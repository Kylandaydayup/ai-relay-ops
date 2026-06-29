#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
k8s_database="${K8S_NEWAPI_DATABASE:-newapi}"
k8s_owner="${K8S_NEWAPI_OWNER:-newapi}"
k8s_deployment="${K8S_NEWAPI_DEPLOYMENT:-relay-new-api}"
docker_postgres_container="${DOCKER_NEWAPI_POSTGRES_CONTAINER:-new-api-postgres}"
docker_database="${DOCKER_NEWAPI_DATABASE:-new_api}"
docker_user="${DOCKER_NEWAPI_USER:-newapi}"
backup_root="${BACKUP_ROOT:-/root/platform-backups}"
public_base_url="${PUBLIC_BASE_URL:-http://api.nexushome.top}"
compat_public_base_urls="${NEWAPI_EXTRA_PUBLIC_BASE_URLS:-http://139.196.254.8}"
casdoor_public_base_url="${CASDOOR_PUBLIC_BASE_URL:-http://auth.nexushome.top}"
newapi_oauth_slug="${NEWAPI_CASDOOR_OAUTH_SLUG:-ymmjc}"
timestamp="$(date +%Y%m%d%H%M%S)"
backup_dir="${backup_root}/newapi-docker-to-k8s-${timestamp}"
old_dump="${backup_dir}/docker-newapi.dump"
k8s_dump="${backup_dir}/k8s-newapi-before.dump"

export KUBECONFIG="$kubeconfig"

case "$newapi_oauth_slug" in
  ""|*[!A-Za-z0-9_-]*)
    echo "invalid NEWAPI_CASDOOR_OAUTH_SLUG: $newapi_oauth_slug" >&2
    exit 2
    ;;
esac

mkdir -p "$backup_dir"

echo "backup dir: $backup_dir"
echo "dumping current K8s new-api database..."
kubectl exec -n "$namespace" "$postgres_pod" -- \
  pg_dump -U postgres -d "$k8s_database" --format=custom --no-owner --no-privileges > "$k8s_dump"

echo "dumping legacy Docker new-api database..."
docker exec "$docker_postgres_container" \
  pg_dump -U "$docker_user" -d "$docker_database" --format=custom --no-owner --no-privileges > "$old_dump"

previous_replicas="$(kubectl get deployment -n "$namespace" "$k8s_deployment" -o jsonpath='{.spec.replicas}')"
if [ -z "$previous_replicas" ]; then
  previous_replicas=1
fi

restore_deployment() {
  kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas="$previous_replicas" >/dev/null 2>&1 || true
}
trap restore_deployment EXIT

echo "scaling K8s new-api deployment to zero..."
kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas=0
kubectl rollout status deployment/"$k8s_deployment" -n "$namespace" --timeout=120s || true

echo "resetting K8s new-api schema..."
kubectl exec -n "$namespace" "$postgres_pod" -- psql -U postgres -d "$k8s_database" -v ON_ERROR_STOP=1 \
  -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; ALTER SCHEMA public OWNER TO ${k8s_owner}; GRANT ALL ON SCHEMA public TO ${k8s_owner}; GRANT ALL ON SCHEMA public TO public;"

echo "restoring legacy Docker new-api data into K8s database..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  pg_restore -U postgres -d "$k8s_database" --no-owner --no-privileges --role="$k8s_owner" < "$old_dump"

echo "rewriting new-api Casdoor OAuth endpoints for this environment..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$k8s_database" -v ON_ERROR_STOP=1 \
    -v slug="$newapi_oauth_slug" \
    -v casdoor_base="$casdoor_public_base_url" <<'SQL'
UPDATE custom_oauth_providers
SET authorization_endpoint = :'casdoor_base' || '/login/oauth/authorize',
    token_endpoint = :'casdoor_base' || '/api/login/oauth/access_token',
    user_info_endpoint = :'casdoor_base' || '/api/userinfo',
    enabled = true,
    updated_at = now()
WHERE slug = :'slug';
SQL

provider_count="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$k8s_database" -At \
    -c "SELECT count(*) FROM custom_oauth_providers WHERE slug = '${newapi_oauth_slug}'")"
if [ "$provider_count" != "1" ]; then
  echo "new-api custom OAuth provider slug was not found: $newapi_oauth_slug" >&2
  exit 1
fi

provider_credentials="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$k8s_database" -AtF $'\t' \
    -c "SELECT client_id, client_secret FROM custom_oauth_providers WHERE slug = '${newapi_oauth_slug}' LIMIT 1")"
IFS=$'\t' read -r newapi_client_id newapi_client_secret <<< "$provider_credentials"
if [ -z "$newapi_client_id" ] || [ -z "$newapi_client_secret" ]; then
  echo "missing new-api custom OAuth client credentials after restore" >&2
  exit 1
fi

newapi_redirect_uris="$(
  PUBLIC_BASE_URL="${public_base_url%/}" \
  NEWAPI_EXTRA_PUBLIC_BASE_URLS="$compat_public_base_urls" \
  NEWAPI_CASDOOR_OAUTH_SLUG="$newapi_oauth_slug" \
  python3 - <<'PY'
import json
import os

slug = os.environ["NEWAPI_CASDOOR_OAUTH_SLUG"]
urls = [os.environ["PUBLIC_BASE_URL"]]
urls.extend(u.strip() for u in os.environ.get("NEWAPI_EXTRA_PUBLIC_BASE_URLS", "").split(","))

seen = []
for url in urls:
    url = url.rstrip("/")
    if not url:
        continue
    redirect_uri = f"{url}/oauth/{slug}"
    if redirect_uri not in seen:
        seen.append(redirect_uri)

print(json.dumps(seen, ensure_ascii=False))
PY
)"

echo "ensuring Casdoor application for new-api OAuth callback..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -v ON_ERROR_STOP=1 \
    -v client_id="$newapi_client_id" \
    -v client_secret="$newapi_client_secret" \
    -v public_base_url="$public_base_url" \
    -v redirect_uris="$newapi_redirect_uris" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM application WHERE owner = 'admin' AND name = 'eDream_web'
  ) THEN
    RAISE EXCEPTION 'Casdoor eDream_web application is required as the new-api template';
  END IF;
END $$;

DELETE FROM application WHERE owner = 'admin' AND name = 'new-api';
CREATE TEMP TABLE newapi_app_template AS
  SELECT * FROM application WHERE owner = 'admin' AND name = 'eDream_web';

UPDATE newapi_app_template
SET name = 'new-api',
    display_name = 'New API',
    title = 'New API',
    homepage_url = :'public_base_url',
    organization = 'edream',
    client_id = :'client_id',
    client_secret = :'client_secret',
    redirect_uris = :'redirect_uris',
    signin_url = '',
    signup_url = '';

INSERT INTO application SELECT * FROM newapi_app_template;
SQL

echo "restoring K8s new-api deployment replicas: $previous_replicas"
kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas="$previous_replicas"
trap - EXIT
kubectl rollout status deployment/"$k8s_deployment" -n "$namespace" --timeout=180s

echo "migration complete"
echo "K8s backup: $k8s_dump"
echo "Docker source dump: $old_dump"

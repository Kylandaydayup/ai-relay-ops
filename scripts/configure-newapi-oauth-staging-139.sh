#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
newapi_database="${K8S_NEWAPI_DATABASE:-newapi}"
public_base_url="${PUBLIC_BASE_URL:-http://api.nexushome.top}"
compat_public_base_urls="${NEWAPI_EXTRA_PUBLIC_BASE_URLS:-http://139.196.254.8}"
casdoor_public_base_url="${CASDOOR_PUBLIC_BASE_URL:-http://auth.nexushome.top}"
newapi_oauth_slug="${NEWAPI_CASDOOR_OAUTH_SLUG:-ymmjc}"

trim_trailing_slash() {
  printf '%s' "${1%/}"
}

case "$newapi_oauth_slug" in
  ""|*[!A-Za-z0-9_-]*)
    echo "invalid NEWAPI_CASDOOR_OAUTH_SLUG: $newapi_oauth_slug" >&2
    exit 2
    ;;
esac

public_base_url="$(trim_trailing_slash "$public_base_url")"
casdoor_public_base_url="$(trim_trailing_slash "$casdoor_public_base_url")"

redirect_uris="$(
  PUBLIC_BASE_URL="$public_base_url" \
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

export KUBECONFIG="$kubeconfig"

echo "configuring new-api Casdoor OAuth provider..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$newapi_database" -v ON_ERROR_STOP=1 \
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
  psql -U postgres -d "$newapi_database" -At \
    -c "SELECT count(*) FROM custom_oauth_providers WHERE slug = '${newapi_oauth_slug}'")"
if [ "$provider_count" != "1" ]; then
  echo "new-api custom OAuth provider slug is missing: $newapi_oauth_slug" >&2
  exit 1
fi

provider_credentials="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$newapi_database" -AtF $'\t' \
    -c "SELECT client_id, client_secret FROM custom_oauth_providers WHERE slug = '${newapi_oauth_slug}' LIMIT 1")"
IFS=$'\t' read -r newapi_client_id newapi_client_secret <<< "$provider_credentials"
if [ -z "$newapi_client_id" ] || [ -z "$newapi_client_secret" ]; then
  echo "missing new-api custom OAuth client credentials" >&2
  exit 1
fi

echo "configuring Casdoor new-api application redirect URIs..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -v ON_ERROR_STOP=1 \
    -v client_id="$newapi_client_id" \
    -v client_secret="$newapi_client_secret" \
    -v public_base_url="$public_base_url" \
    -v redirect_uris="$redirect_uris" <<'SQL'
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

"$(dirname "$0")/verify-newapi-oauth-staging-139.sh"

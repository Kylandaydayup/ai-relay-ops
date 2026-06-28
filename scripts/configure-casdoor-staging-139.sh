#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
public_base_url="${PUBLIC_BASE_URL:-http://139.196.254.8}"
crowd_base_path="${CROWD_BASE_PATH:-/zhongchou/}"
crowd_api_callback_path="${CROWD_API_CALLBACK_PATH:-/zhongchou_api/login/oauth2/code/casdoor}"
root_callback_path="${ROOT_CALLBACK_PATH:-/login/oauth2/code/casdoor}"

export KUBECONFIG="$kubeconfig"

crowd_homepage_url="${public_base_url}${crowd_base_path}"
redirect_uris="[\"${public_base_url}${root_callback_path}\",\"${public_base_url}${crowd_api_callback_path}\"]"

echo "configuring Casdoor staging application URLs..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -v ON_ERROR_STOP=1 \
    -v crowd_homepage_url="$crowd_homepage_url" \
    -v redirect_uris="$redirect_uris" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM organization WHERE owner = 'admin' AND name = 'edream'
  ) THEN
    RAISE EXCEPTION 'required Casdoor organization is missing: admin/edream';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM application WHERE owner = 'admin' AND name = 'eDream_web'
  ) THEN
    RAISE EXCEPTION 'required Casdoor application is missing: admin/eDream_web';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM application WHERE owner = 'admin' AND name = 'eDream_app'
  ) THEN
    RAISE EXCEPTION 'required Casdoor application is missing: admin/eDream_app';
  END IF;
END $$;

UPDATE organization
SET website_url = :'crowd_homepage_url',
    default_application = 'eDream_web'
WHERE owner = 'admin' AND name = 'edream';

UPDATE application
SET homepage_url = :'crowd_homepage_url',
    organization = 'edream',
    redirect_uris = :'redirect_uris'
WHERE owner = 'admin' AND name = 'eDream_web';

INSERT INTO casbin_api_rule (ptype, v0, v1, v2, v3, v4, v5)
SELECT 'p', '*', '*', 'POST', '/api/native-sso-complete', '*', '*'
WHERE NOT EXISTS (
  SELECT 1 FROM casbin_api_rule
  WHERE ptype = 'p'
    AND v0 = '*'
    AND v1 = '*'
    AND v2 = 'POST'
    AND v3 = '/api/native-sso-complete'
    AND v4 = '*'
    AND v5 = '*'
);
SQL

configured_count="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d casdoor -At \
    -c "SELECT count(*) FROM organization o JOIN application a ON a.owner = 'admin' AND a.name = 'eDream_web' WHERE o.owner = 'admin' AND o.name = 'edream' AND o.default_application = 'eDream_web' AND a.homepage_url = '${crowd_homepage_url}'")"

if [ "$configured_count" != "1" ]; then
  echo "Casdoor staging application URL verification failed" >&2
  exit 1
fi

echo "Casdoor staging application URLs configured"

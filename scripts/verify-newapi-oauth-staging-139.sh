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

sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}

public_base_url="$(trim_trailing_slash "$public_base_url")"
casdoor_public_base_url="$(trim_trailing_slash "$casdoor_public_base_url")"
expected_authorization_endpoint="${casdoor_public_base_url}/login/oauth/authorize"
expected_token_endpoint="${casdoor_public_base_url}/api/login/oauth/access_token"
expected_user_info_endpoint="${casdoor_public_base_url}/api/userinfo"
expected_redirect_uri="${public_base_url}/oauth/${newapi_oauth_slug}"
slug_sql="$(sql_literal "$newapi_oauth_slug")"
authorization_endpoint_sql="$(sql_literal "$expected_authorization_endpoint")"
token_endpoint_sql="$(sql_literal "$expected_token_endpoint")"
user_info_endpoint_sql="$(sql_literal "$expected_user_info_endpoint")"

export KUBECONFIG="$kubeconfig"

provider_count="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$newapi_database" -At \
    -c "SELECT count(*) FROM custom_oauth_providers WHERE slug = '${slug_sql}' AND enabled = true AND authorization_endpoint = '${authorization_endpoint_sql}' AND token_endpoint = '${token_endpoint_sql}' AND user_info_endpoint = '${user_info_endpoint_sql}';"
)"

if [ "$provider_count" != "1" ]; then
  echo "new-api Casdoor OAuth provider is not configured for ${casdoor_public_base_url}" >&2
  exit 1
fi

check_redirect_uri() {
  local uri=$1
  local count
  local uri_sql

  uri_sql="$(sql_literal "$uri")"

  count="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
    psql -U postgres -d casdoor -At \
      -c "SELECT count(*) FROM application WHERE owner = 'admin' AND name = 'new-api' AND redirect_uris LIKE '%${uri_sql}%';"
  )"

  if [ "$count" != "1" ]; then
    echo "Casdoor new-api application is missing redirect URI: $uri" >&2
    exit 1
  fi
}

check_redirect_uri "$expected_redirect_uri"

IFS=',' read -r -a compat_urls <<< "$compat_public_base_urls"
for compat_url in "${compat_urls[@]}"; do
  compat_url="$(trim_trailing_slash "$compat_url")"
  if [ -n "$compat_url" ]; then
    check_redirect_uri "${compat_url}/oauth/${newapi_oauth_slug}"
  fi
done

echo "new-api Casdoor OAuth staging verification passed"

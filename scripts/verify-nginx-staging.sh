#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
values_file="${1:-$repo_root/nginx/staging/platform.values.env}"
template_file="${2:-$repo_root/nginx/staging/platform.conf.tpl}"
rendered_file="$(mktemp "${TMPDIR:-/tmp}/platform-nginx-verify.XXXXXX.conf")"
trap 'rm -f "$rendered_file"' EXIT

"$repo_root/scripts/render-nginx-config.sh" "$values_file" "$template_file" "$rendered_file"

set -a
# shellcheck disable=SC1090
source "$values_file"
set +a

require_rendered() {
  local expected=$1
  local description=$2

  if ! grep -Fq "$expected" "$rendered_file"; then
    echo "missing rendered nginx rule: $description" >&2
    echo "expected: $expected" >&2
    exit 1
  fi
}

reject_rendered() {
  local unexpected=$1
  local description=$2

  if grep -Fq "$unexpected" "$rendered_file"; then
    echo "unexpected nginx config: $description" >&2
    echo "found: $unexpected" >&2
    exit 1
  fi
}

require_optional_server() {
  local value=$1
  local description=$2

  if [ -n "$value" ]; then
    require_rendered "server_name $value;" "$description"
  fi
}

require_rendered "proxy_pass http://${HOST_UPSTREAM_IP}:${NEWAPI_NODE_PORT};" "new-api upstream is built from the required host/port values"
require_rendered "proxy_pass http://${HOST_UPSTREAM_IP}:${CASDOOR_NODE_PORT}/;" "Casdoor upstream is built from the required host/port values"
require_optional_server "$API_SERVER_NAME" "API domain routes to the k8s new-api public entry"
require_optional_server "$AUTH_SERVER_NAME" "Auth domain routes directly to Casdoor"
require_optional_server "$ZHONGCHOU_SERVER_NAME" "Crowdfunding domain routes directly to EDreamCrowd"
require_optional_server "$ARCREEL_SERVER_NAME" "ArcReel domain is reserved until the product entry is decided"
if [ -n "$ARCREEL_SERVER_NAME" ]; then
  require_rendered "return 404 \"$ARCREEL_SERVER_NAME is not configured yet\\n\";" "ArcReel domain does not accidentally expose new-api"
fi
reject_rendered "window.location.replace(target)" "Casdoor console must not be forced to the crowd frontend"
reject_rendered "__webpack_require__.p=\"/casdoor/\"" "staging should use the auth domain instead of rewriting Casdoor under /casdoor"

if [ -n "$AUTH_SERVER_NAME" ]; then
  require_rendered "return 302 http://$AUTH_SERVER_NAME/\$1;" "IP /casdoor paths are delegated to the auth domain"
fi
if [ -n "$ZHONGCHOU_SERVER_NAME" ]; then
  require_rendered "server_name $ZHONGCHOU_SERVER_NAME;" "crowdfunding domain server exists"
  require_rendered "return 302 ${ZHONGCHOU_BASE_PATH_SLASH};" "crowdfunding domain root opens the packaged /zhongchou app"
fi

echo "nginx staging render verification passed"

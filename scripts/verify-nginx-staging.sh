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

require_optional_server() {
  local value=$1
  local description=$2

  if [ -n "$value" ]; then
    require_rendered "server_name $value;" "$description"
  fi
}

require_rendered "return 302 /casdoor/login/edream;" "Casdoor root opens the staging organization login page"
require_rendered "proxy_pass http://${HOST_UPSTREAM_IP}:${NEWAPI_NODE_PORT};" "new-api upstream is built from the required host/port values"
require_rendered "proxy_pass http://${HOST_UPSTREAM_IP}:${CASDOOR_NODE_PORT}/;" "Casdoor upstream is built from the required host/port values"
require_optional_server "$API_SERVER_NAME" "API domain routes to the k8s new-api public entry"
require_optional_server "$AUTH_SERVER_NAME" "Auth domain routes directly to Casdoor"
require_optional_server "$ZHONGCHOU_SERVER_NAME" "Crowdfunding domain routes directly to EDreamCrowd"
require_optional_server "$ARCREEL_SERVER_NAME" "ArcReel domain is reserved until the product entry is decided"
if [ -n "$ARCREEL_SERVER_NAME" ]; then
  require_rendered "return 404 \"$ARCREEL_SERVER_NAME is not configured yet\\n\";" "ArcReel domain does not accidentally expose new-api"
fi
require_rendered "sub_filter '__webpack_require__.p=\"/\"' '__webpack_require__.p=\"/casdoor/\"';" "Casdoor chunks load from the /casdoor/ base path"
require_rendered "sub_filter '(0,Qe.jsx)(br.VK,{children:' '(0,Qe.jsx)(br.VK,{basename:\"/casdoor\",children:';" "Casdoor React router is mounted under /casdoor"
require_rendered "sub_filter 'return null===e?\"/\":e}function scrollToDiv' 'return!e||\"/\"===e||\"/casdoor\"===e||\"/casdoor/\"===e||e.indexOf(\"/login\")>=0?\"http://139.196.254.8/zhongchou/\":e}function scrollToDiv';" "Direct Casdoor login returns to the staging crowd frontend instead of an empty Casdoor root"
require_rendered "sub_filter 'null!==t&&\"\"!==t?window.location.href=t:c.goToLink(\"/\")' 't&&\"\"!==t&&\"/\"!==t&&\"/casdoor\"!==t&&\"/casdoor/\"!==t&&t.indexOf(\"/login\")<0?window.location.href=t:window.location.href=\"http://139.196.254.8/zhongchou/\"';" "Existing Casdoor sessions return to the staging crowd frontend instead of the empty Casdoor root"
require_rendered "sub_filter '</body>' '<script>(function(){var target=\"http://139.196.254.8/zhongchou/\";setInterval(function(){if(window.location.pathname===\"/casdoor/\"){window.location.replace(target)}},500)})()</script></body>';" "Casdoor SPA root redirects to the staging crowd frontend after client-side navigation"

echo "nginx staging render verification passed"

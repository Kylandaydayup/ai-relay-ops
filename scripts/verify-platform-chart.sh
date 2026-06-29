#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  local path=$1
  if [ ! -f "$repo_root/$path" ]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
}

require_text() {
  local path=$1
  local expected=$2
  local description=$3
  if ! grep -Fq "$expected" "$repo_root/$path"; then
    echo "missing $description in $path" >&2
    echo "expected: $expected" >&2
    exit 1
  fi
}

require_file charts/platform/Chart.yaml
require_file charts/platform/values.yaml
require_file charts/platform/templates/postgres-init-job.yaml
require_file charts/gateway/Chart.yaml
require_file charts/gateway/values.yaml
require_file charts/gateway/templates/configmap.yaml
require_file charts/gateway/templates/deployment.yaml
require_file charts/gateway/templates/service.yaml
require_file environments/staging/platform.values.yaml

require_text charts/platform/Chart.yaml "repository: file://../gateway" "gateway dependency"
require_text charts/platform/Chart.yaml "repository: file://../new-api" "new-api dependency"
require_text charts/platform/Chart.yaml "repository: file://../edreamcrowd" "EDreamCrowd dependency"
require_text charts/platform/templates/postgres-init-job.yaml "CREATE DATABASE" "database bootstrap job"
require_text charts/platform/templates/postgres-init-job.yaml "broker_db" "broker database bootstrap"

require_text charts/postgres/templates/_helpers.tpl "postgres.instance" "Postgres instance override helper"
require_text charts/new-api/templates/_helpers.tpl "new-api.instance" "new-api instance override helper"
require_text charts/broker/templates/_helpers.tpl "broker.instance" "broker instance override helper"
require_text charts/casdoor/templates/_helpers.tpl "casdoor.instance" "Casdoor instance override helper"
require_text charts/edreamcrowd/templates/_helpers.tpl "edreamcrowd.instance" "EDreamCrowd instance override helper"
require_text environments/staging/platform.values.yaml "instanceOverride: platform-db" "Postgres existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: relay-new-api" "new-api existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: relay-broker" "Broker existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: casdoor" "Casdoor existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: edreamcrowd" "EDreamCrowd existing release selector preservation"

require_text charts/gateway/templates/configmap.yaml "sub_filter '__webpack_require__.p=\"/\"'" "Casdoor chunk path rewrite"
require_text charts/gateway/templates/configmap.yaml "return null===e?\"{{ .Values.casdoor.basePathSlash }}\":e" "Casdoor direct login stays in the console"
require_text charts/gateway/templates/configmap.yaml "c.goToLink(\"{{ .Values.casdoor.basePathSlash }}\")" "Casdoor existing session stays in the console"
require_text charts/gateway/templates/configmap.yaml "proxy_pass {{ .Values.upstreams.newApi }}" "new-api upstream from values"
require_text charts/gateway/templates/configmap.yaml "proxy_pass {{ .Values.upstreams.casdoor }}/" "Casdoor upstream from values"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.api }}" "optional API domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.auth }}" "optional auth domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.zhongchou }}" "optional crowdfunding domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.arcreel }}" "optional ArcReel reserved domain server"
require_text charts/gateway/templates/deployment.yaml "maxSurge: {{ .Values.strategy.rollingUpdate.maxSurge }}" "gateway update strategy maxSurge is values-driven"
require_text charts/gateway/templates/deployment.yaml "maxUnavailable: {{ .Values.strategy.rollingUpdate.maxUnavailable }}" "gateway update strategy maxUnavailable is values-driven"
require_text charts/gateway/templates/deployment.yaml "hostNetwork: {{ .Values.hostNetwork.enabled }}" "hostNetwork switch"
require_text scripts/deploy-platform-staging-139.sh "ADOPT_EXISTING_RELEASES" "existing release adoption switch"
require_text scripts/deploy-platform-staging-139.sh "ALLOW_HOST_GATEWAY_CUTOVER=1" "explicit host Nginx cutover guard"

require_text environments/staging/platform.values.yaml "http://139.196.254.8/zhongchou/" "139 crowd URL"
require_text environments/staging/platform.values.yaml "relay-new-api" "stable new-api service name"
require_text environments/staging/platform.values.yaml "platform-gateway" "stable gateway name"
require_text environments/staging/platform.values.yaml "repository: edreamcrowd-frontend" "139 gateway image that is already present in containerd"
require_text environments/staging/platform.values.yaml "api.nexushome.top" "staging API domain"
require_text environments/staging/platform.values.yaml "auth.nexushome.top" "staging auth domain"
require_text environments/staging/platform.values.yaml "zhongchou.nexushome.top" "staging crowdfunding domain"
require_text environments/staging/platform.values.yaml "maxSurge: 0" "staging gateway avoids host port surge conflicts"

echo "platform chart verification passed"

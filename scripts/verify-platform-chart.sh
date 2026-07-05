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

forbid_text() {
  local path=$1
  local forbidden=$2
  local description=$3
  if grep -Fq "$forbidden" "$repo_root/$path"; then
    echo "unexpected $description in $path" >&2
    echo "forbidden: $forbidden" >&2
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
require_file charts/newapi-compat-gateway/Chart.yaml
require_file charts/newapi-compat-gateway/values.yaml
require_file charts/newapi-compat-gateway/templates/deployment.yaml
require_file charts/newapi-compat-gateway/templates/service.yaml
require_file charts/broker/templates/model-recharge-sync-cronjob.yaml
require_file charts/ai-provider-adapter/Chart.yaml
require_file charts/ai-provider-adapter/values.yaml
require_file charts/ai-provider-adapter/templates/deployment.yaml
require_file charts/ai-provider-adapter/templates/service.yaml
require_file charts/ai-provider-adapter/templates/secret.yaml
require_file environments/staging/platform.values.yaml

require_text charts/platform/Chart.yaml "repository: file://../gateway" "gateway dependency"
require_text charts/platform/Chart.yaml "repository: file://../new-api" "new-api dependency"
require_text charts/platform/Chart.yaml "repository: file://../edreamcrowd" "EDreamCrowd dependency"
require_text charts/platform/Chart.yaml "repository: file://../ai-provider-adapter" "AI provider adapter dependency"
require_text charts/platform/Chart.yaml "repository: file://../newapi-compat-gateway" "NewAPI compatibility gateway dependency"
require_text build/images.env.example "BUILD_AI_PROVIDER_ADAPTER" "AI provider adapter image build switch"
require_text scripts/build-platform-images.sh "BUILD_AI_PROVIDER_ADAPTER" "AI provider adapter image build script branch"
require_text build/images.env.example "Dockerfile.ai-provider-adapter" "AI provider adapter Dockerfile in broker repo"
require_text build/images.env.example "BUILD_NEWAPI_COMPAT_GATEWAY" "NewAPI compatibility gateway image build switch"
require_text scripts/build-platform-images.sh "BUILD_NEWAPI_COMPAT_GATEWAY" "NewAPI compatibility gateway image build script branch"
require_text build/images.env.example "Dockerfile.newapi-compat-gateway" "NewAPI compatibility gateway Dockerfile in broker repo"
require_text scripts/materialize-platform-values.py "MOMA_SEEDANCE_API_KEY" "AI provider adapter materialized MOMA key"
require_text scripts/materialize-platform-values.py "KEYIYUN_API_KEY" "AI provider adapter materialized Keyiyun key"
require_text versions.lock.yaml "ai-provider-adapter" "AI provider adapter version lock"
require_text docs/platform-bundle.md "ai-provider-adapter" "AI provider adapter bundle docs"
require_text charts/platform/templates/postgres-init-job.yaml "CREATE DATABASE" "database bootstrap job"
require_text charts/platform/templates/postgres-init-job.yaml "broker_db" "broker database bootstrap"
require_text charts/new-api/templates/pvc.yaml '"helm.sh/resource-policy": keep' "new-api data PVC keep policy"
require_text charts/postgres/templates/statefulset.yaml '"helm.sh/resource-policy": keep' "Postgres data PVC keep policy"

require_text charts/postgres/templates/_helpers.tpl "postgres.instance" "Postgres instance override helper"
require_text charts/new-api/templates/_helpers.tpl "new-api.instance" "new-api instance override helper"
require_text charts/broker/templates/_helpers.tpl "broker.instance" "broker instance override helper"
require_text charts/casdoor/templates/_helpers.tpl "casdoor.instance" "Casdoor instance override helper"
require_text charts/edreamcrowd/templates/_helpers.tpl "edreamcrowd.instance" "EDreamCrowd instance override helper"
require_text environments/staging/platform.values.yaml "instanceOverride: platform-db" "Postgres existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: relay-new-api" "new-api existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: relay-broker" "Broker existing release selector preservation"
require_text charts/broker/templates/model-recharge-sync-cronjob.yaml "/internal/casdoor/model-recharge-orders/sync" "Broker model recharge order sync CronJob"
require_text charts/broker/templates/deployment.yaml "CASDOOR_DATABASE_URL" "Broker Casdoor database URL secret"
require_text charts/broker/values.yaml "OFFICIAL_PROVIDER_PUBLIC_BASE_URL" "Broker official provider public base URL"
require_text scripts/deploy-platform-staging-139.sh "BROKER_CASDOOR_DATABASE_URL" "Broker Casdoor database URL deploy override"
require_text scripts/deploy-platform-staging-139.sh "ai-provider-adapter.secret.MOMA_SEEDANCE_API_KEY" "AI provider adapter deploy secret override"
require_text scripts/install-platform-bundle.sh "deployment/ai-provider-adapter" "AI provider adapter bundle rollout wait"
require_text scripts/install-platform-bundle.sh "preflight_existing_resources" "bundle install preflight for existing non-Helm resources"
require_text scripts/install-platform-bundle.sh "meta.helm.sh/release-name" "bundle install preflight checks Helm release ownership"
require_text scripts/install-platform-bundle.sh "rollout_status_if_exists" "bundle rollout waits only for rendered or existing workloads"
forbid_text scripts/package-platform-bundle.sh "configure-newapi-provider-adapter-139.sh" "139-only New API channel config script in portable bundle packaging"
forbid_text scripts/package-platform-bundle.sh "verify-newapi-provider-adapter-139.sh" "139-only New API channel verifier script in portable bundle packaging"
require_text environments/staging/platform.values.yaml "namespace: platform" "bundle namespace is values-driven"
require_text scripts/install-platform-bundle.sh "read_values_namespace" "bundle deploy reads namespace from values"
require_text environments/staging/platform.values.yaml "MODEL_RECHARGE_WALLET_GROUP: all" "shared model recharge wallet group"
require_text environments/staging/platform.values.yaml "MODEL_RECHARGE_QUOTA_PER_CNY: \"100\"" "model recharge uses cent-precision quota units"
require_text environments/staging/platform.values.yaml "NEWAPI_MANAGED_TOKEN_QUOTA_MULTIPLIER: \"5000\"" "new-api managed token quota multiplier matches cent-precision broker units"
require_text environments/staging/platform.values.yaml "NEWAPI_PUBLIC_BASE_URL: http://api.nexushome.top" "Desktop official provider public new-api URL"
require_text environments/staging/platform.values.yaml "DESKTOP_PUBLIC_CONFIG_JSON:" "Broker runtime Desktop public config"
require_text environments/staging/platform.values.yaml "\"mediaBaseUrl\":\"http://arcreel-api.nexushome.top/v1\"" "Desktop runtime official media base URL"
require_text environments/staging/platform.values.yaml "\"agentMessagesUrl\":\"http://api.nexushome.top\"" "Desktop runtime official agent messages root URL"
require_text environments/staging/platform.values.yaml '{"id":"qwen/qwen3.7-max","name":"Qwen3.7 Max"' "long-context text model is first in broker catalog"
require_text environments/staging/platform.values.yaml '"id":"MiniMax-M2.5","name":"MiniMax M2.5","capabilities":["text"],"agent_default":true' "official agent uses long-context MiniMax model"
require_text environments/staging/platform.values.yaml "instanceOverride: casdoor" "Casdoor existing release selector preservation"
require_text environments/staging/platform.values.yaml "instanceOverride: edreamcrowd" "EDreamCrowd existing release selector preservation"

require_text charts/gateway/templates/configmap.yaml "sub_filter '__webpack_require__.p=\"/\"'" "Casdoor chunk path rewrite"
require_text charts/gateway/templates/configmap.yaml "return null===e?\"{{ .Values.casdoor.basePathSlash }}\":e" "Casdoor direct login stays in the console"
require_text charts/gateway/templates/configmap.yaml "c.goToLink(\"{{ .Values.casdoor.basePathSlash }}\")" "Casdoor existing session stays in the console"
require_text charts/gateway/templates/configmap.yaml "proxy_pass {{ .Values.upstreams.newApi }}" "new-api upstream from values"
require_text charts/gateway/templates/configmap.yaml "proxy_pass {{ .Values.upstreams.newapiCompat }}" "NewAPI compatibility gateway upstream from values"
require_text charts/gateway/templates/configmap.yaml "proxy_pass {{ .Values.upstreams.casdoor }}/" "Casdoor upstream from values"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.api }}" "optional API domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.newapiCompat }}" "optional NewAPI compatibility gateway domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.auth }}" "optional auth domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.zhongchou }}" "optional crowdfunding domain server"
require_text charts/gateway/templates/configmap.yaml "server_name {{ .Values.domains.arcreel }}" "optional ArcReel reserved domain server"
require_text charts/gateway/templates/configmap.yaml 'return 302 http://{{ .Values.domains.auth }}/$1$is_args$args;' "IP /casdoor routes are delegated to the auth domain with OAuth query preserved"
require_text scripts/configure-newapi-oauth-staging-139.sh "http://auth.nexushome.top" "new-api OAuth configuration uses the auth domain"
require_text scripts/configure-newapi-oauth-staging-139.sh "http://api.nexushome.top" "new-api OAuth callback uses the API domain"
require_text scripts/configure-newapi-provider-adapter-139.sh "Keyiyun VEO via Adapter" "New API Keyiyun VEO adapter backup channel"
require_text scripts/configure-newapi-provider-adapter-139.sh "MOMA_SEEDANCE_CHANNEL_ID" "New API MOMA adapter channel override"
require_text scripts/verify-newapi-provider-adapter-139.sh "ai-provider-adapter.platform.svc.cluster.local" "New API adapter channel verifier"
require_text charts/gateway/templates/configmap.yaml "location = / {" "crowdfunding domain has an explicit root route"
require_text charts/gateway/templates/configmap.yaml "return 302 {{ .Values.edreamcrowd.basePathSlash }};" "crowdfunding domain root opens the packaged /zhongchou app"
require_text charts/gateway/templates/deployment.yaml "maxSurge: {{ .Values.strategy.rollingUpdate.maxSurge }}" "gateway update strategy maxSurge is values-driven"
require_text charts/gateway/templates/deployment.yaml "maxUnavailable: {{ .Values.strategy.rollingUpdate.maxUnavailable }}" "gateway update strategy maxUnavailable is values-driven"
require_text charts/gateway/templates/deployment.yaml "hostNetwork: {{ .Values.hostNetwork.enabled }}" "hostNetwork switch"
require_text scripts/deploy-platform-staging-139.sh "ADOPT_EXISTING_RELEASES" "existing release adoption switch"
require_text scripts/deploy-platform-staging-139.sh "ALLOW_HOST_GATEWAY_CUTOVER=1" "explicit host Nginx cutover guard"

require_text environments/staging/platform.values.yaml "http://zhongchou.nexushome.top/zhongchou/" "139 crowd URL"
require_text environments/staging/platform.values.yaml "relay-new-api" "stable new-api service name"
require_text environments/staging/platform.values.yaml "platform-gateway" "stable gateway name"
require_text environments/staging/platform.values.yaml "ai-provider-adapter:" "AI provider adapter staging values"
require_text environments/staging/platform.values.yaml "AI_PROVIDER_ADAPTER_MODEL_PROVIDER_MAP" "AI provider adapter model routing map"
require_text environments/staging/platform.values.yaml "newapi-compat-gateway:" "NewAPI compatibility gateway staging values"
require_text environments/staging/platform.values.yaml "OFFICIAL_PROVIDER_PUBLIC_BASE_URL: http://arcreel-api.nexushome.top" "official provider returns compatibility gateway base URL"
require_text environments/staging/platform.values.yaml "newapiCompat: arcreel-api.nexushome.top" "staging NewAPI compatibility gateway domain"
require_text environments/staging/platform.values.yaml "repository: edreamcrowd-frontend" "139 gateway image that is already present in containerd"
require_text environments/staging/platform.values.yaml "api.nexushome.top" "staging API domain"
require_text environments/staging/platform.values.yaml "auth.nexushome.top" "staging auth domain"
require_text environments/staging/platform.values.yaml "zhongchou.nexushome.top" "staging crowdfunding domain"
require_text environments/staging/platform.values.yaml "maxSurge: 0" "staging gateway avoids host port surge conflicts"

echo "platform chart verification passed"

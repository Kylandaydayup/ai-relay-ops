#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
newapi_database="${K8S_NEWAPI_DATABASE:-newapi}"
adapter_base_url="${AI_PROVIDER_ADAPTER_BASE_URL:-http://ai-provider-adapter.platform.svc.cluster.local}"
moma_channel_id="${MOMA_SEEDANCE_CHANNEL_ID:-3}"
keyiyun_source_channel_id="${KEYIYUN_SOURCE_CHANNEL_ID:-6}"
keyiyun_veo_channel_name="${KEYIYUN_VEO_ADAPTER_CHANNEL_NAME:-Keyiyun VEO via Adapter}"
keyiyun_grok_channel_name="${KEYIYUN_GROK_ADAPTER_CHANNEL_NAME:-Keyiyun Grok via Adapter}"
keyiyun_veo_model="${KEYIYUN_VEO_MODEL:-veo_3_1_fast}"
keyiyun_grok_model="${KEYIYUN_GROK_MODEL:-grok_video3}"

export KUBECONFIG="$kubeconfig"

require_count() {
  local description=$1
  local sql=$2
  local expected=$3
  local count

  count="$(kubectl exec -n "$namespace" "$postgres_pod" -- \
    psql -U postgres -d "$newapi_database" -At -c "$sql")"
  if [ "$count" != "$expected" ]; then
    echo "$description failed: expected $expected, got $count" >&2
    exit 1
  fi
}

require_count \
  "MOMA Seedance channel base_url adapter check" \
  "SELECT count(*) FROM channels WHERE id = ${moma_channel_id} AND base_url = '${adapter_base_url}';" \
  "1"

require_count \
  "Keyiyun original channel untouched by adapter naming check" \
  "SELECT count(*) FROM channels WHERE id = ${keyiyun_source_channel_id} AND name NOT IN ('${keyiyun_veo_channel_name}', '${keyiyun_grok_channel_name}');" \
  "1"

require_count \
  "Keyiyun VEO via-adapter channel check" \
  "SELECT count(*) FROM channels WHERE name = '${keyiyun_veo_channel_name}' AND type = 54 AND base_url = '${adapter_base_url}';" \
  "1"

require_count \
  "Keyiyun Grok via-adapter channel check" \
  "SELECT count(*) FROM channels WHERE name = '${keyiyun_grok_channel_name}' AND type = 54 AND base_url = '${adapter_base_url}';" \
  "1"

require_count \
  "Keyiyun via-adapter abilities check" \
  "SELECT count(DISTINCT channel_id) FROM abilities WHERE channel_id IN (SELECT id FROM channels WHERE name IN ('${keyiyun_veo_channel_name}', '${keyiyun_grok_channel_name}'));" \
  "2"

require_count \
  "Keyiyun VEO model ability check" \
  "SELECT count(*) FROM abilities WHERE model = '${keyiyun_veo_model}' AND channel_id IN (SELECT id FROM channels WHERE name = '${keyiyun_veo_channel_name}');" \
  "1"

require_count \
  "Keyiyun Grok model ability check" \
  "SELECT count(*) FROM abilities WHERE model = '${keyiyun_grok_model}' AND channel_id IN (SELECT id FROM channels WHERE name = '${keyiyun_grok_channel_name}');" \
  "1"

echo "new-api provider adapter channel verification passed"

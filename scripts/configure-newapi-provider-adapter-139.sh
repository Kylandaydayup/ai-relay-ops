#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
newapi_database="${K8S_NEWAPI_DATABASE:-newapi}"
newapi_deployment="${NEWAPI_DEPLOYMENT:-relay-new-api}"
adapter_base_url="${AI_PROVIDER_ADAPTER_BASE_URL:-http://ai-provider-adapter.platform.svc.cluster.local}"
backup_root="${BACKUP_ROOT:-/root/platform-backups}"
restart_newapi="${RESTART_NEWAPI:-true}"

moma_channel_id="${MOMA_SEEDANCE_CHANNEL_ID:-3}"
keyiyun_source_channel_id="${KEYIYUN_SOURCE_CHANNEL_ID:-6}"
keyiyun_veo_channel_name="${KEYIYUN_VEO_ADAPTER_CHANNEL_NAME:-Keyiyun VEO via Adapter}"
keyiyun_grok_channel_name="${KEYIYUN_GROK_ADAPTER_CHANNEL_NAME:-Keyiyun Grok via Adapter}"
keyiyun_veo_model="${KEYIYUN_VEO_MODEL:-veo_3_1_fast}"
keyiyun_grok_model="${KEYIYUN_GROK_MODEL:-grok_video3}"

export KUBECONFIG="$kubeconfig"

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

case "$adapter_base_url" in
  http://*|https://*) ;;
  *)
    echo "invalid AI_PROVIDER_ADAPTER_BASE_URL: must start with http:// or https://" >&2
    exit 2
    ;;
esac

require_command kubectl

timestamp="$(date +%Y%m%d%H%M%S)"
backup_dir="${backup_root%/}/newapi-provider-adapter-${timestamp}"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

echo "backing up New API channels and abilities to $backup_dir ..."
kubectl exec -n "$namespace" "$postgres_pod" -- \
  pg_dump -U postgres -d "$newapi_database" --format=custom --no-owner --no-privileges \
    -t channels -t abilities > "$backup_dir/newapi-channels-abilities.dump"

kubectl exec -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$newapi_database" -AtF $'\t' \
    -c "SELECT id,name,type,status,base_url,models,\"group\" FROM channels ORDER BY id;" \
  | awk -F '\t' 'BEGIN{OFS="\t"} {print $1,$2,$3,$4,$5,$6,$7}' \
  > "$backup_dir/channels-redacted.tsv"

echo "configuring MOMA Seedance channel and Keyiyun via-adapter backup channels..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  psql -U postgres -d "$newapi_database" -v ON_ERROR_STOP=1 \
    -v adapter_base_url="$adapter_base_url" \
    -v moma_channel_id="$moma_channel_id" \
    -v keyiyun_source_channel_id="$keyiyun_source_channel_id" \
    -v keyiyun_veo_channel_name="$keyiyun_veo_channel_name" \
    -v keyiyun_grok_channel_name="$keyiyun_grok_channel_name" \
    -v keyiyun_veo_model="$keyiyun_veo_model" \
    -v keyiyun_grok_model="$keyiyun_grok_model" <<'SQL'
SELECT EXISTS (SELECT 1 FROM channels WHERE id = :'moma_channel_id'::int) AS moma_channel_exists \gset
\if :moma_channel_exists
\else
  \echo 'MOMA Seedance channel is missing'
  \quit 3
\endif

SELECT EXISTS (SELECT 1 FROM channels WHERE id = :'keyiyun_source_channel_id'::int) AS keyiyun_source_channel_exists \gset
\if :keyiyun_source_channel_exists
\else
  \echo 'Keyiyun source channel is missing'
  \quit 3
\endif

UPDATE channels
SET base_url = :'adapter_base_url'
WHERE id = :'moma_channel_id'::int;

CREATE TEMP TABLE desired_adapter_channels (
  name text PRIMARY KEY,
  model text NOT NULL
);

INSERT INTO desired_adapter_channels(name, model)
VALUES
  (:'keyiyun_veo_channel_name', :'keyiyun_veo_model'),
  (:'keyiyun_grok_channel_name', :'keyiyun_grok_model');

INSERT INTO channels (
  type,
  "key",
  status,
  name,
  weight,
  created_time,
  test_time,
  response_time,
  base_url,
  other,
  balance,
  balance_updated_time,
  models,
  "group",
  used_quota,
  priority,
  auto_ban,
  channel_info,
  other_info,
  settings
)
SELECT
  54,
  source."key",
  1,
  desired.name,
  source.weight,
  EXTRACT(EPOCH FROM now())::bigint,
  0,
  0,
  :'adapter_base_url',
  COALESCE(source.other, ''),
  0,
  0,
  desired.model,
  COALESCE(NULLIF(source."group", ''), 'default'),
  0,
  source.priority,
  source.auto_ban,
  '{}'::json,
  '',
  ''
FROM desired_adapter_channels desired
CROSS JOIN channels source
WHERE source.id = :'keyiyun_source_channel_id'::int
  AND NOT EXISTS (SELECT 1 FROM channels existing WHERE existing.name = desired.name);

UPDATE channels target
SET type = 54,
    "key" = source."key",
    status = 1,
    base_url = :'adapter_base_url',
    models = desired.model,
    "group" = COALESCE(NULLIF(source."group", ''), 'default'),
    priority = source.priority,
    weight = source.weight,
    auto_ban = source.auto_ban
FROM desired_adapter_channels desired
CROSS JOIN channels source
WHERE source.id = :'keyiyun_source_channel_id'::int
  AND target.name = desired.name;

DELETE FROM abilities
WHERE channel_id IN (
  SELECT id FROM channels WHERE name IN (SELECT name FROM desired_adapter_channels)
);

INSERT INTO abilities ("group", model, channel_id, enabled, priority, weight, tag)
SELECT DISTINCT
  btrim(group_name) AS "group",
  btrim(model_name) AS model,
  c.id AS channel_id,
  c.status = 1 AS enabled,
  c.priority,
  COALESCE(c.weight, 0),
  c.tag
FROM channels c
CROSS JOIN LATERAL unnest(string_to_array(c."group", ',')) AS group_name
CROSS JOIN LATERAL unnest(string_to_array(c.models, ',')) AS model_name
WHERE c.name IN (SELECT name FROM desired_adapter_channels)
  AND btrim(group_name) <> ''
  AND btrim(model_name) <> '';
SQL

"$(dirname "$0")/verify-newapi-provider-adapter-139.sh"

if [ "$restart_newapi" = "true" ]; then
  echo "restarting New API deployment to refresh channel cache..."
  kubectl rollout restart deployment/"$newapi_deployment" -n "$namespace"
  kubectl rollout status deployment/"$newapi_deployment" -n "$namespace" --timeout=180s
fi

echo "New API provider adapter channel configuration completed; backup: $backup_dir"

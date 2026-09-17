#!/usr/bin/env bash
set -euo pipefail
umask 077

apply=0
if [ "$#" -eq 3 ] && [ "$3" = "--apply" ]; then
  apply=1
  set -- "$1" "$2"
fi
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig
require_command helm
require_command kubectl
require_command python3
python3 -c 'import yaml' >/dev/null

if ! helm_release_exists; then
  echo "release does not exist; use install first" >&2
  exit 2
fi
enabled="$(yaml_get "$DEPLOYMENT_FILE" ai-provider-adapter.enabled true)"
create_secret="$(yaml_get "$DEPLOYMENT_FILE" ai-provider-adapter.secret.create true)"
if [[ "$enabled" != "true" && "$enabled" != "True" ]] || \
   [[ "$create_secret" != "false" && "$create_secret" != "False" ]]; then
  echo "adapter-only upgrades require an enabled adapter with secret.create=false" >&2
  exit 2
fi
adapter="$(yaml_get "$DEPLOYMENT_FILE" ai-provider-adapter.fullnameOverride "")"
if [ -z "$adapter" ]; then
  echo "ai-provider-adapter.fullnameOverride is required" >&2
  exit 2
fi

backup_root="${ADAPTER_BACKUP_ROOT:-$HOME/edream-backups}"
mkdir -p "$backup_root"
backup="$(mktemp -d "$backup_root/${ENV_NAME}-adapter-$(date '+%Y%m%d-%H%M%S').XXXXXX")"
echo "Protected review/backup directory: $backup"
cp "$DEPLOYMENT_FILE" "$backup/deployment-values.yaml"
helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" > "$backup/saved-manifest.yaml"
helm get values "$RELEASE_NAME" -n "$NAMESPACE" -a -o json > "$backup/saved-values.json"
helm history "$RELEASE_NAME" -n "$NAMESPACE" -o json > "$backup/helm-history.json"
kubectl get pods -n "$NAMESPACE" -o json > "$backup/pods-before.json"
"$OPS_ROOT/scripts/platform/preflight.sh" -f "$backup/deployment-values.yaml"
helm template "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" --is-upgrade \
  -f "$backup/deployment-values.yaml" > "$backup/desired-manifest.yaml"
python3 "$OPS_ROOT/scripts/platform/check-adapter-upgrade.py" \
  --saved "$backup/saved-manifest.yaml" --desired "$backup/desired-manifest.yaml" \
  --namespace "$NAMESPACE" --release "$RELEASE_NAME" --adapter "$adapter" \
  --snapshot "$backup/live-resources.json"
helm upgrade "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" \
  -f "$backup/deployment-values.yaml" --no-hooks --dry-run=server --hide-secret \
  > "$backup/helm-dry-run.txt"
if [ "$apply" = "0" ]; then
  echo "Preflight passed. No workload changed. Run again with --apply after review."
  exit 0
fi

# The old Helm revision can predate emergency fixes; do not auto-roll it back.
helm upgrade "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" \
  -f "$backup/deployment-values.yaml" --no-hooks --wait --timeout="${ROLLOUT_TIMEOUT:-600s}"
kubectl rollout status "deployment/$adapter" -n "$NAMESPACE" --timeout="${ROLLOUT_TIMEOUT:-600s}"
helm get values "$RELEASE_NAME" -n "$NAMESPACE" -a -o json > "$backup/applied-values.json"
kubectl get pods -n "$NAMESPACE" -o json > "$backup/pods-after.json"
echo "Helm state updated. Perform the business smoke tests in docs/adapter-maintenance.md."

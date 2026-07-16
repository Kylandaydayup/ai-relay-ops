#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig

require_command helm
require_command kubectl

if ! helm_release_exists; then
  echo "release does not exist: $RELEASE_NAME in $NAMESPACE" >&2
  exit 2
fi

delete_data="${DELETE_DATA:-0}"
backup_dir="${BACKUP_DIR:-$OPS_ROOT/dist/platform-backups/${ENV_NAME}-$(date '+%Y%m%d%H%M%S')}"

if [ "$delete_data" != "1" ]; then
  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  resources=()
  while IFS= read -r resource; do
    [ -n "$resource" ] && resources+=("$resource")
  done < <(kept_resources)
  while IFS= read -r pvc; do
    [ -n "$pvc" ] && resources+=("pvc/$pvc")
  done < <(postgres_pvc_resources | sed 's#^pvc/##')

  if [ "${#resources[@]}" -gt 0 ]; then
    kubectl get -n "$NAMESPACE" "${resources[@]}" -o yaml > "$backup_dir/kept-resources.yaml" 2>/dev/null || true
    chmod 600 "$backup_dir/kept-resources.yaml" 2>/dev/null || true
    for resource in "${resources[@]}"; do
      kubectl annotate -n "$NAMESPACE" "$resource" helm.sh/resource-policy=keep --overwrite >/dev/null 2>&1 || true
    done
  fi

  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"

  echo "platform uninstalled and data resources kept: env=$ENV_NAME release=$RELEASE_NAME backup=$backup_dir"
  exit 0
fi

if [ "${CONFIRM_DELETE_DATA:-}" != "delete-$ENV_NAME" ]; then
  if [ -t 0 ]; then
    printf 'Type delete-%s to uninstall and delete data resources: ' "$ENV_NAME" >&2
    read -r answer
    if [ "$answer" != "delete-$ENV_NAME" ]; then
      echo "aborted" >&2
      exit 2
    fi
  else
    echo "set CONFIRM_DELETE_DATA=delete-$ENV_NAME to delete data resources" >&2
    exit 2
  fi
fi

helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
for resource in $(postgres_pvc_resources); do
  kubectl delete -n "$NAMESPACE" "$resource" --ignore-not-found
done
for resource in $(kept_resources); do
  kubectl delete -n "$NAMESPACE" "$resource" --ignore-not-found
done

echo "platform uninstalled and data resources deleted: env=$ENV_NAME release=$RELEASE_NAME"

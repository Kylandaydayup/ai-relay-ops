#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig

"$(dirname "${BASH_SOURCE[0]}")/preflight.sh" "$ENV_NAME"

if ! helm_release_exists; then
  echo "release does not exist, use install first: $RELEASE_NAME in $NAMESPACE" >&2
  exit 2
fi

helm upgrade "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" -f "$DEPLOYMENT_FILE"
wait_rollouts

echo "platform upgraded: env=$ENV_NAME release=$RELEASE_NAME namespace=$NAMESPACE"

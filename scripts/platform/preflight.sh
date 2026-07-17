#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig

require_command helm
require_command kubectl

if grep -q "CHANGE_ME" "$DEPLOYMENT_FILE"; then
  echo "deployment file still contains CHANGE_ME placeholders: $DEPLOYMENT_FILE" >&2
  exit 2
fi

helm_dependency_build
manifest_file="$(mktemp -t edream-platform-manifest.XXXXXX.yaml)"
trap 'rm -f "$manifest_file"' EXIT
helm template "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" -f "$DEPLOYMENT_FILE" >"$manifest_file"
verify_rendered_manifest "$manifest_file"
verify_external_resources

echo "preflight passed: env=$ENV_NAME release=$RELEASE_NAME namespace=$NAMESPACE"

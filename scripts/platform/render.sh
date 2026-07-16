#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig

require_command helm

helm_dependency_build
helm template "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" -f "$DEPLOYMENT_FILE"

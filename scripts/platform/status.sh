#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"
ensure_kubeconfig

require_command helm
require_command kubectl

helm status "$RELEASE_NAME" -n "$NAMESPACE"
kubectl get pods,svc,deploy,statefulset,cronjob,pvc -n "$NAMESPACE"

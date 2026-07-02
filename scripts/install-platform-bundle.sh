#!/usr/bin/env bash
set -euo pipefail

bundle_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release="${RELEASE:-platform}"
values_file="${VALUES_FILE:-$bundle_root/values/values.yaml}"
load_images="${LOAD_IMAGES:-false}"
wait_rollout="${WAIT_ROLLOUT:-true}"
helm_args="${HELM_ARGS:-}"

if [ -z "${KUBECONFIG:-}" ] && [ -f /etc/rancher/k3s/k3s.yaml ]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
fi

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

require_command helm
require_command kubectl

if [ ! -f "$values_file" ]; then
  echo "missing values file: $values_file" >&2
  exit 2
fi

if grep -R "CHANGE_ME" "$values_file" >/dev/null 2>&1; then
  echo "values file still contains CHANGE_ME placeholders: $values_file" >&2
  exit 2
fi

read_values_namespace() {
  awk '
    /^[[:space:]]*#/ { next }
    /^namespace:[[:space:]]*/ {
      value = $0
      sub(/^namespace:[[:space:]]*/, "", value)
      gsub(/["'\'']/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$values_file"
}

namespace="${NAMESPACE:-$(read_values_namespace)}"
namespace="${namespace:-platform}"

if [ "$load_images" = "true" ]; then
  "$bundle_root/scripts/load-platform-images.sh"
fi

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
helm dependency build "$bundle_root/charts/platform"

# shellcheck disable=SC2086
helm upgrade --install "$release" "$bundle_root/charts/platform" \
  -n "$namespace" \
  -f "$values_file" \
  $helm_args

if [ "$wait_rollout" = "true" ]; then
  kubectl rollout status statefulset/platform-postgres -n "$namespace" --timeout=240s || true
  kubectl rollout status deployment/relay-new-api -n "$namespace" --timeout=180s || true
  kubectl rollout status deployment/relay-broker -n "$namespace" --timeout=180s || true
  kubectl rollout status deployment/casdoor -n "$namespace" --timeout=180s || true
  kubectl rollout status deployment/edreamcrowd-backend -n "$namespace" --timeout=240s || true
  kubectl rollout status deployment/edreamcrowd-frontend -n "$namespace" --timeout=180s || true
  kubectl rollout status deployment/platform-gateway -n "$namespace" --timeout=180s || true
fi

echo "platform release installed or upgraded: $release in namespace $namespace"

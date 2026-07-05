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

preflight_existing_resources() {
  local failures=()
  local rendered_resource
  local kind
  local name
  local resource_ns
  local existing_release
  local existing_namespace
  local managed_by
  local manifest_file

  manifest_file="$(mktemp)"
  helm template "$release" "$bundle_root/charts/platform" -n "$namespace" -f "$values_file" >"$manifest_file"

  while IFS=$'\t' read -r kind name resource_ns; do
    if [ -z "$kind" ] || [ -z "$name" ]; then
      continue
    fi
    rendered_resource="$kind/$name"
    if ! kubectl get -n "$resource_ns" "$rendered_resource" >/dev/null 2>&1; then
      continue
    fi

    # Check meta.helm.sh/release-name and meta.helm.sh/release-namespace before Helm can fail mid-install.
    existing_release="$(kubectl get -n "$resource_ns" "$rendered_resource" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)"
    existing_namespace="$(kubectl get -n "$resource_ns" "$rendered_resource" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"
    managed_by="$(kubectl get -n "$resource_ns" "$rendered_resource" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)"

    if [ "$existing_release" != "$release" ] || [ "$existing_namespace" != "$namespace" ] || [ "$managed_by" != "Helm" ]; then
      failures+=("$resource_ns $rendered_resource existing release=${existing_release:-<none>} namespace=${existing_namespace:-<none>} managed-by=${managed_by:-<none>}")
    fi
  done < <(
    python3 - "$namespace" "$manifest_file" <<'PY'
import re
import sys

default_namespace = sys.argv[1]
manifest_file = sys.argv[2]

with open(manifest_file, encoding="utf-8") as handle:
    text = handle.read()

for raw_doc in re.split(r"^---[ \t]*$", text, flags=re.MULTILINE):
    kind = name = namespace = None
    in_metadata = False
    metadata_indent = None

    for line in raw_doc.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()

        if indent == 0 and stripped.startswith("kind:"):
            kind = stripped.split(":", 1)[1].strip().strip("\"'")
            in_metadata = False
            continue

        if indent == 0 and stripped == "metadata:":
            in_metadata = True
            metadata_indent = indent
            continue

        if in_metadata and metadata_indent is not None and indent <= metadata_indent:
            in_metadata = False

        if in_metadata and stripped.startswith("name:") and name is None:
            name = stripped.split(":", 1)[1].strip().strip("\"'")
            continue

        if in_metadata and stripped.startswith("namespace:") and namespace is None:
            namespace = stripped.split(":", 1)[1].strip().strip("\"'")

    if kind and name:
        print(f"{kind}\t{name}\t{namespace or default_namespace}")
PY
  )

  rm -f "$manifest_file"

  if [ "${#failures[@]}" -gt 0 ]; then
    echo "existing Kubernetes resources conflict with Helm release '$release' in namespace '$namespace':" >&2
    printf '  - %s\n' "${failures[@]}" >&2
    echo "Refusing to install so existing data and workloads are not adopted or overwritten unexpectedly." >&2
    exit 3
  fi
}

rollout_status_if_exists() {
  local resource=$1
  local timeout=$2

  if kubectl get "$resource" -n "$namespace" >/dev/null 2>&1; then
    kubectl rollout status "$resource" -n "$namespace" --timeout="$timeout" || true
  else
    echo "skipping rollout wait for missing $resource in namespace $namespace"
  fi
}

helm dependency build "$bundle_root/charts/platform"
preflight_existing_resources

if [ "$load_images" = "true" ]; then
  "$bundle_root/scripts/load-platform-images.sh"
fi

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

# shellcheck disable=SC2086
helm upgrade --install "$release" "$bundle_root/charts/platform" \
  -n "$namespace" \
  -f "$values_file" \
  $helm_args

if [ "$wait_rollout" = "true" ]; then
  rollout_status_if_exists statefulset/platform-postgres 240s
  rollout_status_if_exists deployment/relay-new-api 180s
  rollout_status_if_exists deployment/ai-provider-adapter 180s
  rollout_status_if_exists deployment/relay-broker 180s
  rollout_status_if_exists deployment/casdoor 180s
  rollout_status_if_exists deployment/edreamcrowd-backend 240s
  rollout_status_if_exists deployment/edreamcrowd-frontend 180s
  rollout_status_if_exists deployment/platform-gateway 180s
fi

echo "platform release installed or upgraded: $release in namespace $namespace"

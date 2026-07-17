#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$OPS_ROOT/scripts/lib/timing.sh"

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

yaml_get() {
  local file=$1
  local path=$2
  local fallback=${3:-}

  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
    file, path, fallback = ARGV
    data = YAML.load_file(file) || {}
    cursor = data
    path.split(".").each do |part|
      if cursor.is_a?(Hash) && cursor.key?(part)
        cursor = cursor[part]
      else
        cursor = nil
        break
      end
    end
    value = cursor.nil? ? fallback : cursor
    print value
    ' "$file" "$path" "$fallback"
    return 0
  fi

  python3 - "$file" "$path" "$fallback" <<'PY'
import sys
import yaml

file_name, path, fallback = sys.argv[1:4]
with open(file_name, encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
cursor = data
for part in path.split("."):
    if isinstance(cursor, dict) and part in cursor:
        cursor = cursor[part]
    else:
        cursor = None
        break
print(fallback if cursor is None else cursor, end="")
PY
}

init_platform_env() {
  start_script_timer "${0##*/}"
  if [ "$#" -eq 1 ] && [ -f "$1" ]; then
    DEPLOYMENT_FILE="$1"
  elif [ "$#" -eq 2 ] && [ "$1" = "-f" ]; then
    DEPLOYMENT_FILE="$2"
  else
    echo "usage: $0 -f <deployment-values.yaml>" >&2
    exit 2
  fi
  if [[ "$DEPLOYMENT_FILE" != /* ]]; then
    DEPLOYMENT_FILE="$OPS_ROOT/$DEPLOYMENT_FILE"
  fi
  CHART_DIR="$OPS_ROOT/charts/platform"

  if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "missing deployment file: $DEPLOYMENT_FILE" >&2
    exit 2
  fi

  RELEASE_NAME="${RELEASE_NAME:-$(yaml_get "$DEPLOYMENT_FILE" deployment.releaseName platform)}"
  NAMESPACE="${NAMESPACE:-$(yaml_get "$DEPLOYMENT_FILE" namespace platform)}"
  ENV_NAME="$(basename "$(dirname "$DEPLOYMENT_FILE")")"

  if [ -z "$RELEASE_NAME" ] || [ -z "$NAMESPACE" ]; then
    echo "deployment.releaseName and namespace are required in $DEPLOYMENT_FILE" >&2
    exit 2
  fi
}

ensure_kubeconfig() {
  if [ -z "${KUBECONFIG:-}" ] && [ -f /etc/rancher/k3s/k3s.yaml ]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  fi
}

helm_dependency_build() {
  helm dependency build "$CHART_DIR"
}

helm_release_exists() {
  helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1
}

rollout_status_if_exists() {
  local resource=$1
  local timeout=${2:-${ROLLOUT_TIMEOUT:-600s}}

  if kubectl get "$resource" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl rollout status "$resource" -n "$NAMESPACE" --timeout="$timeout"
  fi
}

wait_rollouts() {
  local timeout="${ROLLOUT_TIMEOUT:-600s}"
  rollout_status_if_exists statefulset/platform-postgres "$timeout"
  rollout_status_if_exists deployment/relay-new-api "$timeout"
  rollout_status_if_exists deployment/ai-provider-adapter "$timeout"
  rollout_status_if_exists deployment/newapi-compat-gateway "$timeout"
  rollout_status_if_exists deployment/relay-broker "$timeout"
  rollout_status_if_exists deployment/casdoor "$timeout"
  rollout_status_if_exists deployment/edreamcrowd-backend "$timeout"
  rollout_status_if_exists deployment/edreamcrowd-frontend "$timeout"
  rollout_status_if_exists deployment/platform-gateway "$timeout"
}

deployment_images() {
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
    file = ARGV[0]
    data = YAML.load_file(file) || {}
    def dig_hash(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end
    specs = [
      [["postgres"], ["postgres", "enabled"]],
      [["databaseInit"], ["databaseInit", "enabled"]],
      [["new-api"], ["new-api", "enabled"]],
      [["broker"], ["broker", "enabled"]],
      [["ai-provider-adapter"], ["ai-provider-adapter", "enabled"]],
      [["newapi-compat-gateway"], ["newapi-compat-gateway", "enabled"]],
      [["casdoor"], ["casdoor", "enabled"]],
      [["gateway"], ["gateway", "enabled"]],
      [["edreamcrowd", "backend"], ["edreamcrowd", "enabled"]],
      [["edreamcrowd", "frontend"], ["edreamcrowd", "enabled"]]
    ]
    images = []
    specs.each do |path, enabled_path|
      next if dig_hash(data, *enabled_path) == false
      image = dig_hash(data, *path, "image")
      next unless image.is_a?(Hash)
      repository = image["repository"]
      tag = image["tag"]
      next if repository.nil? || repository.empty? || tag.nil? || tag.empty?
      images << "#{repository}:#{tag}"
    end
    puts images.uniq
    ' "$1"
    return 0
  fi

  python3 - "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

def dig(*keys):
    cursor = data
    for key in keys:
        if not isinstance(cursor, dict):
            return None
        cursor = cursor.get(key)
    return cursor

specs = [
    (("postgres",), ("postgres", "enabled")),
    (("databaseInit",), ("databaseInit", "enabled")),
    (("new-api",), ("new-api", "enabled")),
    (("broker",), ("broker", "enabled")),
    (("ai-provider-adapter",), ("ai-provider-adapter", "enabled")),
    (("newapi-compat-gateway",), ("newapi-compat-gateway", "enabled")),
    (("casdoor",), ("casdoor", "enabled")),
    (("gateway",), ("gateway", "enabled")),
    (("edreamcrowd", "backend"), ("edreamcrowd", "enabled")),
    (("edreamcrowd", "frontend"), ("edreamcrowd", "enabled")),
]
images = []
for path, enabled_path in specs:
    if dig(*enabled_path) is False:
        continue
    image = dig(*path, "image")
    if not isinstance(image, dict):
        continue
    repository = image.get("repository")
    tag = image.get("tag")
    if repository and tag:
        images.append(f"{repository}:{tag}")
for image in dict.fromkeys(images):
    print(image)
PY
}

import_image_archive() {
  local image_archive=$1
  echo "loading packaged images: $image_archive"
  if command -v docker >/dev/null 2>&1; then
    docker load -i "$image_archive"
    return 0
  fi
  if command -v k3s >/dev/null 2>&1; then
    k3s ctr -n k8s.io images import "$image_archive"
    return 0
  fi
  if command -v ctr >/dev/null 2>&1; then
    ctr -n k8s.io images import "$image_archive"
    return 0
  fi

  echo "missing image loader: docker, k3s, or ctr is required for packaged images" >&2
  exit 2
}

kept_resources() {
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
    data = YAML.load_file(ARGV[0]) || {}
    def dig_hash(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end
    resource_specs = [
      [["databaseInit", "secret"], "secret", ["databaseInit", "enabled"]],
      [["postgres", "secret"], "secret", ["postgres", "enabled"]],
      [["new-api", "secret"], "secret", ["new-api", "enabled"]],
      [["broker", "secret"], "secret", ["broker", "enabled"]],
      [["ai-provider-adapter", "secret"], "secret", ["ai-provider-adapter", "enabled"]],
      [["edreamcrowd", "backend", "secret"], "secret", ["edreamcrowd", "enabled"]],
      [["casdoor", "config"], "configmap", ["casdoor", "enabled"]]
    ]
    resources = []
    resource_specs.each do |path, kind, enabled_path|
      next if dig_hash(data, *enabled_path) == false
      item = dig_hash(data, *path)
      next unless item.is_a?(Hash)
      name = item["name"]
      resources << "#{kind}/#{name}" if name && !name.empty?
    end
    puts resources.uniq
    ' "$DEPLOYMENT_FILE"
    return 0
  fi

  python3 - "$DEPLOYMENT_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

def dig(*keys):
    cursor = data
    for key in keys:
        if not isinstance(cursor, dict):
            return None
        cursor = cursor.get(key)
    return cursor

resources = []
resource_specs = [
    (("databaseInit", "secret"), "secret", ("databaseInit", "enabled")),
    (("postgres", "secret"), "secret", ("postgres", "enabled")),
    (("new-api", "secret"), "secret", ("new-api", "enabled")),
    (("broker", "secret"), "secret", ("broker", "enabled")),
    (("ai-provider-adapter", "secret"), "secret", ("ai-provider-adapter", "enabled")),
    (("edreamcrowd", "backend", "secret"), "secret", ("edreamcrowd", "enabled")),
    (("casdoor", "config"), "configmap", ("casdoor", "enabled")),
]
for path, kind, enabled_path in resource_specs:
    if dig(*enabled_path) is False:
        continue
    item = dig(*path)
    if isinstance(item, dict) and item.get("name"):
        resources.append(f"{kind}/{item['name']}")
for resource in dict.fromkeys(resources):
    print(resource)
PY
}

external_resources() {
  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
    data = YAML.load_file(ARGV[0]) || {}
    def dig_hash(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end
    resource_specs = [
      [["databaseInit", "secret"], "secret", ["databaseInit", "enabled"]],
      [["postgres", "secret"], "secret", ["postgres", "enabled"]],
      [["new-api", "secret"], "secret", ["new-api", "enabled"]],
      [["broker", "secret"], "secret", ["broker", "enabled"]],
      [["ai-provider-adapter", "secret"], "secret", ["ai-provider-adapter", "enabled"]],
      [["edreamcrowd", "backend", "secret"], "secret", ["edreamcrowd", "enabled"]],
      [["casdoor", "config"], "configmap", ["casdoor", "enabled"]]
    ]
    resources = []
    resource_specs.each do |path, kind, enabled_path|
      next if dig_hash(data, *enabled_path) == false
      item = dig_hash(data, *path)
      next unless item.is_a?(Hash)
      name = item["name"]
      create = item.key?("create") ? item["create"] : true
      resources << "#{kind}/#{name}" if name && !name.empty? && !create
    end
    puts resources.uniq
    ' "$DEPLOYMENT_FILE"
    return 0
  fi

  python3 - "$DEPLOYMENT_FILE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}

def dig(*keys):
    cursor = data
    for key in keys:
        if not isinstance(cursor, dict):
            return None
        cursor = cursor.get(key)
    return cursor

resources = []
resource_specs = [
    (("databaseInit", "secret"), "secret", ("databaseInit", "enabled")),
    (("postgres", "secret"), "secret", ("postgres", "enabled")),
    (("new-api", "secret"), "secret", ("new-api", "enabled")),
    (("broker", "secret"), "secret", ("broker", "enabled")),
    (("ai-provider-adapter", "secret"), "secret", ("ai-provider-adapter", "enabled")),
    (("edreamcrowd", "backend", "secret"), "secret", ("edreamcrowd", "enabled")),
    (("casdoor", "config"), "configmap", ("casdoor", "enabled")),
]
for path, kind, enabled_path in resource_specs:
    if dig(*enabled_path) is False:
        continue
    item = dig(*path)
    if isinstance(item, dict) and item.get("name") and item.get("create", True) is False:
        resources.append(f"{kind}/{item['name']}")
for resource in dict.fromkeys(resources):
    print(resource)
PY
}

postgres_pvc_resources() {
  local postgres_enabled
  postgres_enabled="$(yaml_get "$DEPLOYMENT_FILE" postgres.enabled true)"
  if [ "$postgres_enabled" != "true" ]; then
    return 0
  fi

  local postgres_name
  postgres_name="$(yaml_get "$DEPLOYMENT_FILE" postgres.fullnameOverride "")"
  if [ -z "$postgres_name" ]; then
    local platform_name
    platform_name="$(yaml_get "$DEPLOYMENT_FILE" fullnameOverride "$RELEASE_NAME")"
    postgres_name="${platform_name}-postgres"
  fi

  printf 'pvc/data-%s-0\n' "$postgres_name"
}

verify_external_resources() {
  local missing=0
  local resource
  while IFS= read -r resource; do
    [ -z "$resource" ] && continue
    if ! kubectl get "$resource" -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "missing external resource: $resource in namespace $NAMESPACE" >&2
      missing=1
    fi
  done < <(external_resources)

  if [ "$missing" = "1" ]; then
    exit 1
  fi
}

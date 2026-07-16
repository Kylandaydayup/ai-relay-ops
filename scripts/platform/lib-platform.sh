#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
  if [ $# -lt 1 ]; then
    echo "usage: $0 <134|139>" >&2
    exit 2
  fi

  ENV_NAME=$1
  ENV_DIR="$OPS_ROOT/environments/$ENV_NAME"
  DEPLOYMENT_FILE="$ENV_DIR/edream-deployment.yaml"
  CHART_DIR="$OPS_ROOT/charts/platform"

  if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "missing deployment file: $DEPLOYMENT_FILE" >&2
    exit 2
  fi

  RELEASE_NAME="${RELEASE_NAME:-$(yaml_get "$DEPLOYMENT_FILE" deployment.releaseName platform)}"
  NAMESPACE="${NAMESPACE:-$(yaml_get "$DEPLOYMENT_FILE" namespace platform)}"

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
  local timeout=$2

  if kubectl get "$resource" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl rollout status "$resource" -n "$NAMESPACE" --timeout="$timeout"
  fi
}

wait_rollouts() {
  rollout_status_if_exists statefulset/platform-postgres 240s
  rollout_status_if_exists deployment/relay-new-api 180s
  rollout_status_if_exists deployment/ai-provider-adapter 180s
  rollout_status_if_exists deployment/newapi-compat-gateway 180s
  rollout_status_if_exists deployment/relay-broker 180s
  rollout_status_if_exists deployment/casdoor 180s
  rollout_status_if_exists deployment/edreamcrowd-backend 240s
  rollout_status_if_exists deployment/edreamcrowd-frontend 180s
  rollout_status_if_exists deployment/platform-gateway 180s
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

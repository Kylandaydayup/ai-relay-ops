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

yaml_set_image() {
  local file=$1
  local path=$2
  local repository=$3
  local tag=$4

  if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
    file, path, repository, tag = ARGV
    data = YAML.load_file(file) || {}
    cursor = data
    parts = path.split(".")
    parts.each do |part|
      cursor[part] ||= {}
      cursor = cursor[part]
    end
    cursor["repository"] = repository
    cursor["tag"] = tag
    cursor["pullPolicy"] ||= "IfNotPresent"
    File.write(file, data.to_yaml)
    ' "$file" "$path" "$repository" "$tag"
    return 0
  fi

  python3 - "$file" "$path" "$repository" "$tag" <<'PY'
import sys
import yaml

file_name, path, repository, tag = sys.argv[1:5]
with open(file_name, encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
cursor = data
for part in path.split("."):
    cursor = cursor.setdefault(part, {})
cursor["repository"] = repository
cursor["tag"] = tag
cursor.setdefault("pullPolicy", "IfNotPresent")
with open(file_name, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, sort_keys=False)
PY
}

sanitize_ref() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9_.-]+#-#g; s#^-+##; s#-+$##'
}

abs_path() {
  local path=$1
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    (cd "$OPS_ROOT" && cd "$path" && pwd)
  fi
}

git_label_for_dir() {
  local dir=$1
  local branch
  local short_sha
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'local-nogit\n'
    return 0
  fi
  branch="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD)"
  short_sha="$(git -C "$dir" rev-parse --short HEAD)"
  printf '%s-%s\n' "$(sanitize_ref "$branch")" "$short_sha"
}

init_image_build() {
  if [ $# -lt 1 ]; then
    echo "usage: $0 <134|139>" >&2
    exit 2
  fi

  ENV_NAME=$1
  ENV_DIR="$OPS_ROOT/environments/$ENV_NAME"
  DEPLOYMENT_FILE="$ENV_DIR/edream-deployment.yaml"
  HARBOR_FILE="$ENV_DIR/harbor.yaml"

  if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "missing deployment file: $DEPLOYMENT_FILE" >&2
    exit 2
  fi
  if [ ! -f "$HARBOR_FILE" ]; then
    echo "missing Harbor file: $HARBOR_FILE" >&2
    exit 2
  fi

  require_command docker
  if ! command -v ruby >/dev/null 2>&1; then
    python3 - <<'PY' >/dev/null
import yaml
PY
  fi

  if [ -f "${HARBOR_ENV_FILE:-$OPS_ROOT/build/harbor.env}" ]; then
    # shellcheck disable=SC1090
    . "${HARBOR_ENV_FILE:-$OPS_ROOT/build/harbor.env}"
  fi

  HARBOR_REGISTRY="$(yaml_get "$HARBOR_FILE" harbor.registry)"
  HARBOR_BASE_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.baseProject base-images)"
  HARBOR_RUNTIME_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.runtimeProject platform)"
  HARBOR_CACHE_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.cacheProject build-cache)"
  IMAGE_TAG_TIMESTAMP="${IMAGE_TAG_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"

  if [ -z "$HARBOR_REGISTRY" ]; then
    echo "missing harbor.registry in $HARBOR_FILE" >&2
    exit 2
  fi

  if [ -n "${HARBOR_USERNAME:-}" ] && [ -n "${HARBOR_PASSWORD:-}" ]; then
    echo "$HARBOR_PASSWORD" | docker login "$HARBOR_REGISTRY" -u "$HARBOR_USERNAME" --password-stdin >/dev/null
  fi
}

base_image_ref() {
  local public_image=$1
  local ref_no_digest="${public_image%@*}"
  local repo="${ref_no_digest%:*}"
  local tag="${ref_no_digest##*:}"
  local name="${repo##*/}"
  printf '%s/%s/%s:%s\n' "$HARBOR_REGISTRY" "$HARBOR_BASE_PROJECT" "$name" "$tag"
}

ensure_base_image() {
  local public_image=$1
  local harbor_image
  harbor_image="$(base_image_ref "$public_image")"

  if ! docker pull "$harbor_image" >&2; then
    docker pull "$public_image" >&2
    docker tag "$public_image" "$harbor_image" >&2
    docker push "$harbor_image" >&2
    docker pull "$harbor_image" >&2
  fi

  printf '%s\n' "$harbor_image"
}

runtime_image_ref() {
  local image_name=$1
  local source_dir=$2
  local label
  label="$(git_label_for_dir "$source_dir")"
  printf '%s/%s/%s:%s-%s\n' \
    "$HARBOR_REGISTRY" "$HARBOR_RUNTIME_PROJECT" "$image_name" "$label" "$IMAGE_TAG_TIMESTAMP"
}

push_image() {
  local context=$1
  local dockerfile=$2
  local image=$3
  shift 3

  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --push "$@" -f "$dockerfile" -t "$image" "$context"
  else
    docker build "$@" -f "$dockerfile" -t "$image" "$context"
    docker push "$image"
  fi
}

write_component_image() {
  local values_path=$1
  local image=$2
  local repository="${image%:*}"
  local tag="${image##*:}"
  yaml_set_image "$DEPLOYMENT_FILE" "$values_path" "$repository" "$tag"
  echo "updated $DEPLOYMENT_FILE: $values_path -> $image"
}

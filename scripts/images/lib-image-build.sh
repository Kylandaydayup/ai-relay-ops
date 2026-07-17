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

source_build_config() {
  local config_file="${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}"
  if [ ! -f "$config_file" ]; then
    echo "missing build config: $config_file" >&2
    echo "copy config/build.env.example to config/build.env or set BUILD_ENV_FILE" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  . "$config_file"
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
    print(cursor.nil? ? fallback : cursor)
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
    path.split(".").each do |part|
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
  if [ -n "${IMAGE_REF_LABEL:-}" ]; then
    sanitize_ref "$IMAGE_REF_LABEL"
    return 0
  fi
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'local\n'
    return 0
  fi
  branch="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD)"
  sanitize_ref "$branch"
}

init_image_build() {
  start_script_timer "${0##*/}"
  if [ "$#" -ne 0 ]; then
    echo "usage: $0" >&2
    echo "image build scripts read config/build.env; they do not take environment names" >&2
    exit 2
  fi

  require_command docker
  source_build_config

  HARBOR_REGISTRY="${HARBOR_REGISTRY:?HARBOR_REGISTRY is required}"
  HARBOR_BUILD_REGISTRY="${HARBOR_BUILD_REGISTRY:-$HARBOR_REGISTRY}"
  HARBOR_BASE_PROJECT="${HARBOR_BASE_PROJECT:-base-images}"
  HARBOR_RUNTIME_PROJECT="${HARBOR_RUNTIME_PROJECT:-platform}"
  IMAGE_TAG_TIMESTAMP="${IMAGE_TAG_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"
  IMAGE_PLATFORM="${IMAGE_PLATFORM:-linux/amd64}"

  BUILD_CACHE_ROOT="${BUILD_CACHE_ROOT:-${BUILD_ROOT:-$OPS_ROOT/.build}/cache}"
  GO_CACHE_DIR="${GO_CACHE_DIR:-$BUILD_CACHE_ROOT/go}"
  MAVEN_CACHE_DIR="${MAVEN_CACHE_DIR:-$BUILD_CACHE_ROOT/maven}"
  NODE_CACHE_DIR="${NODE_CACHE_DIR:-$BUILD_CACHE_ROOT/node}"
  BUN_CACHE_DIR="${BUN_CACHE_DIR:-$BUILD_CACHE_ROOT/bun}"
  PIP_CACHE_DIR="${PIP_CACHE_DIR:-$BUILD_CACHE_ROOT/pip}"

  mkdir -p "$GO_CACHE_DIR" "$MAVEN_CACHE_DIR" "$NODE_CACHE_DIR" "$BUN_CACHE_DIR" "$PIP_CACHE_DIR"

  if [ -n "${HARBOR_USERNAME:-}" ] && [ -n "${HARBOR_PASSWORD:-}" ]; then
    echo "$HARBOR_PASSWORD" | docker login "$HARBOR_REGISTRY" -u "$HARBOR_USERNAME" --password-stdin >/dev/null
    if [ "$HARBOR_BUILD_REGISTRY" != "$HARBOR_REGISTRY" ]; then
      echo "$HARBOR_PASSWORD" | docker login "$HARBOR_BUILD_REGISTRY" -u "$HARBOR_USERNAME" --password-stdin >/dev/null
    fi
  fi

  export DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"
  if [ "${USE_BUILDX:-1}" = "1" ]; then
    require_command docker
    if ! docker buildx version >/dev/null 2>&1; then
      echo "docker buildx is required when USE_BUILDX=1" >&2
      echo "install docker-buildx on the build host or set USE_BUILDX=0" >&2
      exit 2
    fi
  fi
}

base_image_ref() {
  local public_image=$1
  local ref_no_digest="${public_image%@*}"
  local repo="${ref_no_digest%:*}"
  local tag="${ref_no_digest##*:}"
  local name="${repo##*/}"
  printf '%s/%s/%s:%s\n' "$HARBOR_BUILD_REGISTRY" "$HARBOR_BASE_PROJECT" "$name" "$tag"
}

ensure_base_image() {
  local public_image=$1
  local harbor_image
  harbor_image="$(base_image_ref "$public_image")"
  if ! docker pull --platform "$IMAGE_PLATFORM" "$harbor_image" >&2; then
    docker pull --platform "$IMAGE_PLATFORM" "$public_image" >&2
    docker tag "$public_image" "$harbor_image" >&2
    docker push "$harbor_image" >&2
    docker pull --platform "$IMAGE_PLATFORM" "$harbor_image" >&2
  fi
  printf '%s\n' "$harbor_image"
}

require_image() {
  local image=$1
  if docker image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "$image"
    return 0
  fi
  if ! docker pull --platform "$IMAGE_PLATFORM" "$image" >&2; then
    echo "missing required Harbor image: $image" >&2
    return 1
  fi
  printf '%s\n' "$image"
}

require_base_image() {
  local public_image=$1
  require_image "$(base_image_ref "$public_image")"
}

runtime_image_ref() {
  local image_name=$1
  local source_dir=$2
  local label
  label="$(git_label_for_dir "$source_dir")"
  printf '%s/%s/%s:%s-%s\n' \
    "$HARBOR_BUILD_REGISTRY" "$HARBOR_RUNTIME_PROJECT" "$image_name" "$label" "$IMAGE_TAG_TIMESTAMP"
}

deployment_image_ref() {
  local image=$1
  if [ "$HARBOR_BUILD_REGISTRY" = "$HARBOR_REGISTRY" ]; then
    printf '%s\n' "$image"
    return 0
  fi
  case "$image" in
    "$HARBOR_BUILD_REGISTRY"/*)
      printf '%s/%s\n' "$HARBOR_REGISTRY" "${image#"$HARBOR_BUILD_REGISTRY"/}"
      ;;
    *)
      printf '%s\n' "$image"
      ;;
  esac
}

build_image_ref() {
  local image=$1
  if [ "$HARBOR_BUILD_REGISTRY" = "$HARBOR_REGISTRY" ]; then
    printf '%s\n' "$image"
    return 0
  fi
  case "$image" in
    "$HARBOR_REGISTRY"/*)
      printf '%s/%s\n' "$HARBOR_BUILD_REGISTRY" "${image#"$HARBOR_REGISTRY"/}"
      ;;
    *)
      printf '%s\n' "$image"
      ;;
  esac
}

push_image() {
  local context=$1
  local dockerfile=$2
  local image=$3
  shift 3
  if docker buildx version >/dev/null 2>&1 && [ "${USE_BUILDX:-1}" = "1" ]; then
    local cache_args=()
    if [ "${USE_BUILDX_LOCAL_CACHE:-0}" = "1" ]; then
      local image_cache_name
      local cache_dir
      local next_cache_dir
      image_cache_name="$(printf '%s' "${image##*/}" | tr ':/' '__')"
      cache_dir="$BUILD_CACHE_ROOT/docker/$image_cache_name"
      next_cache_dir="${cache_dir}.next"
      rm -rf "$next_cache_dir"
      mkdir -p "$cache_dir"
      cache_args+=(--cache-from "type=local,src=$cache_dir")
      cache_args+=(--cache-to "type=local,dest=$next_cache_dir,mode=max")
    fi
    docker buildx build --push --platform "$IMAGE_PLATFORM" \
      --build-arg "BUILDPLATFORM=$IMAGE_PLATFORM" \
      "${cache_args[@]}" \
      "$@" -f "$dockerfile" -t "$image" "$context"
    if [ "${USE_BUILDX_LOCAL_CACHE:-0}" = "1" ]; then
      rm -rf "$cache_dir"
      mv "$next_cache_dir" "$cache_dir"
    fi
  else
    docker build --platform "$IMAGE_PLATFORM" \
      --build-arg "BUILDPLATFORM=$IMAGE_PLATFORM" \
      "$@" -f "$dockerfile" -t "$image" "$context"
    docker push "$image"
  fi
}

write_component_image() {
  local values_path=$1
  local image=$2
  local values_file="${DEPLOYMENT_VALUES_FILE:-}"
  if [ -z "$values_file" ]; then
    echo "built image: $image"
    echo "set DEPLOYMENT_VALUES_FILE to update a deployment values file automatically"
    return 0
  fi
  if [ ! -f "$values_file" ]; then
    echo "DEPLOYMENT_VALUES_FILE does not exist: $values_file" >&2
    exit 2
  fi
  local deployment_image
  deployment_image="$(deployment_image_ref "$image")"
  local repository="${deployment_image%:*}"
  local tag="${deployment_image##*:}"
  yaml_set_image "$values_file" "$values_path" "$repository" "$tag"
  echo "updated $values_file: $values_path -> $deployment_image"
}

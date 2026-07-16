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
  if [ -n "${IMAGE_REF_LABEL:-}" ]; then
    sanitize_ref "$IMAGE_REF_LABEL"
    return 0
  fi

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
  BASE_IMAGE_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.baseProject base-images)"
  PROJECT_BASE_IMAGE_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.projectBaseProject project-base-images)"
  PROJECT_BASE_IMAGE_TAG="$(yaml_get "$HARBOR_FILE" harbor.projectBaseTag)"
  RUNTIME_IMAGE_PROJECT="$(yaml_get "$HARBOR_FILE" harbor.runtimeProject platform)"
  IMAGE_TAG_TIMESTAMP="${IMAGE_TAG_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"
  IMAGE_PLATFORM="${IMAGE_PLATFORM:-linux/amd64}"

  if [ -z "$HARBOR_REGISTRY" ]; then
    echo "missing harbor.registry in $HARBOR_FILE" >&2
    exit 2
  fi
  if [ -z "$PROJECT_BASE_IMAGE_TAG" ]; then
    echo "missing harbor.projectBaseTag in $HARBOR_FILE" >&2
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
  printf '%s/%s/%s:%s\n' "$HARBOR_REGISTRY" "$BASE_IMAGE_PROJECT" "$name" "$tag"
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

runtime_image_ref() {
  local image_name=$1
  local source_dir=$2
  local label
  label="$(git_label_for_dir "$source_dir")"
  printf '%s/%s/%s:%s-%s\n' \
    "$HARBOR_REGISTRY" "$RUNTIME_IMAGE_PROJECT" "$image_name" "$label" "$IMAGE_TAG_TIMESTAMP"
}

project_base_image_ref() {
  local image_name=$1
  printf '%s/%s/%s:%s\n' \
    "$HARBOR_REGISTRY" "$PROJECT_BASE_IMAGE_PROJECT" "$image_name" "$PROJECT_BASE_IMAGE_TAG"
}

require_base_image() {
  local public_image=$1
  require_image "$(base_image_ref "$public_image")"
}

require_project_base_image() {
  local image_name=$1
  require_image "$(project_base_image_ref "$image_name")"
}

ensure_project_base_image() {
  local context=$1
  local dockerfile=$2
  local image=$3
  shift 3

  if [ "${FORCE_PROJECT_BASE_REBUILD:-0}" != "1" ] && docker image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "$image"
    return 0
  fi
  if [ "${SKIP_PROJECT_BASE_PUSH:-0}" = "1" ]; then
    docker build --platform "$IMAGE_PLATFORM" \
      --build-arg "BUILDPLATFORM=$IMAGE_PLATFORM" \
      "$@" -f "$dockerfile" -t "$image" "$context" >&2
    printf '%s\n' "$image"
    return 0
  fi
  if [ "${FORCE_PROJECT_BASE_REBUILD:-0}" != "1" ] && docker pull --platform "$IMAGE_PLATFORM" "$image" >&2; then
    printf '%s\n' "$image"
    return 0
  fi

  if ! push_image "$context" "$dockerfile" "$image" "$@"; then
    echo "failed to build and push project base image: $image" >&2
    return 1
  fi
  if ! docker pull --platform "$IMAGE_PLATFORM" "$image" >&2; then
    echo "failed to pull project base image after push: $image" >&2
    return 1
  fi
  printf '%s\n' "$image"
}

ensure_python_service_runtime() {
  local source_dir=$1
  local python_base=$2
  local image
  image="$(project_base_image_ref python-service-runtime)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/python-service-runtime.Dockerfile" "$image" \
    --build-arg "PYTHON_BASE_IMAGE=$python_base" \
    --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
}

ensure_casdoor_web_builder() {
  local source_dir=$1
  local node_base=$2
  local image
  image="$(project_base_image_ref casdoor-web-builder)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/casdoor-web-builder.Dockerfile" "$image" \
    --build-arg "NODE_BASE_IMAGE=$node_base"
}

ensure_casdoor_go_builder() {
  local source_dir=$1
  local go_base=$2
  local image
  image="$(project_base_image_ref casdoor-go-builder)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/casdoor-go-builder.Dockerfile" "$image" \
    --build-arg "GO_BASE_IMAGE=$go_base" \
    --build-arg "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}"
}

ensure_casdoor_runtime() {
  local debian_base=$1
  local image
  image="$(project_base_image_ref casdoor-runtime)"
  ensure_project_base_image "$OPS_ROOT" "$OPS_ROOT/docker/project-base/casdoor-runtime.Dockerfile" "$image" \
    --build-arg "DEBIAN_BASE_IMAGE=$debian_base"
}

ensure_new_api_bun_builder() {
  local source_dir=$1
  local bun_base=$2
  local image
  image="$(project_base_image_ref new-api-bun-builder)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/new-api-bun-builder.Dockerfile" "$image" \
    --build-arg "BUN_BASE_IMAGE=$bun_base"
}

ensure_new_api_go_builder() {
  local source_dir=$1
  local go_base=$2
  local image
  image="$(project_base_image_ref new-api-go-builder)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/new-api-go-builder.Dockerfile" "$image" \
    --build-arg "GO_BASE_IMAGE=$go_base" \
    --build-arg "GOPROXY=${GOPROXY:-https://goproxy.cn,direct}"
}

ensure_new_api_runtime() {
  local debian_base=$1
  local image
  image="$(project_base_image_ref new-api-runtime)"
  ensure_project_base_image "$OPS_ROOT" "$OPS_ROOT/docker/project-base/new-api-runtime.Dockerfile" "$image" \
    --build-arg "DEBIAN_BASE_IMAGE=$debian_base"
}

ensure_edreamcrowd_maven_builder() {
  local source_dir=$1
  local maven_base=$2
  local image
  image="$(project_base_image_ref edreamcrowd-maven-builder)"
  ensure_project_base_image "$source_dir" "$OPS_ROOT/docker/project-base/edreamcrowd-maven-builder.Dockerfile" "$image" \
    --build-arg "MAVEN_BASE_IMAGE=$maven_base"
}

ensure_edreamcrowd_node_builder() {
  local source_dir=$1
  local node_base=$2
  local image
  image="$(project_base_image_ref edreamcrowd-node-builder)"
  ensure_project_base_image "$source_dir/frontend" "$OPS_ROOT/docker/project-base/edreamcrowd-node-builder.Dockerfile" "$image" \
    --build-arg "NODE_BASE_IMAGE=$node_base"
}

push_image() {
  local context=$1
  local dockerfile=$2
  local image=$3
  shift 3

  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --push --platform "$IMAGE_PLATFORM" \
      --build-arg "BUILDPLATFORM=$IMAGE_PLATFORM" \
      "$@" -f "$dockerfile" -t "$image" "$context"
  else
    docker build --platform "$IMAGE_PLATFORM" \
      --build-arg "BUILDPLATFORM=$IMAGE_PLATFORM" \
      "$@" -f "$dockerfile" -t "$image" "$context"
    docker push "$image"
  fi
}

push_runtime_image() {
  local context=$1
  local dockerfile=$2
  local image=$3
  local network="${RUNTIME_BUILD_NETWORK:-none}"
  shift 3

  push_image "$context" "$dockerfile" "$image" --network "$network" "$@"
}

write_component_image() {
  local values_path=$1
  local image=$2
  local repository="${image%:*}"
  local tag="${image##*:}"
  yaml_set_image "$DEPLOYMENT_FILE" "$values_path" "$repository" "$tag"
  echo "updated $DEPLOYMENT_FILE: $values_path -> $image"
}

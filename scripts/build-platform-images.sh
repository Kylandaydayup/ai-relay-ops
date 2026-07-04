#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${1:-${BUILD_ENV_FILE:-build/images.env}}"

cd "$repo_root"

if [ ! -f "$env_file" ]; then
  echo "missing image build env file: $env_file" >&2
  echo "copy build/images.env.example to $env_file and edit it first" >&2
  exit 2
fi

# shellcheck disable=SC1090
. "$env_file"

build_workdir="${BUILD_WORKDIR:-.build/platform-images}"
image_output_dir="${IMAGE_OUTPUT_DIR:-dist/platform-bundle/images}"
image_registry="${IMAGE_REGISTRY:-}"
push_images="${PUSH_IMAGES:-false}"
save_images="${SAVE_IMAGES:-true}"

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

image_ref() {
  local repository=$1
  local tag=$2

  if [ -n "$image_registry" ]; then
    printf '%s/%s:%s\n' "${image_registry%/}" "$repository" "$tag"
  else
    printf '%s:%s\n' "$repository" "$tag"
  fi
}

safe_image_filename() {
  printf '%s\n' "$1" | tr '/:' '__'
}

build_args_flags() {
  local args=${1:-}
  local flags=()
  local item

  for item in $args; do
    flags+=(--build-arg "$item")
  done
  printf '%q ' "${flags[@]}"
}

prepare_source() {
  local name=$1
  local repo_url=$2
  local repo_ref=$3
  local local_dir=$4
  local dst="$build_workdir/src/$name"

  mkdir -p "$build_workdir/src"
  if [ -n "$local_dir" ]; then
    if [ ! -d "$local_dir" ]; then
      echo "missing local source directory for $name: $local_dir" >&2
      exit 2
    fi
    printf '%s\n' "$local_dir"
    return 0
  fi

  if [ -z "$repo_url" ]; then
    echo "missing repository url for $name" >&2
    exit 2
  fi

  if [ ! -d "$dst/.git" ]; then
    rm -rf "$dst"
    git clone "$repo_url" "$dst"
  fi

  git -C "$dst" fetch --all --tags --prune
  git -C "$dst" checkout "$repo_ref"
  git -C "$dst" pull --ff-only origin "$repo_ref" 2>/dev/null || true
  printf '%s\n' "$dst"
}

build_image() {
  local image=$1
  local dockerfile=$2
  local context_dir=$3
  local args=${4:-}
  local extra_args

  extra_args="$(build_args_flags "$args")"
  # shellcheck disable=SC2086
  docker build $extra_args -f "$dockerfile" -t "$image" "$context_dir"
}

save_image() {
  local image=$1
  local file="$image_output_dir/$(safe_image_filename "$image").tar"

  mkdir -p "$image_output_dir"
  docker save "$image" -o "$file"
  echo "$image" >> "$image_output_dir/images.txt"
}

publish_or_save() {
  local image=$1

  if [ "$push_images" = "true" ]; then
    docker push "$image"
  fi
  if [ "$save_images" = "true" ]; then
    save_image "$image"
  fi
}

require_command git
require_command docker

rm -f "$image_output_dir/images.txt"
mkdir -p "$image_output_dir"

if [ "${BUILD_BROKER:-true}" = "true" ]; then
  broker_src="$(prepare_source \
    broker \
    "${BROKER_REPO_URL:-}" \
    "${BROKER_REPO_REF:-main}" \
    "${BROKER_LOCAL_DIR:-}")"
  broker_image="$(image_ref "${BROKER_IMAGE_REPOSITORY:-ai-relay-broker}" "${BROKER_IMAGE_TAG:-demo}")"
  broker_context="$broker_src/${BROKER_CONTEXT:-.}"
  broker_dockerfile="$broker_context/${BROKER_DOCKERFILE:-Dockerfile}"
  build_image "$broker_image" "$broker_dockerfile" "$broker_context" "${BROKER_BUILD_ARGS:-}"
  publish_or_save "$broker_image"
fi

if [ "${BUILD_AI_PROVIDER_ADAPTER:-true}" = "true" ]; then
  adapter_src="$(prepare_source \
    ai-provider-adapter \
    "${AI_PROVIDER_ADAPTER_REPO_URL:-}" \
    "${AI_PROVIDER_ADAPTER_REPO_REF:-main}" \
    "${AI_PROVIDER_ADAPTER_LOCAL_DIR:-}")"
  adapter_image="$(image_ref "${AI_PROVIDER_ADAPTER_IMAGE_REPOSITORY:-ai-provider-adapter}" "${AI_PROVIDER_ADAPTER_IMAGE_TAG:-demo}")"
  adapter_context="$adapter_src/${AI_PROVIDER_ADAPTER_CONTEXT:-.}"
  adapter_dockerfile="$adapter_context/${AI_PROVIDER_ADAPTER_DOCKERFILE:-Dockerfile}"
  build_image "$adapter_image" "$adapter_dockerfile" "$adapter_context" "${AI_PROVIDER_ADAPTER_BUILD_ARGS:-}"
  publish_or_save "$adapter_image"
fi

if [ "${BUILD_NEWAPI_COMPAT_GATEWAY:-true}" = "true" ]; then
  compat_src="$(prepare_source \
    newapi-compat-gateway \
    "${NEWAPI_COMPAT_GATEWAY_REPO_URL:-${BROKER_REPO_URL:-}}" \
    "${NEWAPI_COMPAT_GATEWAY_REPO_REF:-${BROKER_REPO_REF:-main}}" \
    "${NEWAPI_COMPAT_GATEWAY_LOCAL_DIR:-${BROKER_LOCAL_DIR:-}}")"
  compat_image="$(image_ref "${NEWAPI_COMPAT_GATEWAY_IMAGE_REPOSITORY:-newapi-compat-gateway}" "${NEWAPI_COMPAT_GATEWAY_IMAGE_TAG:-demo}")"
  compat_context="$compat_src/${NEWAPI_COMPAT_GATEWAY_CONTEXT:-.}"
  compat_dockerfile="$compat_context/${NEWAPI_COMPAT_GATEWAY_DOCKERFILE:-Dockerfile.newapi-compat-gateway}"
  build_image "$compat_image" "$compat_dockerfile" "$compat_context" "${NEWAPI_COMPAT_GATEWAY_BUILD_ARGS:-}"
  publish_or_save "$compat_image"
fi

if [ "${BUILD_EDREAMCROWD_FRONTEND:-true}" = "true" ] || [ "${BUILD_EDREAMCROWD_BACKEND:-true}" = "true" ]; then
  edream_src="$(prepare_source \
    edreamcrowd \
    "${EDREAMCROWD_REPO_URL:-}" \
    "${EDREAMCROWD_REPO_REF:-main}" \
    "${EDREAMCROWD_LOCAL_DIR:-}")"

  if [ "${BUILD_EDREAMCROWD_FRONTEND:-true}" = "true" ]; then
    frontend_image="$(image_ref "${EDREAMCROWD_FRONTEND_IMAGE_REPOSITORY:-edreamcrowd-frontend}" "${EDREAMCROWD_FRONTEND_IMAGE_TAG:-demo}")"
    frontend_args="VITE_PUBLIC_BASE=${EDREAMCROWD_FRONTEND_PUBLIC_BASE:-/} ${EDREAMCROWD_FRONTEND_BUILD_ARGS:-}"
    build_image "$frontend_image" "$edream_src/frontend/Dockerfile" "$edream_src/frontend" "$frontend_args"
    publish_or_save "$frontend_image"
  fi

  if [ "${BUILD_EDREAMCROWD_BACKEND:-true}" = "true" ]; then
    backend_image="$(image_ref "${EDREAMCROWD_BACKEND_IMAGE_REPOSITORY:-edreamcrowd-backend}" "${EDREAMCROWD_BACKEND_IMAGE_TAG:-demo}")"
    build_image "$backend_image" "$edream_src/Dockerfile" "$edream_src" "${EDREAMCROWD_BACKEND_BUILD_ARGS:-}"
    publish_or_save "$backend_image"
  fi
fi

for upstream_image in ${UPSTREAM_IMAGES:-}; do
  if ! docker image inspect "$upstream_image" >/dev/null 2>&1; then
    docker pull "$upstream_image"
  fi
  publish_or_save "$upstream_image"
done

if [ -f "$image_output_dir/images.txt" ]; then
  sort -u "$image_output_dir/images.txt" -o "$image_output_dir/images.txt"
fi
echo "image build output: $image_output_dir"

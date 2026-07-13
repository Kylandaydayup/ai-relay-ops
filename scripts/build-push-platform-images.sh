#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib-harbor-images.sh
. "$repo_root/scripts/lib-harbor-images.sh"

env_file="${1:-${BUILD_ENV_FILE:-build/platform-images.harbor.env}}"
cd "$repo_root"
load_env_file "$env_file"
load_env_file "${HARBOR_ENV_FILE:-build/harbor.env}"

registry="${HARBOR_REGISTRY:-${HARBOR_HOST}:${HARBOR_PORT}}"
runtime_project="${HARBOR_RUNTIME_PROJECT:-edreamcrowd}"
cache_project="${HARBOR_CACHE_PROJECT:-build-cache}"
build_workdir="${BUILD_WORKDIR:-.build/harbor-platform-images}"
timestamp="${IMAGE_TAG_TIMESTAMP:-$(image_timestamp)}"
values_file="$build_workdir/platform-image-values-${timestamp}.yaml"

if [ -n "${HARBOR_USERNAME:-}" ] && [ -n "${HARBOR_PASSWORD:-}" ]; then
  echo "$HARBOR_PASSWORD" | docker login "$registry" -u "$HARBOR_USERNAME" --password-stdin
fi

mkdir -p "$build_workdir"
manifest="$build_workdir/images-${timestamp}.env"
values_json="$build_workdir/platform-image-values-${timestamp}.json"
: > "$manifest"
printf '{}\n' > "$values_json"

append_yaml_image() {
  local key=$1
  local image=$2
  local repository="${image%:*}"
  local tag="${image##*:}"

  python3 - "$values_json" "$key" "$repository" "$tag" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key, repository, tag = sys.argv[2:5]
data = json.loads(path.read_text())

def set_path(parts):
    cursor = data
    for part in parts[:-1]:
        cursor = cursor.setdefault(part, {})
    cursor[parts[-1]] = {"repository": repository, "tag": tag}

paths = {
    "broker": ["broker", "image"],
    "ai-provider-adapter": ["ai-provider-adapter", "image"],
    "newapi-compat-gateway": ["newapi-compat-gateway", "image"],
    "edreamcrowd-backend": ["edreamcrowd", "backend", "image"],
    "edreamcrowd-frontend": ["edreamcrowd", "frontend", "image"],
    "new-api": ["new-api", "image"],
    "casdoor": ["casdoor", "image"],
}
if key in paths:
    set_path(paths[key])

path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

write_values_file() {
  python3 - "$values_json" "$values_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())

def dump_yaml(value, indent=0):
    lines = []
    prefix = " " * indent
    for key, item in value.items():
        if isinstance(item, dict):
            lines.append(f"{prefix}{key}:")
            lines.extend(dump_yaml(item, indent + 2))
        else:
            lines.append(f"{prefix}{key}: {item}")
    return lines

Path(sys.argv[2]).write_text("\n".join(dump_yaml(data)) + "\n")
PY
}

build_one() {
  local key=$1
  local src context dockerfile image_name build_args image branch cache_ref args

  src="$(prepare_source "$key" "${2:-}" "${3:-main}" "${4:-}" "$build_workdir")"
  context="$src/${5:-.}"
  dockerfile="$context/${6:-Dockerfile}"
  image_name=$7
  build_args=${8:-}
  branch="${IMAGE_BRANCH:-$(git_branch_for_dir "$src")}"
  image="$(image_ref_for "$registry" "$runtime_project" "$image_name" "$branch" "$timestamp")"
  cache_ref="$(cache_ref_for "$registry" "$cache_project" "$image_name" "$branch")"
  build_args_array "$build_args" args

  docker buildx build \
    --push \
    --cache-from "type=registry,ref=$cache_ref" \
    --cache-to "type=registry,ref=$cache_ref,mode=max" \
    "${args[@]}" \
    -f "$dockerfile" \
    -t "$image" \
    "$context"
  printf '%s=%s\n' "$(printf '%s_IMAGE' "$image_name" | tr '[:lower:]-' '[:upper:]_')" "$image" >> "$manifest"
  append_yaml_image "$key" "$image"
  echo "$image"
}

if [ "${BUILD_BROKER:-false}" = "true" ]; then
  build_one broker "${BROKER_REPO_URL:-}" "${BROKER_REPO_REF:-main}" "${BROKER_LOCAL_DIR:-}" "${BROKER_CONTEXT:-.}" "${BROKER_DOCKERFILE:-Dockerfile}" "${BROKER_IMAGE_NAME:-broker}" "${BROKER_BUILD_ARGS:-}"
fi
if [ "${BUILD_AI_PROVIDER_ADAPTER:-false}" = "true" ]; then
  build_one ai-provider-adapter "${AI_PROVIDER_ADAPTER_REPO_URL:-}" "${AI_PROVIDER_ADAPTER_REPO_REF:-main}" "${AI_PROVIDER_ADAPTER_LOCAL_DIR:-}" "${AI_PROVIDER_ADAPTER_CONTEXT:-.}" "${AI_PROVIDER_ADAPTER_DOCKERFILE:-Dockerfile.ai-provider-adapter}" "${AI_PROVIDER_ADAPTER_IMAGE_NAME:-ai-provider-adapter}" "${AI_PROVIDER_ADAPTER_BUILD_ARGS:-}"
fi
if [ "${BUILD_NEWAPI_COMPAT_GATEWAY:-false}" = "true" ]; then
  build_one newapi-compat-gateway "${NEWAPI_COMPAT_GATEWAY_REPO_URL:-}" "${NEWAPI_COMPAT_GATEWAY_REPO_REF:-main}" "${NEWAPI_COMPAT_GATEWAY_LOCAL_DIR:-}" "${NEWAPI_COMPAT_GATEWAY_CONTEXT:-.}" "${NEWAPI_COMPAT_GATEWAY_DOCKERFILE:-Dockerfile.newapi-compat-gateway}" "${NEWAPI_COMPAT_GATEWAY_IMAGE_NAME:-newapi-compat-gateway}" "${NEWAPI_COMPAT_GATEWAY_BUILD_ARGS:-}"
fi
if [ "${BUILD_EDREAMCROWD_BACKEND:-false}" = "true" ]; then
  build_one edreamcrowd-backend "${EDREAMCROWD_REPO_URL:-}" "${EDREAMCROWD_REPO_REF:-main}" "${EDREAMCROWD_LOCAL_DIR:-}" "${EDREAMCROWD_BACKEND_CONTEXT:-.}" "${EDREAMCROWD_BACKEND_DOCKERFILE:-Dockerfile}" "${EDREAMCROWD_BACKEND_IMAGE_NAME:-backend}" "${EDREAMCROWD_BACKEND_BUILD_ARGS:-}"
fi
if [ "${BUILD_EDREAMCROWD_FRONTEND:-false}" = "true" ]; then
  build_one edreamcrowd-frontend "${EDREAMCROWD_REPO_URL:-}" "${EDREAMCROWD_REPO_REF:-main}" "${EDREAMCROWD_LOCAL_DIR:-}" "${EDREAMCROWD_FRONTEND_CONTEXT:-frontend}" "${EDREAMCROWD_FRONTEND_DOCKERFILE:-Dockerfile}" "${EDREAMCROWD_FRONTEND_IMAGE_NAME:-frontend}" "${EDREAMCROWD_FRONTEND_BUILD_ARGS:-}"
fi
if [ "${BUILD_NEW_API:-false}" = "true" ]; then
  build_one new-api "${NEW_API_REPO_URL:-}" "${NEW_API_REPO_REF:-main}" "${NEW_API_LOCAL_DIR:-}" "${NEW_API_CONTEXT:-.}" "${NEW_API_DOCKERFILE:-Dockerfile}" "${NEW_API_IMAGE_NAME:-new-api}" "${NEW_API_BUILD_ARGS:-}"
fi
if [ "${BUILD_CASDOOR:-false}" = "true" ]; then
  build_one casdoor "${CASDOOR_REPO_URL:-}" "${CASDOOR_REPO_REF:-main}" "${CASDOOR_LOCAL_DIR:-}" "${CASDOOR_CONTEXT:-.}" "${CASDOOR_DOCKERFILE:-Dockerfile}" "${CASDOOR_IMAGE_NAME:-casdoor}" "${CASDOOR_BUILD_ARGS:-}"
fi

write_values_file
echo "image manifest: $manifest"
echo "image values: $values_file"

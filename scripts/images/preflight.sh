#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

failures=()
warnings=()

to_kb() {
  local path=$1
  df -Pk "$path" | awk 'NR == 2 { print $4 }'
}

available_mem_mb() {
  if command -v free >/dev/null 2>&1; then
    free -m | awk '/^Mem:/ { print $7 }'
    return 0
  fi
  if command -v vm_stat >/dev/null 2>&1; then
    pages_free="$(vm_stat | awk '/Pages free/ { gsub("\\.", "", $3); print $3 }')"
    page_size="$(vm_stat | awk '/page size of/ { print $8 }')"
    echo $((pages_free * page_size / 1024 / 1024))
    return 0
  fi
  echo 0
}

check_free_gb() {
  local label=$1
  local path=$2
  local min_gb=$3
  local free_kb
  free_kb="$(to_kb "$path")"
  free_gb=$((free_kb / 1024 / 1024))
  if [ "$free_gb" -lt "$min_gb" ]; then
    failures+=("$label free disk is ${free_gb}GB, require >= ${min_gb}GB: $path")
  elif [ "$free_gb" -lt $((min_gb + 10)) ]; then
    warnings+=("$label free disk is ${free_gb}GB: $path")
  fi
}

check_git_source() {
  local name=$1
  local dir=$2
  local ref=$3
  if [ ! -d "$dir/.git" ]; then
    if [ -f "$dir/.edream-source-meta" ]; then
      local meta_ref
      meta_ref="$(awk -F= '$1 == "branch" { print $2 }' "$dir/.edream-source-meta")"
      if [ -n "$ref" ] && [ "$meta_ref" != "$ref" ]; then
        warnings+=("$name source snapshot ref is $meta_ref, configured ref is $ref")
      fi
      return 0
    fi
    failures+=("$name source is not a git repository or source snapshot: $dir")
    return 0
  fi
  if [ "${SOURCE_ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git -C "$dir" status --porcelain)" ]; then
    failures+=("$name source has uncommitted changes: $dir")
  fi
  current_ref="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD)"
  if [ -n "$ref" ] && [ "$current_ref" != "$ref" ]; then
    warnings+=("$name source ref is $current_ref, configured ref is $ref")
  fi
}

build_root="${BUILD_ROOT:-$OPS_ROOT/.build}"
docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
min_free_gb="${MIN_BUILD_FREE_GB:-10}"
if [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  min_free_gb="${MIN_CASDOOR_BUILD_FREE_GB:-15}"
fi

check_free_gb "build root" "$build_root" "$min_free_gb"
if [ -n "$docker_root" ]; then
  check_free_gb "docker root" "$docker_root" "$min_free_gb"
fi

mem_required="${MIN_BUILD_AVAILABLE_MEM_MB:-2048}"
if [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  mem_required="${MIN_CASDOOR_BUILD_AVAILABLE_MEM_MB:-4096}"
fi
mem_available="$(available_mem_mb)"
if [ "$mem_available" -gt 0 ] && [ "$mem_available" -lt "$mem_required" ]; then
  failures+=("available memory is ${mem_available}MB, require >= ${mem_required}MB")
fi

if ! docker ps >/dev/null 2>&1; then
  failures+=("docker daemon is not accessible by current user")
fi
if [ "${USE_BUILDX:-1}" = "1" ] && ! docker buildx version >/dev/null 2>&1; then
  failures+=("docker buildx is required but not available")
fi

probe_image="$(base_image_ref nginx:alpine)"
if ! docker pull --platform "$IMAGE_PLATFORM" "$probe_image" >/dev/null 2>&1; then
  failures+=("Harbor base image pull failed: $probe_image")
fi

if [ -n "${DEPLOYMENT_VALUES_FILE:-}" ]; then
  if [ ! -f "$DEPLOYMENT_VALUES_FILE" ]; then
    failures+=("DEPLOYMENT_VALUES_FILE does not exist: $DEPLOYMENT_VALUES_FILE")
  elif [ ! -w "$DEPLOYMENT_VALUES_FILE" ]; then
    failures+=("DEPLOYMENT_VALUES_FILE is not writable: $DEPLOYMENT_VALUES_FILE")
  else
    yaml_get "$DEPLOYMENT_VALUES_FILE" deployment.releaseName >/dev/null
  fi
fi

check_git_source broker "$(abs_path "${BROKER_LOCAL_DIR:-../ai-relay-broker}")" "${BROKER_GIT_REF:-main}"
check_git_source new-api "$(abs_path "${NEW_API_LOCAL_DIR:-../new-api}")" "${NEW_API_GIT_REF:-main}"
if [ "${SYNC_CASDOOR:-0}" = "1" ] || [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  check_git_source casdoor "$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")" "${CASDOOR_GIT_REF:-main}"
fi
check_git_source edreamcrowd "$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")" "${EDREAMCROWD_GIT_REF:-main}"

if [ "${#warnings[@]}" -gt 0 ]; then
  printf 'image preflight warnings:\n' >&2
  printf '  - %s\n' "${warnings[@]}" >&2
fi

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'image preflight failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "image preflight passed"

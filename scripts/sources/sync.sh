#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$OPS_ROOT/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

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

retry_git() {
  local attempt
  for attempt in 1 2 3; do
    if git "$@"; then
      return 0
    fi
    if [ "$attempt" = "3" ]; then
      return 1
    fi
    echo "git $* failed, retrying ($attempt/3)" >&2
    sleep $((attempt * 5))
  done
}

sync_repo() {
  local name=$1
  local dir=$2
  local url=$3
  local ref=$4
  local depth="${SOURCE_GIT_DEPTH:-1}"

  if [ -z "$dir" ]; then
    echo "$name local directory is not configured" >&2
    exit 2
  fi

  if [ ! -d "$dir/.git" ]; then
    if [ -z "$url" ]; then
      echo "$name source does not exist and git url is not configured: $dir" >&2
      exit 2
    fi
    mkdir -p "$(dirname "$dir")"
    clone_args=()
    if [ -n "$ref" ]; then
      clone_args+=(--single-branch)
      clone_args+=(--branch "$ref")
    fi
    if [ -n "$depth" ]; then
      clone_args+=(--depth "$depth")
    fi
    retry_git clone "${clone_args[@]}" "$url" "$dir"
  fi

  if [ "${SOURCE_ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git -C "$dir" status --porcelain)" ]; then
    echo "$name source has uncommitted changes: $dir" >&2
    exit 2
  fi

  if [ -n "$url" ]; then
    current_url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [ -n "$current_url" ] && [ "$current_url" != "$url" ]; then
      echo "$name origin mismatch: expected $url, got $current_url" >&2
      exit 2
    fi
  fi

  fetch_args=(--prune origin)
  if [ -n "$depth" ]; then
    fetch_args=(--depth "$depth" "${fetch_args[@]}")
  fi
  retry_git -C "$dir" fetch "${fetch_args[@]}"
  if [ -n "$ref" ]; then
    if git -C "$dir" rev-parse --verify --quiet "origin/$ref" >/dev/null; then
      git -C "$dir" checkout -B "$ref" "origin/$ref"
    else
      git -C "$dir" checkout "$ref"
    fi
  fi

  commit="$(git -C "$dir" rev-parse --short HEAD)"
  branch="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || true)"
  echo "$name source ready: dir=$dir ref=${ref:-current} branch=${branch:-detached} commit=$commit"
}

if [ "$#" -ne 0 ]; then
  echo "usage: sync.sh" >&2
  exit 2
fi

require_command git
source_build_config

sync_repo "broker" "${BROKER_LOCAL_DIR:-}" "${BROKER_GIT_URL:-}" "${BROKER_GIT_REF:-main}"
sync_repo "new-api" "${NEW_API_LOCAL_DIR:-}" "${NEW_API_GIT_URL:-}" "${NEW_API_GIT_REF:-main}"
if [ "${SYNC_CASDOOR:-0}" = "1" ] || [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  sync_repo "casdoor" "${CASDOOR_LOCAL_DIR:-}" "${CASDOOR_GIT_URL:-}" "${CASDOOR_GIT_REF:-main}"
else
  echo "casdoor source skipped: SYNC_CASDOOR=0 BUILD_CASDOOR=${BUILD_CASDOOR:-0}"
fi
sync_repo "edreamcrowd" "${EDREAMCROWD_LOCAL_DIR:-}" "${EDREAMCROWD_GIT_URL:-}" "${EDREAMCROWD_GIT_REF:-main}"

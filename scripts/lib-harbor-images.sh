#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env_file() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo "missing env file: $file" >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  . "$file"
}

sanitize_ref() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9_.-]+#-#g; s#^-+##; s#-+$##'
}

git_branch_for_dir() {
  local dir=$1
  git -C "$dir" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$dir" rev-parse --short HEAD
}

image_timestamp() {
  date '+%Y%m%d%H%M%S'
}

image_ref_for() {
  local registry=$1
  local project=$2
  local name=$3
  local branch=$4
  local timestamp=$5
  printf '%s/%s/%s:%s-%s\n' \
    "${registry%/}" "$project" "$(sanitize_ref "$name")" "$(sanitize_ref "$branch")" "$timestamp"
}

cache_ref_for() {
  local registry=$1
  local project=$2
  local name=$3
  local branch=$4
  printf '%s/%s/%s:%s-cache\n' \
    "${registry%/}" "$project" "$(sanitize_ref "$name")" "$(sanitize_ref "$branch")"
}

prepare_source() {
  local name=$1
  local repo_url=$2
  local repo_ref=$3
  local local_dir=$4
  local build_workdir=$5
  local dst="$build_workdir/src/$name"

  mkdir -p "$build_workdir/src"
  if [ -n "$local_dir" ]; then
    if [ ! -d "$local_dir" ]; then
      echo "missing local source directory for $name: $local_dir" >&2
      exit 2
    fi
    (cd "$repo_root" && cd "$local_dir" && pwd)
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

build_args_array() {
  local args=${1:-}
  local -n out=$2
  local item
  out=()
  for item in $args; do
    out+=(--build-arg "$item")
  done
}

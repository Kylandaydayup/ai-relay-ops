#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$OPS_ROOT/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

config_file="${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}"
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  . "$config_file"
fi

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

abs_path() {
  local path=$1
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    (cd "$OPS_ROOT" && cd "$path" && pwd)
  fi
}

ssh_target="${REMOTE_BUILD_TARGET:-}"
if [ -z "$ssh_target" ] && [ -n "${REMOTE_BUILD_HOST:-}" ]; then
  ssh_target="${REMOTE_BUILD_USER:-ubuntu}@$REMOTE_BUILD_HOST"
fi
if [ -z "$ssh_target" ]; then
  echo "REMOTE_BUILD_TARGET or REMOTE_BUILD_HOST is required" >&2
  exit 2
fi

ssh_opts="${REMOTE_SSH_OPTS:--o StrictHostKeyChecking=accept-new}"
ssh_bin=(ssh)
scp_bin=(scp)
if [ -n "${SSHPASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
  ssh_bin=(sshpass -e ssh)
  scp_bin=(sshpass -e scp)
fi

run_remote() {
  "${ssh_bin[@]}" $ssh_opts "$ssh_target" "$@"
}

upload_repo() {
  local name=$1
  local local_dir=$2
  local remote_dir=$3

  if [ ! -d "$local_dir/.git" ]; then
    echo "$name local source is not a git repository: $local_dir" >&2
    exit 2
  fi
  if [ "${ALLOW_DIRTY_UPLOAD:-0}" != "1" ] && [ -n "$(git -C "$local_dir" status --porcelain)" ]; then
    echo "$name local source has uncommitted changes: $local_dir" >&2
    echo "commit/stash them or set ALLOW_DIRTY_UPLOAD=1 for an explicit dirty-source build" >&2
    exit 2
  fi
  local commit branch
  commit="$(git -C "$local_dir" rev-parse --short HEAD)"
  branch="$(git -C "$local_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
  echo "$name upload started: local=$local_dir remote=$remote_dir branch=${branch:-detached} commit=$commit"

  local archive
  archive="$(mktemp -t "${name}.XXXXXX.tar.gz")"
  trap 'rm -f "$archive"' RETURN
  if [ "${ALLOW_DIRTY_UPLOAD:-0}" = "1" ]; then
    echo "$name dirty upload enabled: packaging working tree with build-output excludes"
    tar -C "$local_dir" \
      --exclude './.deploy' \
      --exclude './.tmp' \
      --exclude './tmp' \
      --exclude './target' \
      --exclude './build' \
      --exclude './frontend/node_modules' \
      --exclude './frontend/dist' \
      --exclude './frontend/build' \
      --exclude './node_modules' \
      --exclude './dist' \
      --exclude './coverage' \
      --exclude './.gradle' \
      -czf "$archive" .
  else
    echo "$name clean upload: packaging git archive from HEAD"
    git -C "$local_dir" archive --format=tar.gz -o "$archive" HEAD
  fi

  remote_tmp="/tmp/${name}-${commit}.tar.gz"
  "${scp_bin[@]}" $ssh_opts "$archive" "$ssh_target:$remote_tmp"
  rm -f "$archive"
  trap - RETURN
  local remote_parent remote_stamp
  remote_parent="${remote_dir%/*}"
  remote_stamp="$(date +%Y%m%d%H%M%S)"
  run_remote "set -euo pipefail
    stamp='$remote_stamp'
    mkdir -p /data/edream-build/source-snapshots '$remote_parent'
    work_dir='${remote_dir}.upload-'\$stamp
    mkdir -p \"\\\$work_dir\"
    tar -xzf '$remote_tmp' -C \"\\\$work_dir\"
    rm -f '$remote_tmp'
    cat > \"\\\$work_dir/.edream-source-meta\" <<'META'
name=$name
branch=${branch:-detached}
commit=$commit
META
    if [ -e '$remote_dir' ]; then
      mv '$remote_dir' \"/data/edream-build/source-snapshots/${name}-\"\$stamp
    fi
    mv \"\\\$work_dir\" '$remote_dir'
    echo '$name remote ready:' '${branch:-detached}' '$commit'
  "
  echo "$name upload completed"
}

if [ "$#" -ne 0 ]; then
  echo "usage: upload-local.sh" >&2
  exit 2
fi

require_command git
require_command tar
require_command mktemp

targets="${UPLOAD_TARGETS:-ops broker new-api edreamcrowd}"
if [ "${SYNC_CASDOOR:-0}" = "1" ] || [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  targets="$targets casdoor"
fi

for target in $targets; do
  case "$target" in
    ops)
      upload_repo ops "$OPS_ROOT" "${REMOTE_OPS_DIR:-/data/edream-build/sources/ai-relay-ops}"
      ;;
    broker)
      upload_repo broker "$(abs_path "${BROKER_UPLOAD_DIR:-../ai-relay-broker}")" "${BROKER_LOCAL_DIR:-/data/edream-build/sources/ai-relay-broker}"
      ;;
    new-api)
      upload_repo new-api "$(abs_path "${NEW_API_UPLOAD_DIR:-../new-api}")" "${NEW_API_LOCAL_DIR:-/data/edream-build/sources/new-api}"
      ;;
    edreamcrowd)
      upload_repo edreamcrowd "$(abs_path "${EDREAMCROWD_UPLOAD_DIR:-../EDreamCrowd}")" "${EDREAMCROWD_LOCAL_DIR:-/data/edream-build/sources/EDreamCrowd}"
      ;;
    casdoor)
      upload_repo casdoor "$(abs_path "${CASDOOR_UPLOAD_DIR:-../casdoor}")" "${CASDOOR_LOCAL_DIR:-/data/edream-build/sources/casdoor}"
      ;;
    *)
      echo "unknown upload target: $target" >&2
      exit 2
      ;;
  esac
done

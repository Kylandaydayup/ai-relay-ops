#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ops_root="$(cd "$script_dir/../.." && pwd)"
. "$ops_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

config_file="${BUILD_ENV_FILE:-$ops_root/config/build.env}"
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  . "$config_file"
fi

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
if [ -n "${SSHPASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
  ssh_bin=(sshpass -e ssh)
fi

run_step() {
  local name=$1
  shift
  local start
  start="$(date +%s)"
  echo "[step] $name started"
  "$@"
  local end
  end="$(date +%s)"
  echo "[timing] step=$name elapsed=$((end - start))s"
}

if [ "$#" -ne 0 ]; then
  echo "usage: remote-package-all.sh" >&2
  exit 2
fi

remote_ops_dir="${REMOTE_OPS_DIR:-/data/edream-build/sources/ai-relay-ops}"

run_step upload-local "$ops_root/scripts/sources/upload-local.sh"
run_step remote-package-all "${ssh_bin[@]}" $ssh_opts "$ssh_target" "cd '$remote_ops_dir' && scripts/build/package-all.sh"

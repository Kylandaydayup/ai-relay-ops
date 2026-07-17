#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ops_root="$(cd "$script_dir/../.." && pwd)"
. "$ops_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

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
  echo "usage: package-all.sh" >&2
  exit 2
fi

if [ "${SKIP_SOURCE_SYNC:-1}" = "1" ]; then
  echo "[step] sync-sources skipped: SKIP_SOURCE_SYNC=1"
else
  run_step sync-sources "$ops_root/scripts/sources/sync.sh"
fi
run_step image-preflight "$ops_root/scripts/images/preflight.sh"
run_step build-all "$ops_root/scripts/images/build-all.sh"
run_step package "$ops_root/scripts/platform/package.sh"
run_step package-images "$ops_root/scripts/platform/package-images.sh"

#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "usage: build-all.sh" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/../lib/timing.sh"
start_script_timer "${0##*/}"

export IMAGE_TAG_TIMESTAMP="${IMAGE_TAG_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"

"$script_dir/build-new-api.sh"
"$script_dir/build-broker.sh"
"$script_dir/build-ai-provider-adapter.sh"
"$script_dir/build-newapi-compat-gateway.sh"
"$script_dir/build-edreamcrowd-backend.sh"
"$script_dir/build-edreamcrowd-frontend.sh"
"$script_dir/ensure-casdoor.sh"
"$script_dir/build-gateway.sh"

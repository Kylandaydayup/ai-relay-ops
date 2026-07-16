#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: build-all.sh <134|139>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export IMAGE_TAG_TIMESTAMP="${IMAGE_TAG_TIMESTAMP:-$(date '+%Y%m%d%H%M%S')}"

"$script_dir/build-new-api.sh" "$env_name"
"$script_dir/build-broker.sh" "$env_name"
"$script_dir/build-ai-provider-adapter.sh" "$env_name"
"$script_dir/build-newapi-compat-gateway.sh" "$env_name"
"$script_dir/build-edreamcrowd-backend.sh" "$env_name"
"$script_dir/build-edreamcrowd-frontend.sh" "$env_name"
"$script_dir/build-casdoor.sh" "$env_name"
"$script_dir/build-gateway.sh" "$env_name"

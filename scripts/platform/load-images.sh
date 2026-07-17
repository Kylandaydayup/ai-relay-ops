#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
start_script_timer "${0##*/}"

if [ "$#" -ne 1 ]; then
  echo "usage: load-images.sh <image-archive.tar>" >&2
  exit 2
fi

image_archive=$1
if [[ "$image_archive" != /* ]]; then
  image_archive="$PWD/$image_archive"
fi
if [ ! -f "$image_archive" ]; then
  echo "image archive does not exist: $image_archive" >&2
  exit 2
fi

import_image_archive "$image_archive"

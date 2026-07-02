#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name="${ENV_NAME:-template}"
default_values_file="environments/${env_name}/values.yaml"
legacy_values_file="environments/${env_name}/platform.values.yaml"
values_file="${VALUES_FILE:-}"
bundle_name="${BUNDLE_NAME:-platform-bundle-${env_name}-$(date +%Y%m%d%H%M%S)}"
bundle_dir="${BUNDLE_DIR:-}"
image_dir="${IMAGE_DIR:-dist/platform-bundle/images}"
include_images="${INCLUDE_IMAGES:-true}"
archive="${ARCHIVE:-true}"

cd "$repo_root"

if ! command -v helm >/dev/null 2>&1; then
  echo "missing required command: helm" >&2
  exit 2
fi

if [ -z "$values_file" ]; then
  if [ -f "$default_values_file" ]; then
    values_file="$default_values_file"
  else
    values_file="$legacy_values_file"
  fi
fi

if [ -z "$bundle_dir" ]; then
  bundle_dir="dist/${bundle_name}"
fi

if [ ! -f "$values_file" ]; then
  echo "missing values file: $values_file" >&2
  exit 2
fi

rm -rf "$bundle_dir"
mkdir -p "$bundle_dir/values" "$bundle_dir/scripts" "$bundle_dir/images" "$bundle_dir/docs"

helm dependency build charts/platform

cp -R charts "$bundle_dir/"
cp "$values_file" "$bundle_dir/values/values.yaml"
cp scripts/load-platform-images.sh "$bundle_dir/scripts/load-platform-images.sh"
cp scripts/install-platform-bundle.sh "$bundle_dir/scripts/install-platform-bundle.sh"
cp scripts/deploy-platform-bundle.sh "$bundle_dir/scripts/deploy-platform-bundle.sh"
cp docs/platform-bundle.md "$bundle_dir/README.md"
chmod +x "$bundle_dir/scripts/"*.sh

if [ "$include_images" = "true" ]; then
  if [ ! -d "$image_dir" ]; then
    echo "missing image directory: $image_dir" >&2
    echo "run scripts/build-platform-images.sh first, or set INCLUDE_IMAGES=false" >&2
    exit 2
  fi
  cp -R "$image_dir"/. "$bundle_dir/images/"
fi

if [ "$archive" = "true" ]; then
  tarball="${bundle_dir}.tar.gz"
  tar -C "$(dirname "$bundle_dir")" -czf "$tarball" "$(basename "$bundle_dir")"
  echo "platform bundle archive: $tarball"
else
  echo "platform bundle directory: $bundle_dir"
fi

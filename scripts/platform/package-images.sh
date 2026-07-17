#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
start_script_timer "${0##*/}"
if [ "$#" -gt 0 ]; then
  echo "usage: package-images.sh" >&2
  exit 2
fi

require_command docker
if [ -f "${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}" ]; then
  # shellcheck disable=SC1090
  . "${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}"
fi

deployment_values_file="${PACKAGE_DEPLOYMENT_VALUES_FILE:-${DEPLOYMENT_VALUES_FILE:-}}"
if [ -z "$deployment_values_file" ]; then
  echo "DEPLOYMENT_VALUES_FILE or PACKAGE_DEPLOYMENT_VALUES_FILE is required" >&2
  exit 2
fi
if [[ "$deployment_values_file" != /* ]]; then
  deployment_values_file="$OPS_ROOT/$deployment_values_file"
fi
if [ ! -f "$deployment_values_file" ]; then
  echo "deployment values file does not exist: $deployment_values_file" >&2
  exit 2
fi

package_name="${IMAGE_PACKAGE_NAME:-edream-platform-images-$(date '+%Y%m%d%H%M%S')}"
package_dir="${IMAGE_PACKAGE_DIR:-${BUILD_PACKAGE_DIR:-$OPS_ROOT/dist}}"
archive_path="${IMAGE_ARCHIVE:-$package_dir/$package_name.tar}"
manifest_path="${IMAGE_MANIFEST:-$package_dir/$package_name.txt}"

mkdir -p "$package_dir"
mapfile -t package_images < <(deployment_images "$deployment_values_file")
if [ "${#package_images[@]}" -eq 0 ]; then
  echo "no images found in deployment values: $deployment_values_file" >&2
  exit 1
fi

save_images=()
for image in "${package_images[@]}"; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    save_images+=("$image")
    continue
  fi

  build_image="$image"
  if [ -n "${HARBOR_REGISTRY:-}" ] && [ -n "${HARBOR_BUILD_REGISTRY:-}" ] && [ "$HARBOR_REGISTRY" != "$HARBOR_BUILD_REGISTRY" ]; then
    case "$image" in
      "$HARBOR_REGISTRY"/*)
        build_image="$HARBOR_BUILD_REGISTRY/${image#"$HARBOR_REGISTRY"/}"
        ;;
    esac
  fi

  if docker image inspect "$build_image" >/dev/null 2>&1; then
    docker tag "$build_image" "$image"
    save_images+=("$image")
    continue
  fi

  if docker pull "$build_image" >/dev/null 2>&1; then
    docker tag "$build_image" "$image"
    save_images+=("$image")
    continue
  fi

  if docker pull "$image" >/dev/null 2>&1; then
    save_images+=("$image")
    continue
  fi

  echo "missing package image: $image" >&2
  echo "also checked local build image: $build_image" >&2
  exit 1
done

tmp_archive="${archive_path}.tmp"
tmp_manifest="${manifest_path}.tmp"
rm -f "$tmp_archive" "$tmp_manifest"

{
  echo "# edream platform image package"
  echo "created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "values_file=$deployment_values_file"
  echo
  printf '%s\n' "${package_images[@]}"
} > "$tmp_manifest"

echo "packaging image archive: $archive_path"
printf '  %s\n' "${package_images[@]}"
docker save -o "$tmp_archive" "${save_images[@]}"
mv "$tmp_archive" "$archive_path"
mv "$tmp_manifest" "$manifest_path"

if [ -n "${BUILD_PACKAGE_DIR:-}" ]; then
  cp -f "$archive_path" "$BUILD_PACKAGE_DIR/edream-platform-images-current.tar"
  cp -f "$manifest_path" "$BUILD_PACKAGE_DIR/edream-platform-images-current.txt"
  echo "image package current: $BUILD_PACKAGE_DIR/edream-platform-images-current.tar"
  echo "image manifest current: $BUILD_PACKAGE_DIR/edream-platform-images-current.txt"
fi

echo "image package: $archive_path"
echo "image manifest: $manifest_path"

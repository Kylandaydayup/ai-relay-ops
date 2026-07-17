#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
start_script_timer "${0##*/}"
if [ "$#" -gt 0 ]; then
  echo "usage: package.sh" >&2
  exit 2
fi

require_command helm
if [ -f "${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}" ]; then
  # shellcheck disable=SC1090
  . "${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}"
fi

CHART_DIR="$OPS_ROOT/charts/platform"
package_name="${PACKAGE_NAME:-edream-platform-$(date '+%Y%m%d%H%M%S')}"
dist_dir="${DIST_DIR:-$OPS_ROOT/dist/$package_name}"
archive="${ARCHIVE:-true}"

rm -rf "$dist_dir"
mkdir -p "$dist_dir/charts" "$dist_dir/environments" "$dist_dir/scripts" "$dist_dir/docker" "$dist_dir/docs" "$dist_dir/config"

helm_dependency_build

cp -R "$OPS_ROOT/charts/." "$dist_dir/charts/"
cp -R "$OPS_ROOT/environments/." "$dist_dir/environments/"
cp "$OPS_ROOT/config/build.env.example" "$dist_dir/config/build.env.example"
cp -R "$OPS_ROOT/scripts/images" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/platform" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/harbor" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/sources" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/build" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/maintenance" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/lib" "$dist_dir/scripts/"
cp "$OPS_ROOT/scripts/verify-standard-deployment.sh" "$dist_dir/scripts/verify-standard-deployment.sh"
cp -R "$OPS_ROOT/docker/." "$dist_dir/docker/"
cp "$OPS_ROOT/README.md" "$dist_dir/README.md"

find "$dist_dir/scripts" -type f -name "*.sh" -exec chmod +x {} \;

if [ "$archive" = "true" ]; then
  tarball="${dist_dir}.tar.gz"
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$dist_dir" >/dev/null 2>&1 || true
  fi
  tar_args=()
  if tar --no-xattrs --no-mac-metadata -cf /dev/null --files-from /dev/null >/dev/null 2>&1; then
    tar_args+=(--no-xattrs --no-mac-metadata)
  fi
  COPYFILE_DISABLE=1 tar "${tar_args[@]}" -C "$(dirname "$dist_dir")" -czf "$tarball" "$(basename "$dist_dir")"
  echo "platform package: $tarball"
  if [ -n "${BUILD_PACKAGE_DIR:-}" ]; then
    mkdir -p "$BUILD_PACKAGE_DIR"
    cp -f "$tarball" "$BUILD_PACKAGE_DIR/$(basename "$tarball")"
    cp -f "$tarball" "$BUILD_PACKAGE_DIR/edream-platform-current.tar.gz"
    echo "platform package copied: $BUILD_PACKAGE_DIR/$(basename "$tarball")"
    echo "platform package current: $BUILD_PACKAGE_DIR/edream-platform-current.tar.gz"
  fi
else
  echo "platform package directory: $dist_dir"
fi

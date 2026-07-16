#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-platform.sh"
init_platform_env "$@"

require_command helm

package_name="${PACKAGE_NAME:-edream-platform-$(date '+%Y%m%d%H%M%S')}"
dist_dir="${DIST_DIR:-$OPS_ROOT/dist/$package_name}"
archive="${ARCHIVE:-true}"

rm -rf "$dist_dir"
mkdir -p "$dist_dir/charts" "$dist_dir/environments/$ENV_NAME" "$dist_dir/scripts" "$dist_dir/docker" "$dist_dir/docs"

helm_dependency_build

cp -R "$OPS_ROOT/charts/." "$dist_dir/charts/"
cp "$DEPLOYMENT_FILE" "$dist_dir/environments/$ENV_NAME/edream-deployment.yaml"
cp "$ENV_DIR/harbor.yaml" "$dist_dir/environments/$ENV_NAME/harbor.yaml"
cp -R "$OPS_ROOT/scripts/images" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/platform" "$dist_dir/scripts/"
cp -R "$OPS_ROOT/scripts/harbor" "$dist_dir/scripts/"
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
else
  echo "platform package directory: $dist_dir"
fi

#!/usr/bin/env bash
set -euo pipefail

bundle_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_dir="${IMAGE_DIR:-$bundle_root/images}"
runtime="${CONTAINER_RUNTIME:-auto}"
namespace="${CONTAINERD_NAMESPACE:-k8s.io}"

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

detect_runtime() {
  if [ "$runtime" != "auto" ]; then
    printf '%s\n' "$runtime"
    return 0
  fi

  if command -v k3s >/dev/null 2>&1; then
    printf 'k3s\n'
    return 0
  fi
  if command -v ctr >/dev/null 2>&1; then
    printf 'ctr\n'
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    printf 'docker\n'
    return 0
  fi

  echo "cannot detect container runtime; set CONTAINER_RUNTIME=docker|ctr|k3s" >&2
  exit 2
}

if [ ! -d "$image_dir" ]; then
  echo "missing image directory: $image_dir" >&2
  exit 2
fi

selected_runtime="$(detect_runtime)"
case "$selected_runtime" in
  docker)
    require_command docker
    ;;
  ctr)
    require_command ctr
    ;;
  k3s)
    require_command k3s
    ;;
  *)
    echo "unsupported container runtime: $selected_runtime" >&2
    exit 2
    ;;
esac

found=0
for image_tar in "$image_dir"/*.tar; do
  [ -f "$image_tar" ] || continue
  found=1
  echo "loading image: $image_tar"
  case "$selected_runtime" in
    docker)
      docker load -i "$image_tar"
      ;;
    ctr)
      ctr -n "$namespace" images import "$image_tar"
      ;;
    k3s)
      k3s ctr -n "$namespace" images import "$image_tar"
      ;;
  esac
done

if [ "$found" = "0" ]; then
  echo "no image tar files found under $image_dir" >&2
  exit 2
fi

echo "images loaded from $image_dir"

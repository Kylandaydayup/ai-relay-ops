#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
. "$repo_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

failures=()

require_file() {
  local file=$1
  if [ ! -f "$file" ]; then
    failures+=("missing required file: $file")
  fi
}

require_executable() {
  local file=$1
  require_file "$file"
  if [ -f "$file" ] && [ ! -x "$file" ]; then
    failures+=("file must be executable: $file")
  fi
}

forbid_path() {
  local path=$1
  if compgen -G "$path" >/dev/null; then
    failures+=("forbidden path exists: $path")
  fi
}

forbid_text() {
  local file=$1
  local pattern=$2
  local reason=$3
  if [ -f "$file" ] && grep -q -- "$pattern" "$file"; then
    failures+=("$file must not contain '$pattern': $reason")
  fi
}

require_file config/build.env.example
require_file charts/platform/values.yaml
require_file environments/template/edream-deployment.yaml
require_file environments/134/edream-deployment.yaml
require_file environments/139/edream-deployment.yaml
require_file scripts/lib/timing.sh

for script in \
  scripts/build/package-all.sh \
  scripts/build/remote-package-all.sh \
  scripts/images/lib-image-build.sh \
  scripts/images/preflight.sh \
  scripts/images/sync-base-images.sh \
  scripts/images/build-new-api.sh \
  scripts/images/build-broker.sh \
  scripts/images/build-ai-provider-adapter.sh \
  scripts/images/build-newapi-compat-gateway.sh \
  scripts/images/build-edreamcrowd-backend.sh \
  scripts/images/build-edreamcrowd-frontend.sh \
  scripts/images/build-casdoor.sh \
  scripts/images/ensure-casdoor.sh \
  scripts/images/build-gateway.sh \
  scripts/images/build-all.sh \
  scripts/sources/upload-local.sh \
  scripts/sources/sync.sh \
  scripts/platform/preflight.sh \
  scripts/platform/render.sh \
  scripts/platform/package.sh \
  scripts/platform/install.sh \
  scripts/platform/upgrade.sh \
  scripts/platform/uninstall.sh \
  scripts/platform/status.sh \
  scripts/maintenance/cleanup-build-host.sh \
  scripts/harbor/login.sh \
  scripts/harbor/check.sh; do
  require_executable "$script"
done

for script in scripts/images/base/*.sh; do
  require_executable "$script"
done

forbid_path "docker/project-base/*"
forbid_path "scripts/images/project-base/*"
forbid_path "scripts/images/build-project-base-images.sh"
forbid_path "environments/*/harbor.yaml"
forbid_path "environments/**/*.values.yaml"
forbid_path "scripts/*139.sh"
forbid_path "scripts/legacy/*"
forbid_path "nginx/staging/*"

forbid_text scripts/platform/upgrade.sh "--install" "upgrade must not install"
forbid_text scripts/platform/upgrade.sh "--set" "all runtime values must come from the deployment values file"
forbid_text scripts/platform/install.sh "upgrade --install" "install must use helm install"
forbid_text scripts/platform/install.sh "--set" "all runtime values must come from the deployment values file"
forbid_text scripts/platform/package.sh 'edream-platform-${ENV_NAME}' "package names must be environment-neutral"

if grep -R "CHANGE_ME" environments/134 environments/139 >/dev/null 2>&1; then
  failures+=("134/139 deployment files must not contain CHANGE_ME placeholders")
fi

if grep -R --exclude=verify-standard-deployment.sh -E "projectBase|harbor.yaml|build-project-base-images" \
  README.md docs scripts docker environments config >/dev/null 2>&1; then
  failures+=("project-base image layer and harbor.yaml references must be removed")
fi

if grep -R -E "require_project_base_image|push_runtime_image|ensure_project_base_image" scripts/images >/dev/null 2>&1; then
  failures+=("runtime image scripts must only use generic base images and push final runtime images")
fi

if grep -R -E "usage: .*<134\\|139>|init_image_build \"\\$@\".*<134" scripts/images >/dev/null 2>&1; then
  failures+=("image build scripts must not accept 134/139 environment arguments")
fi

if grep -R -E "HARBOR_(REGISTRY|BASE_PROJECT|RUNTIME_PROJECT)" environments >/dev/null 2>&1; then
  failures+=("Harbor build configuration must not live in deployment values")
fi

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'standard deployment verification failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "standard deployment verification passed"

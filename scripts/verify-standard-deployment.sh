#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

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
    failures+=("forbidden legacy path still exists: $path")
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

require_file charts/platform/values.yaml
require_file charts/new-api/values.yaml
require_file charts/broker/values.yaml
require_file charts/postgres/values.yaml

require_file environments/template/edream-deployment.yaml
require_file environments/134/edream-deployment.yaml
require_file environments/139/edream-deployment.yaml

for env in 134 139; do
  require_file "environments/${env}/edream-deployment.yaml"
  require_file "environments/${env}/harbor.yaml"
done

for script in \
  scripts/images/lib-image-build.sh \
  scripts/images/build-new-api.sh \
  scripts/images/build-broker.sh \
  scripts/images/build-ai-provider-adapter.sh \
  scripts/images/build-newapi-compat-gateway.sh \
  scripts/images/build-edreamcrowd-backend.sh \
  scripts/images/build-edreamcrowd-frontend.sh \
  scripts/images/build-casdoor.sh \
  scripts/images/build-gateway.sh \
  scripts/images/build-all.sh \
  scripts/images/sync-base-images.sh \
  scripts/platform/preflight.sh \
  scripts/platform/render.sh \
  scripts/platform/package.sh \
  scripts/platform/install.sh \
  scripts/platform/upgrade.sh \
  scripts/platform/uninstall.sh \
  scripts/platform/status.sh \
  scripts/harbor/login.sh \
  scripts/harbor/check.sh; do
  require_executable "$script"
done

forbid_path "environments/staging/*.values.yaml"
forbid_path "environments/prod/*.values.yaml"
forbid_path "environments/**/*.values.yaml"
forbid_path "environments/legacy/*"
forbid_path "scripts/*139.sh"
forbid_path "scripts/legacy/*"
forbid_path "nginx/staging/*"

forbid_text scripts/platform/upgrade.sh "--install" "upgrade must not install"
forbid_text scripts/platform/upgrade.sh "--set" "all runtime values must come from the environment deployment file"
forbid_text scripts/platform/install.sh "upgrade --install" "install must use helm install"
forbid_text scripts/platform/install.sh "--set" "all runtime values must come from the environment deployment file"
forbid_text scripts/platform/package.sh 'edream-platform-${ENV_NAME}' "package names must be environment-neutral"

if grep -R "CHANGE_ME" environments/134 environments/139 >/dev/null 2>&1; then
  failures+=("134/139 deployment files must not contain CHANGE_ME placeholders")
fi

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'standard deployment verification failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "standard deployment verification passed"

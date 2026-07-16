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

validate_environment() {
  local env_name=$1
  local deployment_file="environments/${env_name}/edream-deployment.yaml"
  local harbor_file="environments/${env_name}/harbor.yaml"

  if ! command -v ruby >/dev/null 2>&1; then
    failures+=("ruby is required for deployment YAML validation")
    return
  fi

  local output
  if ! output="$(ruby -ryaml -e '
    env_name, deployment_file, harbor_file = ARGV
    data = YAML.load_file(deployment_file) || {}
    harbor_data = YAML.load_file(harbor_file) || {}
    harbor = harbor_data.fetch("harbor", {})
    registry = harbor.fetch("registry", "")
    base_project = harbor.fetch("baseProject", "base-images")
    project_base_project = harbor.fetch("projectBaseProject", "")
    project_base_tag = harbor.fetch("projectBaseTag", "")
    runtime_project = harbor.fetch("runtimeProject", "platform")
    base_prefix = "#{registry}/#{base_project}/"
    runtime_prefix = "#{registry}/#{runtime_project}/"
    problems = []

    if project_base_project.empty?
      problems << "#{harbor_file}: harbor.projectBaseProject is required"
    end
    if project_base_tag.empty? || project_base_tag == "current" || project_base_tag == "latest"
      problems << "#{harbor_file}: harbor.projectBaseTag must be explicit and must not be current/latest"
    end

    def dig_hash(data, *keys)
      keys.reduce(data) { |memo, key| memo.is_a?(Hash) ? memo[key] : nil }
    end

    broker_enabled = dig_hash(data, "broker", "enabled") != false
    sync_enabled = dig_hash(data, "broker", "modelRechargeSync", "enabled") == true
    sync_schedule = dig_hash(data, "broker", "modelRechargeSync", "schedule")
    if broker_enabled && sync_enabled && sync_schedule != "*/10 * * * *"
      problems << "#{deployment_file}: broker.modelRechargeSync.schedule must be */10 * * * *, got #{sync_schedule.inspect}"
    end

    if env_name == "139"
      image_specs = [
        ["databaseInit.image", base_prefix, dig_hash(data, "databaseInit", "enabled") != false, dig_hash(data, "databaseInit", "image")],
        ["postgres.image", base_prefix, dig_hash(data, "postgres", "enabled") != false, dig_hash(data, "postgres", "image")],
        ["new-api.image", runtime_prefix, dig_hash(data, "new-api", "enabled") != false, dig_hash(data, "new-api", "image")],
        ["new-api.postgresWait.image", base_prefix, dig_hash(data, "new-api", "enabled") != false && dig_hash(data, "new-api", "postgresWait", "enabled") != false, dig_hash(data, "new-api", "postgresWait", "image")],
        ["ai-provider-adapter.image", runtime_prefix, dig_hash(data, "ai-provider-adapter", "enabled") != false, dig_hash(data, "ai-provider-adapter", "image")],
        ["newapi-compat-gateway.image", runtime_prefix, dig_hash(data, "newapi-compat-gateway", "enabled") != false, dig_hash(data, "newapi-compat-gateway", "image")],
        ["broker.image", runtime_prefix, broker_enabled, dig_hash(data, "broker", "image")],
        ["broker.postgresWait.image", base_prefix, broker_enabled && dig_hash(data, "broker", "postgresWait", "enabled") != false, dig_hash(data, "broker", "postgresWait", "image")],
        ["casdoor.image", runtime_prefix, dig_hash(data, "casdoor", "enabled") != false, dig_hash(data, "casdoor", "image")],
        ["casdoor.postgresWait.image", base_prefix, dig_hash(data, "casdoor", "enabled") != false && dig_hash(data, "casdoor", "postgresWait", "enabled") != false, dig_hash(data, "casdoor", "postgresWait", "image")],
        ["edreamcrowd.backend.image", runtime_prefix, dig_hash(data, "edreamcrowd", "enabled") != false, dig_hash(data, "edreamcrowd", "backend", "image")],
        ["edreamcrowd.backend.postgresWait.image", base_prefix, dig_hash(data, "edreamcrowd", "enabled") != false && dig_hash(data, "edreamcrowd", "backend", "postgresWait", "enabled") != false, dig_hash(data, "edreamcrowd", "backend", "postgresWait", "image")],
        ["edreamcrowd.frontend.image", runtime_prefix, dig_hash(data, "edreamcrowd", "enabled") != false, dig_hash(data, "edreamcrowd", "frontend", "image")],
        ["gateway.image", runtime_prefix, dig_hash(data, "gateway", "enabled") != false, dig_hash(data, "gateway", "image")]
      ]

      image_specs.each do |label, expected_prefix, enabled, image|
        next unless enabled
        unless image.is_a?(Hash)
          problems << "#{deployment_file}: #{label} must be configured for enabled components"
          next
        end
        repository = image["repository"].to_s
        tag = image["tag"].to_s
        unless repository.start_with?(expected_prefix)
          problems << "#{deployment_file}: #{label}.repository must start with #{expected_prefix}, got #{repository.inspect}"
        end
        if tag.empty? || tag == "latest" || tag.include?("local-nogit")
          problems << "#{deployment_file}: #{label}.tag must be explicit, traceable, and must not be latest/local-nogit"
        end
      end
    end

    puts problems
    exit(problems.empty? ? 0 : 1)
  ' "$env_name" "$deployment_file" "$harbor_file" 2>&1)"; then
    while IFS= read -r line; do
      [ -n "$line" ] && failures+=("$line")
    done <<< "$output"
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
  scripts/images/build-project-base-images.sh \
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

for script in scripts/images/base/*.sh scripts/images/project-base/*.sh; do
  require_executable "$script"
done

forbid_path "environments/staging/*.values.yaml"
forbid_path "environments/prod/*.values.yaml"
forbid_path "environments/**/*.values.yaml"
forbid_path "environments/legacy/*"
forbid_path "scripts/*139.sh"
forbid_path "scripts/legacy/*"
forbid_path "nginx/staging/*"
forbid_path "docker/base/*"
forbid_path "scripts/images/build-base-images.sh"

forbid_text scripts/platform/upgrade.sh "--install" "upgrade must not install"
forbid_text scripts/platform/upgrade.sh "--set" "all runtime values must come from the environment deployment file"
forbid_text scripts/platform/install.sh "upgrade --install" "install must use helm install"
forbid_text scripts/platform/install.sh "--set" "all runtime values must come from the environment deployment file"
forbid_text scripts/platform/package.sh 'edream-platform-${ENV_NAME}' "package names must be environment-neutral"

if grep -R "CHANGE_ME" environments/134 environments/139 >/dev/null 2>&1; then
  failures+=("134/139 deployment files must not contain CHANGE_ME placeholders")
fi

if grep -R -E "(apt-get[[:space:]]|apt[[:space:]]|apk[[:space:]]|yum[[:space:]]|dnf[[:space:]]|go mod download|mvn .*dependency:go-offline|npm ci|yarn install|bun install|pip install)" \
  docker/ai-relay-broker docker/casdoor docker/new-api docker/edreamcrowd docker/gateway >/dev/null 2>&1; then
  failures+=("runtime Dockerfiles must not download dependencies or install system packages; put those steps in docker/project-base")
fi

if grep -R "ensure_project_base_image\\|ensure_.*_builder\\|ensure_.*_runtime" \
  scripts/images/build-new-api.sh \
  scripts/images/build-broker.sh \
  scripts/images/build-ai-provider-adapter.sh \
  scripts/images/build-newapi-compat-gateway.sh \
  scripts/images/build-edreamcrowd-backend.sh \
  scripts/images/build-edreamcrowd-frontend.sh \
  scripts/images/build-casdoor.sh \
  scripts/images/build-gateway.sh >/dev/null 2>&1; then
  failures+=("runtime image build scripts must require existing Harbor base images, not build project-base images")
fi

if grep -q "build-project-base-images.sh\\|build-base-images.sh" scripts/images/build-all.sh; then
  failures+=("build-all.sh must only compose runtime image scripts; project-base images must be built explicitly")
fi

if grep -R "ensure_base_image" scripts/images/project-base >/dev/null 2>&1; then
  failures+=("project-base image scripts must pull generic base images from Harbor with require_base_image")
fi

if find . \
  -path ./.git -prune -o \
  -path ./dist -prune -o \
  -path ./build -prune -o \
  -path ./scripts/verify-standard-deployment.sh -prune -o \
  -type f -print \
  | xargs grep -E "build-cache|cacheProject|HARBOR_CACHE_PROJECT" >/dev/null 2>&1; then
  failures+=("build-cache naming is forbidden; use harbor.projectBaseProject/project-base-images")
fi

if grep -R --exclude=verify-standard-deployment.sh -E "HARBOR_(BASE_PROJECT|PROJECT_BASE_PROJECT|RUNTIME_PROJECT)" build scripts >/dev/null 2>&1; then
  failures+=("Harbor project names must only come from environments/<env>/harbor.yaml")
fi

for env in 134 139; do
  validate_environment "$env"
done

if [ "${#failures[@]}" -gt 0 ]; then
  printf 'standard deployment verification failed:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "standard deployment verification passed"

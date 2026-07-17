#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"
config_file="${BUILD_ENV_FILE:-$repo_root/config/build.env}"

if [ ! -f "$config_file" ]; then
  echo "missing build config: $config_file" >&2
  exit 2
fi
# shellcheck disable=SC1090
. "$config_file"

harbor_version="${HARBOR_VERSION:-v2.12.2}"
install_dir="${HARBOR_INSTALL_DIR:-/opt/harbor}"
data_dir="${HARBOR_DATA_DIR:-/data/harbor}"
http_port="${HARBOR_PORT:-80}"
hostname="${HARBOR_HOST:-${HARBOR_REGISTRY:?HARBOR_REGISTRY is required}}"

if [ -z "${HARBOR_ADMIN_PASSWORD:-}" ]; then
  echo "HARBOR_ADMIN_PASSWORD is required in $config_file" >&2
  exit 2
fi

sudo mkdir -p "$install_dir" "$data_dir"
cd "$install_dir"

archive="harbor-offline-installer-${harbor_version}.tgz"
if [ ! -f "$archive" ]; then
  echo "missing $install_dir/$archive" >&2
  echo "download it first or copy it to the server, then rerun this script" >&2
  exit 2
fi

sudo tar -xzf "$archive" --strip-components=1
sudo cp harbor.yml.tmpl harbor.yml

sudo HARBOR_HOST="$hostname" \
  HARBOR_PORT="$http_port" \
  HARBOR_ADMIN_PASSWORD="$HARBOR_ADMIN_PASSWORD" \
  HARBOR_DATA_DIR="$data_dir" \
  HARBOR_CONFIG_PATH="$install_dir/harbor.yml" \
  python3 - <<'PY'
import os
from pathlib import Path

p = Path(os.environ["HARBOR_CONFIG_PATH"])
s = p.read_text()
s = s.replace("hostname: reg.mydomain.com", f"hostname: {os.environ['HARBOR_HOST']}")
s = s.replace("port: 80", f"port: {os.environ['HARBOR_PORT']}", 1)
s = s.replace("harbor_admin_password: Harbor12345", f"harbor_admin_password: {os.environ['HARBOR_ADMIN_PASSWORD']}")
s = s.replace("data_volume: /data", f"data_volume: {os.environ['HARBOR_DATA_DIR']}")

lines = s.splitlines()
out = []
in_https = False
for line in lines:
    if line.startswith("https:"):
        in_https = True
        out.append("# " + line)
        continue
    if in_https:
        if line and not line.startswith(" ") and not line.startswith("#"):
            in_https = False
            out.append(line)
        else:
            out.append("# " + line if line and not line.startswith("#") else line)
    else:
        out.append(line)
p.write_text("\n".join(out) + "\n")
PY

sudo ./install.sh

for project in "${HARBOR_BASE_PROJECT:-base-images}" "${HARBOR_RUNTIME_PROJECT:-platform}"; do
  if [ -z "$project" ]; then
    continue
  fi
  status="$(curl -sS --max-time 20 -o /tmp/harbor-project-create.out -w '%{http_code}' \
    -u "${HARBOR_ADMIN_USER:-admin}:$HARBOR_ADMIN_PASSWORD" \
    -H 'Content-Type: application/json' \
    -X POST "http://${hostname}:${http_port}/api/v2.0/projects" \
    -d "{\"project_name\":\"${project}\",\"public\":false}" || true)"
  if [ "$status" = "201" ] || [ "$status" = "409" ]; then
    echo "Harbor project ready: $project"
  else
    echo "failed to create Harbor project $project, status=$status" >&2
    cat /tmp/harbor-project-create.out >&2 || true
    exit 1
  fi
done

echo "Harbor is expected at http://${hostname}:${http_port}"

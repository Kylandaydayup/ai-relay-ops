#!/usr/bin/env bash
set -euo pipefail

registry="${1:?usage: configure-docker-registry.sh <registry>}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"
daemon_file="${DOCKER_DAEMON_FILE:-/etc/docker/daemon.json}"

sudo mkdir -p "$(dirname "$daemon_file")"
tmp="$(mktemp)"
if [ -f "$daemon_file" ]; then
  sudo cp "$daemon_file" "$tmp"
else
  printf '{}\n' > "$tmp"
fi

python3 - "$tmp" "$registry" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
registry = sys.argv[2]
try:
    data = json.loads(path.read_text() or "{}")
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid Docker daemon JSON: {exc}")

items = data.setdefault("insecure-registries", [])
if registry not in items:
    items.append(registry)
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

sudo install -m 0644 "$tmp" "$daemon_file"
rm -f "$tmp"
echo "updated $daemon_file"
echo "restart Docker to apply: sudo systemctl restart docker"

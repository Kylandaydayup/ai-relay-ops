#!/usr/bin/env bash
set -euo pipefail

registry="${1:?usage: configure-k3s-registry.sh <registry>}"
registries_file="${REGISTRIES_FILE:-/etc/rancher/k3s/registries.yaml}"

sudo mkdir -p "$(dirname "$registries_file")"
tmp="$(mktemp)"
if [ -f "$registries_file" ]; then
  sudo cp "$registries_file" "$tmp"
else
  : > "$tmp"
fi

python3 - "$tmp" "$registry" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
registry = sys.argv[2]
existing = path.read_text()
block = f'''mirrors:
  "{registry}":
    endpoint:
      - "http://{registry}"
configs:
  "{registry}":
    tls:
      insecure_skip_verify: true
'''
if registry in existing:
    print(existing, end="")
else:
    if existing.strip():
        print(existing.rstrip())
        print()
    print(block, end="")
PY

sudo install -m 0644 "$tmp" "$registries_file"
rm -f "$tmp"
echo "updated $registries_file"
echo "restart k3s to apply: sudo systemctl restart k3s"

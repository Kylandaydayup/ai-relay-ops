#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

values_file="${1:-$repo_root/nginx/staging/platform.values.env}"
template_file="${2:-$repo_root/nginx/staging/platform.conf.tpl}"
target_file="${3:-/etc/nginx/sites-enabled/new-api.conf}"
available_file="${4:-/etc/nginx/sites-available/new-api.conf}"
backup_dir="${BACKUP_DIR:-/root/nginx-backups}"
rendered_file="$(mktemp "${TMPDIR:-/tmp}/platform-nginx.XXXXXX.conf")"

"$repo_root/scripts/render-nginx-config.sh" "$values_file" "$template_file" "$rendered_file"

mkdir -p "$backup_dir"
if [ -f "$target_file" ]; then
  cp "$target_file" "$backup_dir/$(basename "$target_file").$(date +%Y%m%d%H%M%S)"
fi

cp "$rendered_file" "$target_file"
if [ -n "$available_file" ]; then
  cp "$rendered_file" "$available_file"
fi

nginx -t
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
elif nginx -s reload; then
  :
else
  masters="$(ps -eo pid=,cmd= | awk '/nginx: master process/ {print $1}')"
  if [ -z "$masters" ]; then
    echo "nginx is not active and no nginx master process was found" >&2
    exit 1
  fi
  # shellcheck disable=SC2086
  kill -HUP $masters
fi

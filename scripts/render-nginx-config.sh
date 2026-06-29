#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <values.env> <template.conf.tpl> <output.conf>" >&2
  exit 2
fi

values_file=$1
template_file=$2
output_file=$3

set -a
# shellcheck disable=SC1090
source "$values_file"
set +a

python3 - "$template_file" "$output_file" <<'PY'
import os
import re
import sys

template_path, output_path = sys.argv[1:3]
with open(template_path, "r", encoding="utf-8") as source:
    template = source.read()

rendered_lines = []
include_stack = []
include_current = True

for line_number, line in enumerate(template.splitlines(keepends=True), start=1):
    if_match = re.match(r"\s*#@if\s+([A-Z0-9_]+)\s*$", line)
    if if_match:
        variable = if_match.group(1)
        include_stack.append(include_current)
        include_current = include_current and bool(os.environ.get(variable, "").strip())
        continue

    endif_match = re.match(r"\s*#@endif\s*$", line)
    if endif_match:
        if not include_stack:
            raise SystemExit(f"unexpected #@endif at {template_path}:{line_number}")
        include_current = include_stack.pop()
        continue

    if include_current:
        rendered_lines.append(line)

if include_stack:
    raise SystemExit("unterminated #@if block in " + template_path)

template = "".join(rendered_lines)
missing = sorted(set(re.findall(r"\$\{([A-Z0-9_]+)\}", template)) - set(os.environ))
if missing:
    raise SystemExit("missing values: " + ", ".join(missing))

rendered = re.sub(r"\$\{([A-Z0-9_]+)\}", lambda match: os.environ[match.group(1)], template)
with open(output_path, "w", encoding="utf-8") as target:
    target.write(rendered)
PY

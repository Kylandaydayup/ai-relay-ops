#!/usr/bin/env bash
set -euo pipefail

source_ssh="${SOURCE_SSH:-ubuntu@134.175.68.24}"
target_ssh="${TARGET_SSH:-root@139.196.254.8}"
namespace="${NAMESPACE:-platform}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
backup_root="${BACKUP_ROOT:-/root/platform-backups}"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/casdoor-user-sync.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

source_users="$workdir/source-users.txt"
target_users="$workdir/target-users.txt"
missing_users="$workdir/missing-users.txt"
source_cols="$workdir/source-user-cols.txt"
target_cols="$workdir/target-user-cols.txt"
missing_csv="$workdir/missing-users.csv"

source_psql() {
  printf "%s\n" "$1" | ssh "$source_ssh" "sudo -u postgres psql -At -d casdoor"
}

target_psql() {
  printf "%s\n" "$1" | ssh "$target_ssh" "kubectl exec -i -n '$namespace' '$postgres_pod' -- psql -U postgres -At -d casdoor"
}

source_psql "SELECT owner || '/' || name FROM \"user\" ORDER BY owner,name;" | LC_ALL=C sort > "$source_users"
target_psql "SELECT owner || '/' || name FROM \"user\" ORDER BY owner,name;" | LC_ALL=C sort > "$target_users"
comm -23 "$source_users" "$target_users" > "$missing_users"

if [ ! -s "$missing_users" ]; then
  echo "no missing Casdoor users on target"
  exit 0
fi

source_psql "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'user' ORDER BY ordinal_position;" > "$source_cols"
target_psql "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'user' ORDER BY ordinal_position;" > "$target_cols"
if ! cmp -s "$source_cols" "$target_cols"; then
  echo "source and target Casdoor user schemas differ; refusing to import" >&2
  diff -u "$source_cols" "$target_cols" || true
  exit 1
fi

where_clause="$(python3 - "$missing_users" <<'PY'
import sys

def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

pairs = []
with open(sys.argv[1], "r", encoding="utf-8") as source:
    for raw in source:
        raw = raw.strip()
        if not raw:
            continue
        owner, name = raw.split("/", 1)
        pairs.append(f"({quote(owner)},{quote(name)})")

print("(owner, name) IN (" + ",".join(pairs) + ")")
PY
)"

printf "%s\n" "COPY (SELECT * FROM \"user\" WHERE ${where_clause} ORDER BY owner,name) TO STDOUT WITH (FORMAT csv, HEADER true, FORCE_QUOTE *);" |
  ssh "$source_ssh" "sudo -u postgres psql -d casdoor" > "$missing_csv"

backup_path="$(ssh "$target_ssh" "set -e; mkdir -p '$backup_root'; backup='$backup_root/casdoor-before-user-sync-'\\\$(date +%Y%m%d%H%M%S)'.dump'; kubectl exec -n '$namespace' '$postgres_pod' -- pg_dump -U postgres -d casdoor --format=custom --no-owner --no-privileges > \"\\\$backup\"; echo \"\\\$backup\"")"
cat "$missing_csv" | ssh "$target_ssh" "kubectl exec -i -n '$namespace' '$postgres_pod' -- psql -U postgres -d casdoor -v ON_ERROR_STOP=1 -c \"COPY \\\"user\\\" FROM STDIN WITH (FORMAT csv, HEADER true);\""

target_psql "SELECT owner || '/' || name FROM \"user\" ORDER BY owner,name;" | LC_ALL=C sort > "$target_users"
if comm -23 "$source_users" "$target_users" | grep -q .; then
  echo "some source users are still missing on target" >&2
  comm -23 "$source_users" "$target_users" >&2
  exit 1
fi

echo "synced $(($(wc -l < "$missing_csv") - 1)) Casdoor users"
echo "target backup: $backup_path"

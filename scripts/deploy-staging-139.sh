#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
namespace="${NAMESPACE:-platform}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
staging_secret_file="${STAGING_SECRET_FILE:-/root/platform-secrets/staging.env}"

cd "$repo_root"

if [ ! -f "$staging_secret_file" ]; then
  echo "missing staging secret file: $staging_secret_file" >&2
  exit 2
fi

secret_value_or_empty() {
  local secret_name=$1
  local secret_key=$2

  if ! kubectl get secret -n "$namespace" "$secret_name" >/dev/null 2>&1; then
    return 0
  fi
  kubectl get secret -n "$namespace" "$secret_name" -o jsonpath="{.data.${secret_key}}" 2>/dev/null | base64 -d || true
}

required_config() {
  local name=$1
  local value=$2

  if [ -z "$value" ]; then
    echo "missing required config: $name in $staging_secret_file or existing Kubernetes Secret" >&2
    exit 2
  fi
}

sql_string() {
  printf "%s" "$1" | sed "s/'/''/g"
}

ensure_allowed_pg_name() {
  case "$1" in
    broker|broker_db|casdoor|edreamcrowd|newapi)
      ;;
    *)
      echo "refusing unexpected postgres identifier: $1" >&2
      exit 2
      ;;
  esac
}

ensure_postgres_role() {
  local role=$1
  local password=$2
  local escaped_password

  ensure_allowed_pg_name "$role"
  required_config "${role^^}_DB_PASSWORD" "$password"
  escaped_password="$(sql_string "$password")"
  kubectl exec -n "$namespace" platform-postgres-0 -- psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${role}') THEN CREATE ROLE ${role} LOGIN PASSWORD '${escaped_password}'; ELSE ALTER ROLE ${role} WITH LOGIN PASSWORD '${escaped_password}'; END IF; END \$\$;"
}

ensure_postgres_database() {
  local database=$1
  local owner=$2

  ensure_allowed_pg_name "$database"
  ensure_allowed_pg_name "$owner"
  if ! kubectl exec -n "$namespace" platform-postgres-0 -- psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -q 1; then
    kubectl exec -n "$namespace" platform-postgres-0 -- createdb -U postgres -O "$owner" "$database"
  fi
  kubectl exec -n "$namespace" platform-postgres-0 -- psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER DATABASE ${database} OWNER TO ${owner}; GRANT ALL PRIVILEGES ON DATABASE ${database} TO ${owner};"
}

# shellcheck disable=SC1090
. "$staging_secret_file"

postgres_password="${POSTGRES_PASSWORD:-$(secret_value_or_empty platform-postgres-secret POSTGRES_PASSWORD)}"
required_config POSTGRES_PASSWORD "$postgres_password"

casdoor_db_password="${CASDOOR_DB_PASSWORD:-}"
edream_db_password="${EDREAMCROWD_DB_PASSWORD:-$(secret_value_or_empty edreamcrowd-backend-secret SPRING_DATASOURCE_PASSWORD)}"
newapi_db_password="${NEWAPI_DB_PASSWORD:-}"
broker_db_password="${BROKER_DB_PASSWORD:-}"
required_config CASDOOR_DB_PASSWORD "$casdoor_db_password"
required_config EDREAMCROWD_DB_PASSWORD "$edream_db_password"
required_config NEWAPI_DB_PASSWORD "$newapi_db_password"
required_config BROKER_DB_PASSWORD "$broker_db_password"

newapi_sql_dsn="${NEWAPI_SQL_DSN:-postgresql://newapi:${newapi_db_password}@platform-postgres:5432/newapi}"
newapi_redis_conn_string="${NEWAPI_REDIS_CONN_STRING:-$(secret_value_or_empty relay-new-api-secret REDIS_CONN_STRING)}"
newapi_session_secret="${NEWAPI_SESSION_SECRET:-$(secret_value_or_empty relay-new-api-secret SESSION_SECRET)}"
newapi_crypto_secret="${NEWAPI_CRYPTO_SECRET:-$(secret_value_or_empty relay-new-api-secret CRYPTO_SECRET)}"
required_config NEWAPI_SESSION_SECRET "$newapi_session_secret"
required_config NEWAPI_CRYPTO_SECRET "$newapi_crypto_secret"

broker_database_url="${BROKER_DATABASE_URL:-postgresql+psycopg://broker:${broker_db_password}@platform-postgres:5432/broker_db}"
broker_casdoor_client_secret="${BROKER_CASDOOR_CLIENT_SECRET:-$(secret_value_or_empty relay-broker-secret CASDOOR_CLIENT_SECRET)}"
broker_newapi_token="${BROKER_NEWAPI_ADMIN_ACCESS_TOKEN:-${NEWAPI_ADMIN_ACCESS_TOKEN:-$(secret_value_or_empty relay-broker-secret NEWAPI_ADMIN_ACCESS_TOKEN)}}"
broker_internal_api_key="${BROKER_INTERNAL_API_KEY:-$(secret_value_or_empty relay-broker-secret INTERNAL_API_KEY)}"
required_config BROKER_INTERNAL_API_KEY "$broker_internal_api_key"
if [ -z "$broker_newapi_token" ]; then
  broker_newapi_token="change-me"
fi

edream_jasypt_password="${EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD:-$(secret_value_or_empty edreamcrowd-backend-secret JASYPT_ENCRYPTOR_PASSWORD)}"
edream_casdoor_access_key="${EDREAMCROWD_CASDOOR_ACCESS_KEY:-$(secret_value_or_empty edreamcrowd-backend-secret CASDOOR_ACCESS_KEY)}"
edream_casdoor_access_secret="${EDREAMCROWD_CASDOOR_ACCESS_SECRET:-$(secret_value_or_empty edreamcrowd-backend-secret CASDOOR_ACCESS_SECRET)}"
required_config EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD "$edream_jasypt_password"

casdoor_dsn="user=casdoor password=${casdoor_db_password} host=platform-postgres port=5432 sslmode=disable dbname=casdoor"

helm upgrade --install platform-db charts/postgres \
  -n "$namespace" \
  --create-namespace \
  -f environments/staging/postgres.values.yaml \
  --set-string auth.password="$postgres_password"

kubectl rollout status statefulset/platform-postgres -n "$namespace" --timeout=240s

ensure_postgres_role casdoor "$casdoor_db_password"
ensure_postgres_database casdoor casdoor
ensure_postgres_role edreamcrowd "$edream_db_password"
ensure_postgres_database edreamcrowd edreamcrowd
ensure_postgres_role newapi "$newapi_db_password"
ensure_postgres_database newapi newapi
ensure_postgres_role broker "$broker_db_password"
ensure_postgres_database broker_db broker

helm upgrade --install relay-new-api charts/new-api \
  -n "$namespace" \
  -f environments/staging/new-api.values.yaml \
  --set-string secret.SQL_DSN="$newapi_sql_dsn" \
  --set-string secret.REDIS_CONN_STRING="$newapi_redis_conn_string" \
  --set-string secret.SESSION_SECRET="$newapi_session_secret" \
  --set-string secret.CRYPTO_SECRET="$newapi_crypto_secret"

helm upgrade --install relay-broker charts/broker \
  -n "$namespace" \
  -f environments/staging/broker.values.yaml \
  --set-string secret.DATABASE_URL="$broker_database_url" \
  --set-string secret.CASDOOR_CLIENT_SECRET="$broker_casdoor_client_secret" \
  --set-string secret.NEWAPI_ADMIN_ACCESS_TOKEN="$broker_newapi_token" \
  --set-string secret.INTERNAL_API_KEY="$broker_internal_api_key"

helm upgrade --install casdoor charts/casdoor \
  -n "$namespace" \
  -f environments/staging/casdoor.values.yaml \
  --set-string config.dataSourceName="$casdoor_dsn"

helm upgrade --install edreamcrowd charts/edreamcrowd \
  -n "$namespace" \
  -f environments/staging/edreamcrowd.values.yaml \
  --set-string backend.secret.SPRING_DATASOURCE_PASSWORD="$edream_db_password" \
  --set-string backend.secret.JASYPT_ENCRYPTOR_PASSWORD="$edream_jasypt_password" \
  --set-string backend.secret.CASDOOR_ACCESS_KEY="$edream_casdoor_access_key" \
  --set-string backend.secret.CASDOOR_ACCESS_SECRET="$edream_casdoor_access_secret"

kubectl rollout status deployment/relay-new-api -n "$namespace" --timeout=180s
kubectl rollout status deployment/relay-broker -n "$namespace" --timeout=180s
kubectl rollout status deployment/casdoor -n "$namespace" --timeout=180s
kubectl rollout status deployment/edreamcrowd-backend -n "$namespace" --timeout=240s
kubectl rollout status deployment/edreamcrowd-frontend -n "$namespace" --timeout=180s

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
namespace="${NAMESPACE:-platform}"
release="${RELEASE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
staging_secret_file="${STAGING_SECRET_FILE:-/root/platform-secrets/staging.env}"
gateway_host_network="${GATEWAY_HOST_NETWORK:-true}"
allow_host_gateway_cutover="${ALLOW_HOST_GATEWAY_CUTOVER:-0}"
adopt_existing_releases="${ADOPT_EXISTING_RELEASES:-1}"
cleanup_old_helm_release_metadata="${CLEANUP_OLD_HELM_RELEASE_METADATA:-0}"

export KUBECONFIG="$kubeconfig"

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

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

is_nginx_active_on_host_port_80() {
  systemctl is-active --quiet nginx && ss -ltnp 2>/dev/null | grep -E '(:80[[:space:]]|:80$)' | grep -q nginx
}

restore_host_nginx_on_failure() {
  if [ "${host_nginx_stopped:-0}" = "1" ]; then
    systemctl start nginx >/dev/null 2>&1 || true
  fi
}

adopt_resource_if_present() {
  local resource=$1

  if kubectl get -n "$namespace" "$resource" >/dev/null 2>&1; then
    kubectl annotate -n "$namespace" "$resource" \
      meta.helm.sh/release-name="$release" \
      meta.helm.sh/release-namespace="$namespace" \
      --overwrite >/dev/null
    kubectl label -n "$namespace" "$resource" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
  fi
}

adopt_existing_resources() {
  local resources=(
    statefulset/platform-postgres
    service/platform-postgres
    secret/platform-postgres-secret
    deployment/relay-new-api
    service/relay-new-api
    secret/relay-new-api-secret
    deployment/ai-provider-adapter
    service/ai-provider-adapter
    secret/ai-provider-adapter-secret
    deployment/relay-broker
    service/relay-broker
    secret/relay-broker-secret
    deployment/casdoor
    service/casdoor
    configmap/casdoor-config
    deployment/edreamcrowd-backend
    deployment/edreamcrowd-frontend
    service/edreamcrowd-backend
    service/edreamcrowd-frontend
    configmap/edreamcrowd-frontend-nginx
    secret/edreamcrowd-backend-secret
  )

  for resource in "${resources[@]}"; do
    adopt_resource_if_present "$resource"
  done
}

cleanup_old_helm_metadata() {
  local old_releases=(platform-db relay-new-api relay-broker casdoor edreamcrowd)
  local old_release

  for old_release in "${old_releases[@]}"; do
    kubectl delete secret -n "$namespace" -l "owner=helm,name=${old_release}" --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete configmap -n "$namespace" -l "owner=helm,name=${old_release}" --ignore-not-found >/dev/null 2>&1 || true
  done
}

require_command helm
require_command kubectl

# shellcheck disable=SC1090
. "$staging_secret_file"

postgres_password="${POSTGRES_PASSWORD:-$(secret_value_or_empty platform-postgres-secret POSTGRES_PASSWORD)}"
casdoor_db_password="${CASDOOR_DB_PASSWORD:-}"
edream_db_password="${EDREAMCROWD_DB_PASSWORD:-$(secret_value_or_empty edreamcrowd-backend-secret SPRING_DATASOURCE_PASSWORD)}"
newapi_db_password="${NEWAPI_DB_PASSWORD:-}"
broker_db_password="${BROKER_DB_PASSWORD:-}"

required_config POSTGRES_PASSWORD "$postgres_password"
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
broker_casdoor_database_url="${BROKER_CASDOOR_DATABASE_URL:-postgresql+psycopg://casdoor:${casdoor_db_password}@platform-postgres:5432/casdoor}"
broker_casdoor_client_secret="${BROKER_CASDOOR_CLIENT_SECRET:-$(secret_value_or_empty relay-broker-secret CASDOOR_CLIENT_SECRET)}"
broker_newapi_token="${BROKER_NEWAPI_ADMIN_ACCESS_TOKEN:-${NEWAPI_ADMIN_ACCESS_TOKEN:-$(secret_value_or_empty relay-broker-secret NEWAPI_ADMIN_ACCESS_TOKEN)}}"
broker_internal_api_key="${BROKER_INTERNAL_API_KEY:-$(secret_value_or_empty relay-broker-secret INTERNAL_API_KEY)}"
required_config BROKER_INTERNAL_API_KEY "$broker_internal_api_key"
if [ -z "$broker_newapi_token" ]; then
  broker_newapi_token="change-me"
fi

moma_seedance_api_key="${MOMA_SEEDANCE_API_KEY:-$(secret_value_or_empty ai-provider-adapter-secret MOMA_SEEDANCE_API_KEY)}"
keyiyun_api_key="${KEYIYUN_API_KEY:-$(secret_value_or_empty ai-provider-adapter-secret KEYIYUN_API_KEY)}"

edream_jasypt_password="${EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD:-$(secret_value_or_empty edreamcrowd-backend-secret JASYPT_ENCRYPTOR_PASSWORD)}"
edream_casdoor_access_key="${EDREAMCROWD_CASDOOR_ACCESS_KEY:-$(secret_value_or_empty edreamcrowd-backend-secret CASDOOR_ACCESS_KEY)}"
edream_casdoor_access_secret="${EDREAMCROWD_CASDOOR_ACCESS_SECRET:-$(secret_value_or_empty edreamcrowd-backend-secret CASDOOR_ACCESS_SECRET)}"
required_config EDREAMCROWD_JASYPT_ENCRYPTOR_PASSWORD "$edream_jasypt_password"

casdoor_dsn="user=casdoor password=${casdoor_db_password} host=platform-postgres port=5432 sslmode=disable dbname=casdoor"

if [ "$gateway_host_network" = "true" ] && is_nginx_active_on_host_port_80; then
  if [ "$allow_host_gateway_cutover" != "1" ]; then
    echo "host Nginx is listening on port 80; refusing gateway hostNetwork cutover without ALLOW_HOST_GATEWAY_CUTOVER=1" >&2
    exit 2
  fi
  echo "stopping host Nginx so platform-gateway can bind port 80..."
  systemctl stop nginx
  host_nginx_stopped=1
  trap restore_host_nginx_on_failure EXIT
fi

kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
if [ "$adopt_existing_releases" = "1" ]; then
  adopt_existing_resources
fi

helm dependency build charts/platform

helm upgrade --install "$release" charts/platform \
  -n "$namespace" \
  -f environments/staging/platform.values.yaml \
  --set-string databaseInit.postgres.password="$postgres_password" \
  --set-string databaseInit.rolePasswords.casdoor="$casdoor_db_password" \
  --set-string databaseInit.rolePasswords.edreamcrowd="$edream_db_password" \
  --set-string databaseInit.rolePasswords.newapi="$newapi_db_password" \
  --set-string databaseInit.rolePasswords.broker="$broker_db_password" \
  --set-string postgres.auth.password="$postgres_password" \
  --set-string casdoor.config.dataSourceName="$casdoor_dsn" \
  --set-string new-api.secret.SQL_DSN="$newapi_sql_dsn" \
  --set-string new-api.secret.REDIS_CONN_STRING="$newapi_redis_conn_string" \
  --set-string new-api.secret.SESSION_SECRET="$newapi_session_secret" \
  --set-string new-api.secret.CRYPTO_SECRET="$newapi_crypto_secret" \
  --set-string ai-provider-adapter.secret.MOMA_SEEDANCE_API_KEY="$moma_seedance_api_key" \
  --set-string ai-provider-adapter.secret.KEYIYUN_API_KEY="$keyiyun_api_key" \
  --set-string broker.secret.DATABASE_URL="$broker_database_url" \
  --set-string broker.secret.CASDOOR_CLIENT_SECRET="$broker_casdoor_client_secret" \
  --set-string broker.secret.NEWAPI_ADMIN_ACCESS_TOKEN="$broker_newapi_token" \
  --set-string broker.secret.NEWAPI_DATABASE_URL="${newapi_sql_dsn/postgresql:\/\//postgresql+psycopg:\/\/}" \
  --set-string broker.secret.NEWAPI_REDIS_CONN_STRING="$newapi_redis_conn_string" \
  --set-string broker.secret.NEWAPI_CRYPTO_SECRET="$newapi_crypto_secret" \
  --set-string broker.secret.INTERNAL_API_KEY="$broker_internal_api_key" \
  --set-string broker.secret.CASDOOR_DATABASE_URL="$broker_casdoor_database_url" \
  --set-string edreamcrowd.backend.secret.SPRING_DATASOURCE_PASSWORD="$edream_db_password" \
  --set-string edreamcrowd.backend.secret.JASYPT_ENCRYPTOR_PASSWORD="$edream_jasypt_password" \
  --set-string edreamcrowd.backend.secret.CASDOOR_ACCESS_KEY="$edream_casdoor_access_key" \
  --set-string edreamcrowd.backend.secret.CASDOOR_ACCESS_SECRET="$edream_casdoor_access_secret" \
  --set-string gateway.hostNetwork.enabled="$gateway_host_network"

release_revision="$(helm list -n "$namespace" -o json | python3 -c 'import json, sys; release = sys.argv[1]; data = json.load(sys.stdin); print(next(item for item in data if item["name"] == release)["revision"])' "$release")"
postgres_init_job="${POSTGRES_INIT_JOB:-platform-postgres-init-${release_revision}}"
kubectl wait --for=condition=complete "job/${postgres_init_job}" -n "$namespace" --timeout=180s || true
kubectl rollout status statefulset/platform-postgres -n "$namespace" --timeout=240s
kubectl rollout status deployment/relay-new-api -n "$namespace" --timeout=180s
kubectl rollout status deployment/ai-provider-adapter -n "$namespace" --timeout=180s
kubectl rollout status deployment/relay-broker -n "$namespace" --timeout=180s
kubectl rollout status deployment/casdoor -n "$namespace" --timeout=180s
kubectl rollout status deployment/edreamcrowd-backend -n "$namespace" --timeout=240s
kubectl rollout status deployment/edreamcrowd-frontend -n "$namespace" --timeout=180s
kubectl rollout status deployment/platform-gateway -n "$namespace" --timeout=180s

if [ "${host_nginx_stopped:-0}" = "1" ]; then
  systemctl disable nginx >/dev/null 2>&1 || true
  trap - EXIT
fi

if [ "$cleanup_old_helm_release_metadata" = "1" ]; then
  cleanup_old_helm_metadata
fi

echo "platform release deployed: $release"

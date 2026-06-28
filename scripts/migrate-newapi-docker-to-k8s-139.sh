#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-platform}"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
postgres_pod="${POSTGRES_POD:-platform-postgres-0}"
k8s_database="${K8S_NEWAPI_DATABASE:-newapi}"
k8s_owner="${K8S_NEWAPI_OWNER:-newapi}"
k8s_deployment="${K8S_NEWAPI_DEPLOYMENT:-relay-new-api}"
docker_postgres_container="${DOCKER_NEWAPI_POSTGRES_CONTAINER:-new-api-postgres}"
docker_database="${DOCKER_NEWAPI_DATABASE:-new_api}"
docker_user="${DOCKER_NEWAPI_USER:-newapi}"
backup_root="${BACKUP_ROOT:-/root/platform-backups}"
timestamp="$(date +%Y%m%d%H%M%S)"
backup_dir="${backup_root}/newapi-docker-to-k8s-${timestamp}"
old_dump="${backup_dir}/docker-newapi.dump"
k8s_dump="${backup_dir}/k8s-newapi-before.dump"

export KUBECONFIG="$kubeconfig"

mkdir -p "$backup_dir"

echo "backup dir: $backup_dir"
echo "dumping current K8s new-api database..."
kubectl exec -n "$namespace" "$postgres_pod" -- \
  pg_dump -U postgres -d "$k8s_database" --format=custom --no-owner --no-privileges > "$k8s_dump"

echo "dumping legacy Docker new-api database..."
docker exec "$docker_postgres_container" \
  pg_dump -U "$docker_user" -d "$docker_database" --format=custom --no-owner --no-privileges > "$old_dump"

previous_replicas="$(kubectl get deployment -n "$namespace" "$k8s_deployment" -o jsonpath='{.spec.replicas}')"
if [ -z "$previous_replicas" ]; then
  previous_replicas=1
fi

restore_deployment() {
  kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas="$previous_replicas" >/dev/null 2>&1 || true
}
trap restore_deployment EXIT

echo "scaling K8s new-api deployment to zero..."
kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas=0
kubectl rollout status deployment/"$k8s_deployment" -n "$namespace" --timeout=120s || true

echo "resetting K8s new-api schema..."
kubectl exec -n "$namespace" "$postgres_pod" -- psql -U postgres -d "$k8s_database" -v ON_ERROR_STOP=1 \
  -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; ALTER SCHEMA public OWNER TO ${k8s_owner}; GRANT ALL ON SCHEMA public TO ${k8s_owner}; GRANT ALL ON SCHEMA public TO public;"

echo "restoring legacy Docker new-api data into K8s database..."
kubectl exec -i -n "$namespace" "$postgres_pod" -- \
  pg_restore -U postgres -d "$k8s_database" --no-owner --no-privileges --role="$k8s_owner" < "$old_dump"

echo "restoring K8s new-api deployment replicas: $previous_replicas"
kubectl scale deployment/"$k8s_deployment" -n "$namespace" --replicas="$previous_replicas"
trap - EXIT
kubectl rollout status deployment/"$k8s_deployment" -n "$namespace" --timeout=180s

echo "migration complete"
echo "K8s backup: $k8s_dump"
echo "Docker source dump: $old_dump"

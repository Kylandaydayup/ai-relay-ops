# Deployment Runbook

## Migration Order

1. Inventory existing production services with read-only commands.
2. Install Kubernetes on the validation host without changing production traffic.
3. Deploy the integrated stack in the `platform` namespace: Postgres, Casdoor, EDreamCrowd, `new-api`, and Broker.
4. Import business data into the validation databases.
5. Rewrite environment-specific OAuth callbacks and public origins for the validation host.
6. Apply the host Nginx entrypoint from this repository.
7. Validate browser entrypoints, OAuth login, New API status, Broker health, and EDreamCrowd flows.
8. Plan production migration only after the validation stack is repeatable and rollback is documented.

## First Install

```bash
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -
make install SERVICE=new-api ENV=prod NAMESPACE=platform
make install SERVICE=broker ENV=prod NAMESPACE=platform
```

## Staging 139 Upgrade

The 139 validation host keeps system-level ports and public paths in values files. Service-level runtime configuration is rendered into Pod specs by the Helm charts, while real secret values remain in Kubernetes Secrets and `/root/platform-secrets`.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
scripts/deploy-staging-139.sh
scripts/apply-nginx-config.sh
scripts/migrate-newapi-docker-to-k8s-139.sh
```

The Nginx script stores backups in `/root/nginx-backups`, outside `sites-enabled`, so backups are not accidentally loaded as active virtual hosts.

The New API migration script copies the legacy Docker New API database into the Kubernetes New API database, rewrites Casdoor OAuth endpoints to the validation host, and ensures the Casdoor `new-api` application exists with the local callback URL.

## Smoke Test

```bash
curl -fsS https://broker.example.com/healthz
curl -fsS https://broker.example.com/readyz
curl -fsS https://new-api.example.com/api/status
```

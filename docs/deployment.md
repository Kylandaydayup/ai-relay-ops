# Deployment Runbook

## Migration Order

1. Inventory existing host services.
2. Install Kubernetes without changing existing public traffic.
3. Deploy `new-api` and `broker` in the `platform` namespace.
4. Validate Broker -> new-api and Broker -> Casdoor.
5. Connect existing ArcReel deployment to Broker.
6. Migrate ArcReel-WhiteLabel after the new chain is stable.
7. Migrate Casdoor last.
8. Migrate EDreamCrowd last or leave it as direct deployment.

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
```

The Nginx script stores backups in `/root/nginx-backups`, outside `sites-enabled`, so backups are not accidentally loaded as active virtual hosts.

## Smoke Test

```bash
curl -fsS https://broker.example.com/healthz
curl -fsS https://broker.example.com/readyz
curl -fsS https://new-api.example.com/api/status
```

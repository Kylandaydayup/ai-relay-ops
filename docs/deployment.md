# Deployment Runbook

## Migration Order

1. Inventory existing production services with read-only commands.
2. Install Kubernetes on the validation host without changing production traffic.
3. Deploy the integrated stack in the `platform` namespace with the umbrella chart: Postgres, Casdoor, EDreamCrowd, `new-api`, Broker, and `platform-gateway`.
4. Import business data into the validation databases.
5. Rewrite environment-specific OAuth callbacks and public origins for the validation host.
6. Keep host Nginx as a temporary fallback, then explicitly cut over port 80 to the `platform-gateway` Pod after the K8s stack is healthy.
7. Validate browser entrypoints, OAuth login, New API status, Broker health, and EDreamCrowd flows.
8. Plan production migration only after the validation stack is repeatable and rollback is documented.

## First Install

```bash
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -
make template SERVICE=platform ENV=staging NAMESPACE=platform
scripts/deploy-staging-139.sh
```

## Staging 139 Upgrade

The 139 validation host keeps system-level ports and public paths in values files. Service-level runtime configuration is rendered into Pod specs by the Helm charts, while real secret values remain in Kubernetes Secrets and `/root/platform-secrets`.

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
scripts/deploy-staging-139.sh
scripts/configure-casdoor-staging-139.sh
scripts/migrate-newapi-docker-to-k8s-139.sh
```

The staging deploy script runs one `helm upgrade --install platform charts/platform` command after building local chart dependencies. It can adopt resources from the previous split releases (`platform-db`, `relay-new-api`, `relay-broker`, `casdoor`, `edreamcrowd`) by patching Helm ownership annotations, so existing PVCs and service names are preserved.

By default the script keeps the old NodePorts and does not stop host Nginx. To move the public entrypoint into Kubernetes, run:

```bash
GATEWAY_HOST_NETWORK=true ALLOW_HOST_GATEWAY_CUTOVER=1 scripts/deploy-staging-139.sh
```

If cutover fails after host Nginx is stopped, the script starts host Nginx again.

The New API migration script copies the legacy Docker New API database into the Kubernetes New API database, rewrites Casdoor OAuth endpoints to the validation host, and ensures the Casdoor `new-api` application exists with the local callback URL.

The Casdoor staging configuration script rewrites imported production application URLs for 139. In particular, it keeps the `edream` organization default application as `eDream_web` and points the app homepage to `http://139.196.254.8/zhongchou/`.

## Smoke Test

```bash
curl -fsS https://broker.example.com/healthz
curl -fsS https://broker.example.com/readyz
curl -fsS https://new-api.example.com/api/status
```

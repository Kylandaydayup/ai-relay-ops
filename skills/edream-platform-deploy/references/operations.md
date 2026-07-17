# eDream Platform Deployment Operations

This reference contains concrete command flows. Replace placeholders before running commands.

## 1. Parameter Intake

Collect these values before changing any environment:

```text
TARGET_HOST=<target server IP or hostname>
TARGET_USER=<ssh user>
TARGET_ENV=<environment name, for example 134, 139, staging>
NAMESPACE=<kubernetes namespace, usually platform>
VALUES_FILE=<path to environments/<env>/edream-deployment.yaml>
RELEASE_NAME=<helm release name from values>
BUILD_HOST=81.71.122.120
BUILD_USER=ubuntu
BUILD_ENV_FILE=config/build-81.env
REMOTE_OPS_DIR=/data/edream-build/sources/ai-relay-ops
PACKAGE_DIR=/data/edream-build/packages
DATA_POLICY=keep|delete
COMPONENTS=<new-api broker ai-provider-adapter newapi-compat-gateway edreamcrowd-backend edreamcrowd-frontend gateway casdoor>
ONLINE_HARBOR_PULL=yes|no
```

Discover release and namespace from a values file:

```bash
ruby -ryaml -e 'data=YAML.load_file(ARGV[0]); puts "release=#{data.dig("deployment","releaseName") || "platform"}"; puts "namespace=#{data["namespace"] || "platform"}"' \
  environments/139/edream-deployment.yaml
```

## 2. K3S Bootstrap

Use this only when the target machine does not already have a working k3s/Kubernetes cluster.

Check target host:

```bash
ssh <TARGET_USER>@<TARGET_HOST> '
set -e
hostname
uname -a
free -h
df -h /
command -v k3s || true
command -v kubectl || true
command -v helm || true
'
```

Single-node k3s install example:

```bash
ssh <TARGET_USER>@<TARGET_HOST> '
set -euo pipefail
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644
sudo kubectl get nodes
'
```

Install Helm if missing:

```bash
ssh <TARGET_USER>@<TARGET_HOST> '
set -euo pipefail
if ! command -v helm >/dev/null 2>&1; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version
'
```

Configure k3s/containerd to pull from Harbor:

```bash
ssh <TARGET_USER>@<TARGET_HOST> '
set -euo pipefail
cd /root/edream-deploy/current
BUILD_ENV_FILE=config/build-81.env scripts/harbor/configure-k3s-registry.sh
sudo systemctl restart k3s
kubectl get nodes
'
```

For multi-node k3s, collect server token, node list, role, private IPs, and firewall rules first. Do not infer them.

## 3. Configuration Files

Committed configuration:

```text
config/build-81.env
config/build.env.example
environments/<env>/edream-deployment.yaml
```

Runtime-only configuration:

```text
config/build.env
/data/edream-build/sources/ai-relay-ops/config/build.env
```

Read build host runtime config:

```bash
ssh ubuntu@81.71.122.120 '
cd /data/edream-build/sources/ai-relay-ops
sed -n "1,180p" config/build.env
'
```

Copy it locally if needed:

```bash
scp ubuntu@81.71.122.120:/data/edream-build/sources/ai-relay-ops/config/build.env ./config/build.env
```

Do not commit `config/build.env`.

## 4. Full Remote Build Package

Run from local ops repository:

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
scripts/build/remote-package-all.sh
```

Expected outputs on `81.71.122.120`:

```text
/data/edream-build/packages/edream-platform-<timestamp>.tar.gz
/data/edream-build/packages/edream-platform-current.tar.gz
/data/edream-build/packages/edream-platform-images-<timestamp>.tar
/data/edream-build/packages/edream-platform-images-current.tar
/data/edream-build/packages/edream-platform-images-current.txt
```

Copy the platform package to a target host:

```bash
scp ubuntu@81.71.122.120:/data/edream-build/packages/edream-platform-<timestamp>.tar.gz \
  <TARGET_USER>@<TARGET_HOST>:/root/edream-packages/
```

## 5. Install From Package

Run on target host:

```bash
mkdir -p /root/edream-packages /root/edream-deploy
cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current

cd /root/edream-deploy/current
scripts/verify-standard-deployment.sh
scripts/platform/preflight.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
scripts/platform/install.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
scripts/platform/status.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

If image pulls are slow:

```bash
ROLLOUT_TIMEOUT=900s scripts/platform/install.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

## 6. Upgrade From Package

Run on target host:

```bash
cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current

cd /root/edream-deploy/current
scripts/platform/preflight.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
scripts/platform/status.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

## 7. Keep-Data Uninstall and Reinstall

Default uninstall keeps data:

```bash
cd /root/edream-deploy/current
scripts/platform/uninstall.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

Verify PVC and retained config still exist:

```bash
kubectl -n <NAMESPACE> get pvc -o wide
kubectl -n <NAMESPACE> get secret,configmap | grep -E 'postgres|new-api|broker|adapter|edreamcrowd|casdoor'
```

Reinstall:

```bash
cd /root/edream-deploy/current
scripts/platform/install.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

## 8. Delete-Data Uninstall

Only use after explicit user confirmation:

```bash
DELETE_DATA=1 CONFIRM_DELETE_DATA=delete-<TARGET_ENV> \
  scripts/platform/uninstall.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

This deletes PVC and retained Secret/ConfigMap resources managed by the values file.

## 9. Backup Before Risky Operations

Back up retained Kubernetes resources:

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

kubectl -n <NAMESPACE> get \
  pvc/data-platform-postgres-0 \
  secret/platform-postgres-init-secret \
  secret/platform-postgres-secret \
  secret/relay-new-api-secret \
  secret/relay-broker-secret \
  secret/ai-provider-adapter-secret \
  secret/edreamcrowd-backend-secret \
  configmap/casdoor-config \
  -o yaml > "$backup_dir/kept-resources.yaml"
```

Back up Postgres:

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

kubectl -n <NAMESPACE> exec platform-postgres-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' \
  > "$backup_dir/postgres-dumpall.sql"
```

## 10. Single Image Build and Replace

Example: validate only `new-api` on 139.

Upload only needed sources:

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
UPLOAD_TARGETS="ops new-api" \
scripts/sources/upload-local.sh
```

Build image on `81.71.122.120` and update the target values file:

```bash
ssh ubuntu@81.71.122.120 '
set -euo pipefail
cd /data/edream-build/sources/ai-relay-ops
BUILD_ENV_FILE=config/build.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-new-api.sh
'
```

Package updated values:

```bash
ssh ubuntu@81.71.122.120 '
set -euo pipefail
cd /data/edream-build/sources/ai-relay-ops
BUILD_ENV_FILE=config/build.env scripts/platform/package.sh
'
```

Deploy by Helm upgrade on target host:

```bash
cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current
cd /root/edream-deploy/current
scripts/platform/preflight.sh -f environments/139/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
kubectl -n platform rollout status deployment/relay-new-api --timeout=600s
```

Temporary direct image replacement:

```bash
kubectl -n platform set image deployment/relay-new-api \
  new-api=81.71.122.120/platform/relay-new-api:<tag>
kubectl -n platform rollout status deployment/relay-new-api --timeout=600s
```

After temporary validation, update `environments/<env>/edream-deployment.yaml` and run Helm upgrade.

## 11. Multiple Image Build and Replace

Example: build and replace `new-api`, `broker`, and `edreamcrowd-frontend`.

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
UPLOAD_TARGETS="ops new-api broker edreamcrowd" \
scripts/sources/upload-local.sh

ssh ubuntu@81.71.122.120 '
set -euo pipefail
cd /data/edream-build/sources/ai-relay-ops
export BUILD_ENV_FILE=config/build.env
export DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml
scripts/images/build-new-api.sh
scripts/images/build-broker.sh
scripts/images/build-edreamcrowd-frontend.sh
scripts/platform/package.sh
'
```

Then transfer the generated platform package to the target host and run `scripts/platform/upgrade.sh`.

## 12. Offline Image Package

Load images before install or upgrade:

```bash
scripts/platform/load-images.sh /root/edream-packages/edream-platform-images-current.tar
scripts/platform/upgrade.sh -f environments/<TARGET_ENV>/edream-deployment.yaml
```

## 13. Validation

Minimum validation:

```bash
kubectl -n <NAMESPACE> get pods -o wide
kubectl -n <NAMESPACE> get pvc -o wide
kubectl -n <NAMESPACE> get deploy -o wide
curl -sS http://127.0.0.1:30080/readyz
curl -sS http://127.0.0.1:30080/healthz
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:30081
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:30082
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:30084
```

Casdoor OAuth smoke:

```bash
curl -sS 'http://127.0.0.1:30082/api/get-app-login?clientId=<client-id>&responseType=code&redirectUri=<urlencoded-redirect>&type=code&scope=read&state=test'
```

Expected response contains:

```json
{"status":"ok"}
```

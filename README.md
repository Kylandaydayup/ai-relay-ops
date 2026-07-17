# eDream Ops 运维手册

本仓库维护 eDream relay platform 的标准构建、打包、部署和数据保护流程。它的边界是：

- 构建各服务容器镜像并推送到 Harbor。
- 生成可分发的平台部署包和离线镜像包。
- 使用 Helm 在目标 Kubernetes/k3s 环境安装、升级、卸载平台。
- 管理部署配置、镜像版本、保留数据卸载重装、备份和恢复操作。

本仓库不保存生产密码、API key、数据库真实密码。敏感值应保存在目标集群的 Secret、目标机器本地文件或受控密钥系统中。

## 一、机器和组件角色

### 构建机

标准构建机：

```text
81.71.122.120
```

构建机职责：

- 保存源码快照：`/data/edream-build/sources`
- 保存历史源码备份：`/data/edream-build/source-snapshots`
- 保存构建缓存：`/data/edream-build/cache`
- 保存部署包：`/data/edream-build/packages`
- 运行 Docker/buildx 构建镜像
- 推送镜像到 Harbor

### Harbor

当前 Harbor 地址：

```text
81.71.122.120
```

镜像分两个 project：

```text
base-images   通用基础镜像，例如 python、node、go、nginx、postgres
platform      最终可运行服务镜像
```

服务镜像应基于 Harbor 中的 base image 构建。最终镜像只包含运行服务需要的文件；依赖下载、语言缓存、Docker build cache 留在构建机，不进入最终镜像。

### 目标运行环境

目标环境目前包括：

```text
134 环境：environments/134/edream-deployment.yaml
139 环境：environments/139/edream-deployment.yaml
```

部署脚本不应该写死 134/139 的 IP。环境差异统一放在 `environments/<env>/edream-deployment.yaml`。

## 二、运行依赖

### 构建机依赖

构建机 `81.71.122.120` 需要：

```text
Linux
Docker
Docker buildx
tar
git
ssh/scp
可访问 Harbor：81.71.122.120 或本机 Harbor endpoint
足够磁盘空间：普通构建至少 10GB，构建 Casdoor 至少 15GB
可用内存：普通构建至少 2GB，构建 Casdoor 至少 4GB
```

构建机预检查：

```bash
BUILD_ENV_FILE=config/build-81.env scripts/images/preflight.sh
```

### 部署目标机依赖

目标运行机器需要：

```text
k3s 或 Kubernetes
kubectl
helm
可访问 Harbor 镜像地址
KUBECONFIG 可用
```

如果目标机是 k3s，脚本会在未设置 `KUBECONFIG` 时尝试使用：

```text
/etc/rancher/k3s/k3s.yaml
```

基础检查：

```bash
kubectl get nodes
helm version
kubectl -n platform get pods
```

## 三、目录和配置文件

```text
charts/                         Helm chart。子 chart 有自己的默认 values。
environments/                   环境级部署配置。
environments/134/               134 环境部署配置。
environments/139/               139 环境部署配置。
config/build.env.example        构建配置示例。
config/build-81.env             81.71.122.120 构建机标准配置，可提交。
config/build.env                本机私有构建配置，不提交。
docker/                         构建镜像使用的 Dockerfile wrapper。
scripts/images/                 单镜像和全量镜像构建脚本。
scripts/platform/               install、upgrade、uninstall、render、package 脚本。
scripts/sources/                源码同步和本地上传脚本。
scripts/build/                  完整打包组合脚本。
scripts/maintenance/            构建机清理脚本。
```

### 可提交配置

这些配置可以提交：

```text
config/build-81.env
config/build.env.example
environments/134/edream-deployment.yaml
environments/139/edream-deployment.yaml
```

可提交配置里允许放：

- Harbor 地址
- 镜像 project
- 构建目录
- 源码目录
- 默认分支
- 默认镜像 tag label
- 非敏感资源名
- 非敏感 URL

可提交配置里不要放：

- Harbor 密码
- 数据库密码
- API key
- token
- OAuth client secret
- 加密密钥

### 私有配置

`config/build.env` 是本机私有配置，已被 `.gitignore` 忽略。

如果要在本机临时覆盖构建配置：

```bash
cp config/build-81.env config/build.env
vi config/build.env
```

也可以不复制，直接显式指定：

```bash
BUILD_ENV_FILE=config/build-81.env scripts/images/preflight.sh
```

### 81.71.122.120 上的真实配置

构建机当前使用的真实配置文件在：

```text
/data/edream-build/sources/ai-relay-ops/config/build.env
```

这个文件是 81.71.122.120 上的本机配置，不提交到 Git。它用于记录构建机当前实际使用的源码目录、Git URL、分支、默认 `DEPLOYMENT_VALUES_FILE`、构建缓存目录和包输出目录。

其他维护人员有 81.71.122.120 的 SSH 权限后，可以直接查看：

```bash
ssh ubuntu@81.71.122.120
cd /data/edream-build/sources/ai-relay-ops
sed -n '1,160p' config/build.env
```

也可以复制一份作为自己的构建配置起点：

```bash
scp ubuntu@81.71.122.120:/data/edream-build/sources/ai-relay-ops/config/build.env ./config/build.env
```

注意：

- `config/build-81.env` 是可提交的标准模板。
- `config/build.env` 是构建机或个人机器上的真实运行配置。
- 如果真实配置里加入密码、token、API key，只能保留在 `config/build.env` 或密钥系统中，不能提交到 Git。
- `upload-local.sh` 同步 ops 仓时会保留远端已有的 `config/build.env`，避免覆盖构建机真实配置。

### 环境部署配置

环境部署配置是 Helm 部署的事实来源：

```text
environments/134/edream-deployment.yaml
environments/139/edream-deployment.yaml
```

它们负责：

- release name
- namespace
- 服务启停
- 镜像 repository/tag
- NodePort
- 域名和回调地址
- 环境变量
- 引用的 Secret/ConfigMap 名称
- PVC 配置

如果只是替换镜像，优先修改目标环境的 `edream-deployment.yaml`，再执行 `scripts/platform/upgrade.sh`。

## 四、数据边界

当前 134/139 的业务数据主体在 Postgres PVC 中：

```text
pvc/data-platform-postgres-0
```

Postgres 内包含：

```text
casdoor     Casdoor 用户、OAuth 应用、订单等数据
newapi      new-api 用户、token、quota、OAuth binding 等数据
broker_db   broker 托管 key、账本、同步状态等数据
edreamcrowd 客户端业务数据
```

除了 PVC，还必须保留 Kubernetes 配置资源：

```text
secret/platform-postgres-init-secret
secret/platform-postgres-secret
secret/relay-new-api-secret
secret/relay-broker-secret
secret/ai-provider-adapter-secret
secret/edreamcrowd-backend-secret
configmap/casdoor-config
```

结论：

- 只保留 PVC 不够。
- PVC 是业务数据库数据。
- Secret/ConfigMap 是数据库密码、服务密钥、Casdoor app.conf 等运行配置。
- 数据保护操作必须同时覆盖 PVC、Secret、ConfigMap。

查看当前数据资源：

```bash
kubectl -n platform get pvc -o wide
kubectl -n platform get secret,configmap | grep -E 'postgres|new-api|broker|adapter|edreamcrowd|casdoor'
```

## 五、构建机初始化

在 `81.71.122.120` 上准备目录：

```bash
sudo mkdir -p /data/edream-build/sources
sudo mkdir -p /data/edream-build/source-snapshots
sudo mkdir -p /data/edream-build/cache
sudo mkdir -p /data/edream-build/packages
sudo chown -R "$USER:$USER" /data/edream-build
```

配置 Docker 可访问 Harbor。具体脚本：

```bash
BUILD_ENV_FILE=config/build-81.env scripts/harbor/configure-docker-registry.sh
BUILD_ENV_FILE=config/build-81.env scripts/harbor/login.sh
BUILD_ENV_FILE=config/build-81.env scripts/harbor/check.sh
```

同步基础镜像：

```bash
BUILD_ENV_FILE=config/build-81.env scripts/images/sync-base-images.sh
```

## 六、源码同步

推荐方式是本机上传源码到构建机。原因是构建机访问 GitHub 可能不稳定，本机上传更可控。

默认上传：

```text
ops
broker
new-api
EDreamCrowd
```

本机执行：

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
scripts/sources/upload-local.sh
```

上传后，构建机目录为：

```text
/data/edream-build/sources/ai-relay-ops
/data/edream-build/sources/ai-relay-broker
/data/edream-build/sources/new-api
/data/edream-build/sources/EDreamCrowd
```

旧源码会备份到：

```text
/data/edream-build/source-snapshots
```

默认拒绝脏工作区。如果确认要用未提交代码做临时构建：

```bash
ALLOW_DIRTY_UPLOAD=1 \
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
scripts/sources/upload-local.sh
```

Casdoor 默认不上传、不重建。需要重建时：

```bash
SYNC_CASDOOR=1 \
BUILD_CASDOOR=1 \
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
scripts/sources/upload-local.sh
```

## 七、单镜像构建

在构建机 `81.71.122.120` 上执行。

### new-api

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-new-api.sh
```

脚本会：

1. 从 `NEW_API_LOCAL_DIR` 读取源码。
2. 使用 Harbor base image。
3. 构建 `platform/relay-new-api:<tag>`。
4. 推送到 Harbor。
5. 如果设置了 `DEPLOYMENT_VALUES_FILE`，自动更新 values 中的 `new-api.image`。

### broker

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-broker.sh
```

### EDreamCrowd 后端和前端

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-edreamcrowd-backend.sh

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-edreamcrowd-frontend.sh
```

### adapter / compat gateway / gateway

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-ai-provider-adapter.sh

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-newapi-compat-gateway.sh

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-gateway.sh
```

### Casdoor

Casdoor 是第三方固定组件，默认复用 Harbor 中已有镜像：

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/ensure-casdoor.sh
```

只有需要重建 Casdoor 时：

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_CASDOOR=1 \
BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-casdoor.sh
```

## 八、完整构建和打包

### 本机触发远端完整打包

在本机执行：

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
scripts/build/remote-package-all.sh
```

流程：

```text
upload-local
  -> 上传 ops/broker/new-api/EDreamCrowd 到 81.71.122.120
remote package-all
  -> image preflight
  -> build-all
  -> package platform tar.gz
  -> package image tar
```

### 在构建机直接打包

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/build/package-all.sh
```

产物：

```text
/data/edream-build/packages/edream-platform-<timestamp>.tar.gz
/data/edream-build/packages/edream-platform-current.tar.gz
/data/edream-build/packages/edream-platform-images-<timestamp>.tar
/data/edream-build/packages/edream-platform-images-current.tar
/data/edream-build/packages/edream-platform-images-current.txt
```

说明：

- `edream-platform-*.tar.gz` 是平台小包，包含 chart、values、脚本，不包含镜像。
- `edream-platform-images-*.tar` 是镜像大包，用于离线部署。
- 在线部署只需要平台小包，镜像从 Harbor 拉。

## 九、部署包安装和升级

以下命令在目标运行机器执行，例如 139 环境机器。

### 解压部署包

```bash
mkdir -p /root/edream-packages
mkdir -p /root/edream-deploy

cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current

cd /root/edream-deploy/current
```

### 安装前检查

```bash
scripts/verify-standard-deployment.sh
scripts/platform/preflight.sh -f environments/139/edream-deployment.yaml
```

preflight 会检查：

- Helm chart 能否渲染。
- values 是否仍包含 `CHANGE_ME`。
- 外部 Secret/ConfigMap 是否存在。
- Casdoor postgres 配置是否完整。
- Casdoor 是否可能回退 sqlite。
- `dataSourceName` 和 `dbName` 是否为空。

### 首次安装

```bash
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

`install.sh` 使用 `helm install`。如果 release 已存在，它会失败并提示使用 upgrade。

### 升级

```bash
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

`upgrade.sh` 使用 `helm upgrade`。如果 release 不存在，它会失败并提示先 install。

慢镜像拉取或网络慢时：

```bash
ROLLOUT_TIMEOUT=900s scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

### 状态检查

```bash
scripts/platform/status.sh -f environments/139/edream-deployment.yaml
kubectl -n platform get pods -o wide
kubectl -n platform get pvc -o wide
kubectl -n platform get deploy -o wide
```

## 十、保留数据卸载和重装

默认卸载保留数据：

```bash
cd /root/edream-deploy/current

scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
```

脚本会：

1. 计算需要保留的 Secret/ConfigMap/PVC。
2. 导出保留资源到 `dist/platform-backups/<env>-<timestamp>/kept-resources.yaml`。
3. 给资源标记 `helm.sh/resource-policy=keep`。
4. 执行 `helm uninstall`。
5. 保留 PVC、Secret、ConfigMap。

确认数据仍在：

```bash
kubectl -n platform get pvc -o wide
kubectl -n platform get secret,configmap | grep -E 'postgres|new-api|broker|adapter|edreamcrowd|casdoor'
```

重新安装：

```bash
cd /root/edream-deploy/current

scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

确认 PVC 没变：

```bash
kubectl -n platform get pvc data-platform-postgres-0 -o wide
```

## 十一、删除数据卸载

危险操作。确认不要数据后才执行。

```bash
DELETE_DATA=1 CONFIRM_DELETE_DATA=delete-139 \
  scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
```

这会删除：

- Helm release
- Postgres PVC
- values 管理的保留 Secret/ConfigMap

生产环境不要随手执行。

## 十二、备份

推荐同时备份：

```text
Kubernetes 资源 YAML：Secret / ConfigMap / PVC 元数据
Postgres 逻辑数据：pg_dumpall 或分库 pg_dump
```

### 备份 Secret/ConfigMap/PVC 元数据

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

kubectl -n platform get \
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

### 备份全部 Postgres 数据

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

kubectl -n platform exec platform-postgres-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' \
  > "$backup_dir/postgres-dumpall.sql"
```

### 分库备份

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

for db in casdoor newapi broker_db edreamcrowd; do
  kubectl -n platform exec platform-postgres-0 -- \
    sh -c "PGPASSWORD=\"\$POSTGRES_PASSWORD\" pg_dump -U postgres $db" \
    > "$backup_dir/$db.sql"
done
```

### 原始 PVC 备份

原始 PVC 备份适合整盘兜底，不是首选恢复方式。直接复制文件前必须停 Postgres。

```bash
kubectl -n platform scale deployment --all --replicas=0
kubectl -n platform scale statefulset platform-postgres --replicas=0

pvc=data-platform-postgres-0
pv=$(kubectl -n platform get pvc "$pvc" -o jsonpath='{.spec.volumeName}')
kubectl get pv "$pv" -o yaml
```

根据 PV yaml 找到 local-path 真实路径后，在节点上打包。恢复前也必须停 Postgres。

## 十三、恢复

### 恢复 Kubernetes 资源

```bash
kubectl apply -f /root/edream-backups/<backup>/kept-resources.yaml
```

然后安装：

```bash
cd /root/edream-deploy/current
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

### 恢复 Postgres 逻辑备份

```bash
kubectl -n platform cp /root/edream-backups/<backup>/postgres-dumpall.sql \
  platform-postgres-0:/tmp/postgres-dumpall.sql

kubectl -n platform exec platform-postgres-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -f /tmp/postgres-dumpall.sql'
```

恢复后重启服务：

```bash
kubectl -n platform rollout restart deployment/relay-new-api
kubectl -n platform rollout restart deployment/relay-broker
kubectl -n platform rollout restart deployment/casdoor
kubectl -n platform rollout restart deployment/edreamcrowd-backend
kubectl -n platform rollout restart deployment/edreamcrowd-frontend
kubectl -n platform rollout restart deployment/platform-gateway
```

### 恢复原始 PVC

```bash
kubectl -n platform scale deployment --all --replicas=0
kubectl -n platform scale statefulset platform-postgres --replicas=0
```

在节点上把备份文件恢复到 PV 对应路径。完成后：

```bash
kubectl -n platform scale statefulset platform-postgres --replicas=1
kubectl -n platform rollout status statefulset/platform-postgres --timeout=600s
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## 十四、单镜像修改验证

场景：只验证 new-api 修改，不想完整重装平台。

### 标准方式：构建镜像，更新 values，Helm upgrade

在本机上传源码并触发构建：

```bash
BUILD_ENV_FILE=config/build-81.env \
REMOTE_BUILD_HOST=81.71.122.120 \
UPLOAD_TARGETS="ops new-api" \
scripts/sources/upload-local.sh
```

在 `81.71.122.120` 构建 new-api，并更新 139 values：

```bash
ssh ubuntu@81.71.122.120

cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/139/edream-deployment.yaml \
scripts/images/build-new-api.sh
```

把更新后的平台小包打出来：

```bash
cd /data/edream-build/sources/ai-relay-ops

BUILD_ENV_FILE=config/build-81.env \
scripts/platform/package.sh
```

在 139 目标机器上解压并升级：

```bash
cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current

cd /root/edream-deploy/current
scripts/platform/preflight.sh -f environments/139/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
kubectl -n platform rollout status deployment/relay-new-api --timeout=600s
```

### 临时方式：直接替换 Deployment 镜像

仅用于快速验证。验证完成后必须把同一个镜像 tag 写回 `environments/<env>/edream-deployment.yaml`。

```bash
kubectl -n platform set image deployment/relay-new-api \
  new-api=81.71.122.120/platform/relay-new-api:<tag>

kubectl -n platform rollout status deployment/relay-new-api --timeout=600s
kubectl -n platform get pod -l app.kubernetes.io/name=new-api -o wide
```

确认 container 名称：

```bash
kubectl -n platform get deploy relay-new-api \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}'
```

常见 Deployment 和 container：

```text
deployment/relay-new-api            container new-api
deployment/relay-broker             container broker
deployment/ai-provider-adapter      container ai-provider-adapter
deployment/newapi-compat-gateway    container newapi-compat-gateway
deployment/casdoor                  container casdoor
deployment/edreamcrowd-backend      container backend
deployment/edreamcrowd-frontend     container frontend
deployment/platform-gateway         container gateway
```

## 十五、离线部署

如果目标环境不能从 Harbor 拉镜像，先加载镜像包：

```bash
scripts/platform/load-images.sh /root/edream-packages/edream-platform-images-current.tar
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

升级：

```bash
scripts/platform/load-images.sh /root/edream-packages/edream-platform-images-current.tar
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## 十六、构建机清理

`81.71.122.120` 磁盘空间有限，完整打包后应定期清理可再生数据。

dry-run：

```bash
BUILD_ENV_FILE=config/build-81.env scripts/maintenance/cleanup-build-host.sh
```

执行清理：

```bash
CLEANUP_CONFIRM=1 \
BUILD_ENV_FILE=config/build-81.env \
scripts/maintenance/cleanup-build-host.sh
```

手动清理 Docker 可再生缓存：

```bash
docker builder prune -af
docker image prune -af
```

不要默认执行：

```bash
docker volume prune
```

Docker volume 可能包含服务或 Harbor 数据。

## 十七、常用验证

仓库结构校验：

```bash
scripts/verify-standard-deployment.sh
```

渲染 Helm manifest：

```bash
scripts/platform/render.sh -f environments/139/edream-deployment.yaml >/tmp/edream-render.yaml
```

服务状态：

```bash
kubectl -n platform get pods -o wide
kubectl -n platform get svc
kubectl -n platform get pvc -o wide
kubectl -n platform get deploy -o wide
```

HTTP smoke：

```bash
curl -sS http://127.0.0.1:30080/readyz
curl -sS http://127.0.0.1:30080/healthz
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30081
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30082
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30084
```

Casdoor OAuth：

```bash
curl -sS 'http://127.0.0.1:30082/api/get-app-login?clientId=<client-id>&responseType=code&redirectUri=<urlencoded-redirect>&type=code&scope=read&state=test'
```

期望返回包含：

```json
{"status":"ok"}
```

## 十八、发布检查清单

完整发布前检查：

```text
1. 代码分支确认。
2. 本地工作区无非预期脏改。
3. BUILD_ENV_FILE 指向正确构建配置。
4. 81.71.122.120 构建预检查通过。
5. 镜像已推送到 Harbor。
6. 目标 environments/<env>/edream-deployment.yaml 镜像 tag 正确。
7. 平台小包已传到目标机器。
8. preflight 通过。
9. upgrade 或 install 成功。
10. Pod/PVC/smoke 验证通过。
```

保留数据重装前检查：

```text
1. 已确认 PVC 名称和 PV。
2. 已备份 kept-resources.yaml。
3. 已做 Postgres 逻辑备份。
4. uninstall 未设置 DELETE_DATA=1。
5. 重装后 PVC volume id 未变化。
```

## 十九、禁止事项

- 不要把敏感密码提交到 Git。
- 不要在脚本里写死 134/139 环境差异。
- 不要绕过 preflight。
- 不要把 `kubectl set image` 的临时结果当成正式发布结果。
- 不要默认清理 Docker volumes。
- 不要在生产环境随手执行 `DELETE_DATA=1`。
- 不要只备份 PVC 而忽略 Secret/ConfigMap。

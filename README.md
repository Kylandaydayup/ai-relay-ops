# eDream Ops

这个仓库负责 eDream relay platform 的标准构建、打包、安装、升级和卸载流程。

目标是让新同学只改最外层配置文件，然后用脚本完成标准操作：

- 构建镜像
- 生成部署包
- 安装 / 升级 / 卸载平台
- 保留数据卸载重装
- 备份和恢复数据
- 单独替换某个服务镜像

## 目录约定

```text
charts/                 Helm chart。子 chart 有自己的默认 values。
environments/           环境级部署配置。134/139 只应该体现在这里。
config/build.env        构建机本地配置，不提交。
config/build.env.example 构建配置模板。
docker/                 构建镜像用的 Dockerfile wrapper。
scripts/images/         单镜像和全量镜像构建脚本。
scripts/platform/       安装、升级、卸载、渲染、打包脚本。
scripts/sources/        构建源码同步脚本。
scripts/build/          组合构建脚本。
scripts/maintenance/    构建机清理脚本。
```

环境级配置文件：

```text
environments/134/edream-deployment.yaml
environments/139/edream-deployment.yaml
```

后续部署到哪个环境，就在目标机器上使用对应的 `edream-deployment.yaml`。

## 数据在哪里

当前 134/139 的业务数据主体在 Kubernetes 的 Postgres PVC 里。

当前重要数据分两类：

```text
Postgres PVC
  Casdoor 数据
  new-api 数据
  broker 数据
  EDreamCrowd 数据

Kubernetes Secret / ConfigMap
  数据库密码
  服务密钥
  new-api secret
  broker secret
  EDreamCrowd secret
  Casdoor app.conf
```

所以不要只保留 PVC。保留数据时必须同时保留：

- `pvc/data-platform-postgres-0`
- `secret/platform-postgres-init-secret`
- `secret/platform-postgres-secret`
- `secret/relay-new-api-secret`
- `secret/relay-broker-secret`
- `secret/ai-provider-adapter-secret`
- `secret/edreamcrowd-backend-secret`
- `configmap/casdoor-config`

实际资源名以目标环境的 `edream-deployment.yaml` 为准。

查看当前 PVC：

```bash
kubectl -n platform get pvc -o wide
```

查看当前保留配置：

```bash
kubectl -n platform get secret,configmap | grep -E 'postgres|new-api|broker|adapter|edreamcrowd|casdoor'
```

当前 new-api chart 的独立文件 PVC 默认关闭，业务状态不在 new-api 容器本地目录里。如果未来启用了新的 PVC，必须把它加入备份和保留清单。

## 构建配置

构建脚本读取一个本机配置文件：

```bash
cp config/build.env.example config/build.env
vi config/build.env
```

`config/build.env` 不提交。它包含：

- Harbor 地址
- Harbor project
- 本地或构建机源码目录
- 目标 values 文件
- 构建缓存目录
- 镜像 tag 规则
- 构建包输出目录

134/139 不应该写进构建脚本。构建与环境无关，环境差异只放在 `environments/<env>/edream-deployment.yaml`。

## 81 构建机

81 是标准构建机：

```text
81.71.122.120
```

推荐流程是本机上传源码到 81，再由 81 构建。这样可以绕开 81 直连 GitHub 不稳定的问题。

本机执行：

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

默认上传：

```text
ops
broker
new-api
EDreamCrowd
```

Casdoor 默认不上传、不重建。Casdoor 是固定第三方组件，默认复用 Harbor 里已有镜像。只有明确需要重建时才加：

```bash
SYNC_CASDOOR=1 BUILD_CASDOOR=1 REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

`upload-local.sh` 默认拒绝脏工作区，避免把临时文件、构建产物、非预期修改传到构建机。

如果只是临时验证，确认风险后可以显式允许：

```bash
ALLOW_DIRTY_UPLOAD=1 REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

## 基础镜像

Harbor 中分两类镜像：

```text
base-images   通用基础镜像，例如 python/node/go/nginx/postgres
platform      最终可运行服务镜像
```

同步或补齐基础镜像：

```bash
scripts/images/sync-base-images.sh
```

正常服务镜像只应该基于 Harbor 中的 base image 构建，再复制代码产物和启动文件。构建时可以使用 Docker/language cache，但最终镜像只包含运行需要的内容。

## 单独构建镜像

构建某个服务镜像：

```bash
scripts/images/build-new-api.sh
scripts/images/build-broker.sh
scripts/images/build-ai-provider-adapter.sh
scripts/images/build-newapi-compat-gateway.sh
scripts/images/build-edreamcrowd-backend.sh
scripts/images/build-edreamcrowd-frontend.sh
scripts/images/build-gateway.sh
```

Casdoor 单独处理：

```bash
scripts/images/ensure-casdoor.sh
BUILD_CASDOOR=1 scripts/images/build-casdoor.sh
```

构建所有服务镜像：

```bash
scripts/images/build-all.sh
```

如果 `config/build.env` 中设置了 `DEPLOYMENT_VALUES_FILE`，构建脚本会在推送镜像后更新该 values 文件里的镜像 tag。

## 完整打包

在 81 构建机上完整打包：

```bash
scripts/build/package-all.sh
```

本机触发 81 完整打包：

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/build/remote-package-all.sh
```

这个脚本会：

1. 上传本地源码到 81。
2. 在 81 跑构建预检查。
3. 构建所有服务镜像。
4. 推送镜像到 Harbor。
5. 生成平台小包。
6. 生成镜像大包。

输出位置通常是：

```text
/data/edream-build/packages/edream-platform-<timestamp>.tar.gz
/data/edream-build/packages/edream-platform-current.tar.gz
/data/edream-build/packages/edream-platform-images-<timestamp>.tar
/data/edream-build/packages/edream-platform-images-current.tar
```

平台小包只包含 chart、values、脚本、Dockerfile wrapper，不包含镜像。

镜像大包用于离线部署。在线部署通常不需要传镜像大包，目标环境直接从 Harbor 拉镜像。

## 安装前检查

平台脚本会自动跑 preflight。也可以手动跑：

```bash
scripts/platform/preflight.sh -f environments/139/edream-deployment.yaml
```

preflight 会检查：

- values 文件是否有 `CHANGE_ME`
- Helm chart 能否渲染
- 外部 Secret/ConfigMap 是否存在
- Casdoor postgres 配置是否完整
- Casdoor 是否可能回退 sqlite
- Casdoor `dataSourceName/dbName` 是否为空

如果 preflight 失败，不要绕过。先修配置。

## 安装

在目标服务器上解压平台包：

```bash
mkdir -p /root/edream-deploy
cd /root/edream-deploy
tar -xzf /root/edream-packages/edream-platform-<timestamp>.tar.gz
ln -sfn /root/edream-deploy/edream-platform-<timestamp> /root/edream-deploy/current
cd /root/edream-deploy/current
```

安装：

```bash
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

`install.sh` 使用 `helm install`，不会执行 `helm upgrade --install`。

安装完成后检查：

```bash
scripts/platform/status.sh -f environments/139/edream-deployment.yaml
kubectl -n platform get pods -o wide
kubectl -n platform get pvc -o wide
```

## 升级

升级前建议先渲染确认：

```bash
scripts/platform/render.sh -f environments/139/edream-deployment.yaml >/tmp/edream-render.yaml
```

升级：

```bash
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

`upgrade.sh` 使用 `helm upgrade`。如果 release 不存在，它会失败并提示先 install。

慢镜像拉取时可以调大等待时间：

```bash
ROLLOUT_TIMEOUT=900s scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## 卸载但保留数据

默认卸载会保留数据：

```bash
scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
```

这个脚本会：

1. 找出需要保留的 Secret/ConfigMap/PVC。
2. 导出这些资源 YAML 到备份目录。
3. 给这些资源加 `helm.sh/resource-policy=keep`。
4. 执行 `helm uninstall`。
5. 保留 PVC、Secret、ConfigMap。

备份目录形如：

```text
dist/platform-backups/139-<timestamp>/kept-resources.yaml
```

卸载后确认数据资源还在：

```bash
kubectl -n platform get pvc
kubectl -n platform get secret,configmap | grep -E 'postgres|new-api|broker|adapter|edreamcrowd|casdoor'
```

保留数据后重新安装：

```bash
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

## 卸载并删除数据

危险操作。只有确定不要数据时使用。

```bash
DELETE_DATA=1 CONFIRM_DELETE_DATA=delete-139 \
  scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
```

这个操作会删除：

- Helm release
- Postgres PVC
- 被 values 管理的保留 Secret/ConfigMap

生产环境不要随手执行。

## 备份数据

建议同时做两层备份：

1. Kubernetes 资源备份：Secret/ConfigMap/PVC 元数据。
2. Postgres 逻辑备份：真正的业务数据。

### 备份保留资源 YAML

如果只是准备卸载，直接运行默认卸载脚本即可，它会自动生成：

```text
dist/platform-backups/<env>-<timestamp>/kept-resources.yaml
```

如果不想卸载，只想手动备份资源：

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

### 备份 Postgres 数据

推荐使用逻辑备份，比直接复制 PVC 更稳。

```bash
backup_dir=/root/edream-backups/$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"

kubectl -n platform exec platform-postgres-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U postgres' \
  > "$backup_dir/postgres-dumpall.sql"
```

也可以分别备份数据库：

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

原始 PVC 备份依赖 storage class 和节点路径。当前 local-path PVC 绑定在单机本地盘上，直接拷贝前必须停 Postgres，避免文件不一致。

推荐顺序：

```bash
kubectl -n platform scale deployment --all --replicas=0
kubectl -n platform scale statefulset platform-postgres --replicas=0
```

找到 PV 和本机路径：

```bash
pvc=data-platform-postgres-0
pv=$(kubectl -n platform get pvc "$pvc" -o jsonpath='{.spec.volumeName}')
kubectl get pv "$pv" -o yaml
```

`local-path` 的真实路径在 PV yaml 的 `spec.local.path` 或 provisioner 生成路径里。确认路径后再在节点上打包。

恢复前也必须停 Postgres。原始 PVC 备份风险更高，优先用 Postgres 逻辑备份。

## 恢复数据

### 恢复 Secret/ConfigMap/PVC 元数据

如果有 `kept-resources.yaml`：

```bash
kubectl apply -f /root/edream-backups/<backup>/kept-resources.yaml
```

然后安装：

```bash
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

### 从 Postgres 逻辑备份恢复

先确保 Postgres Pod Running：

```bash
kubectl -n platform get pod platform-postgres-0
```

拷贝 dump：

```bash
kubectl -n platform cp /root/edream-backups/<backup>/postgres-dumpall.sql \
  platform-postgres-0:/tmp/postgres-dumpall.sql
```

恢复：

```bash
kubectl -n platform exec platform-postgres-0 -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -f /tmp/postgres-dumpall.sql'
```

恢复后重启业务服务：

```bash
kubectl -n platform rollout restart deployment/relay-new-api
kubectl -n platform rollout restart deployment/relay-broker
kubectl -n platform rollout restart deployment/casdoor
kubectl -n platform rollout restart deployment/edreamcrowd-backend
kubectl -n platform rollout restart deployment/edreamcrowd-frontend
kubectl -n platform rollout restart deployment/platform-gateway
```

### 从原始 PVC 恢复

原始 PVC 恢复必须停服务：

```bash
kubectl -n platform scale deployment --all --replicas=0
kubectl -n platform scale statefulset platform-postgres --replicas=0
```

然后在节点上把备份内容恢复到 PV 对应路径。恢复完成后：

```bash
kubectl -n platform scale statefulset platform-postgres --replicas=1
kubectl -n platform rollout status statefulset/platform-postgres --timeout=600s
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

原始 PVC 恢复强依赖当前集群和 storage class，不建议作为首选恢复方式。

## 单独替换某个镜像

标准方式是改 values，再 Helm upgrade。

例如替换 new-api：

1. 构建镜像：

```bash
scripts/images/build-new-api.sh
```

2. 修改目标环境 values：

```yaml
new-api:
  image:
    repository: 81.71.122.120/platform/relay-new-api
    tag: main-20260717213114
```

3. 升级：

```bash
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

紧急临时方式可以直接改 Deployment：

```bash
kubectl -n platform set image deployment/relay-new-api \
  new-api=81.71.122.120/platform/relay-new-api:<tag>

kubectl -n platform rollout status deployment/relay-new-api --timeout=600s
```

但这种方式不会回写 values。临时修复验证通过后，必须把同一个镜像 tag 写回 `environments/<env>/edream-deployment.yaml`，否则下次 Helm upgrade 会覆盖。

常见 deployment/container 名称：

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

如果不确定 container 名称：

```bash
kubectl -n platform get deploy relay-new-api \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n"}{end}'
```

## 离线部署

在线部署通常只传平台小包，镜像从 Harbor 拉。

离线部署需要先加载镜像大包：

```bash
scripts/platform/load-images.sh /root/edream-packages/edream-platform-images-current.tar
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

升级同理：

```bash
scripts/platform/load-images.sh /root/edream-packages/edream-platform-images-current.tar
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## 构建机清理

81 磁盘较小，完整打包几次后容易空间不足。

先 dry-run：

```bash
scripts/maintenance/cleanup-build-host.sh
```

确认后执行：

```bash
CLEANUP_CONFIRM=1 scripts/maintenance/cleanup-build-host.sh
```

可手动清理 Docker 可再生缓存：

```bash
docker builder prune -af
docker image prune -af
```

不要默认清理 Docker volumes。volumes 可能包含服务或 Harbor 数据。

## 验证

仓库结构校验：

```bash
scripts/verify-standard-deployment.sh
```

渲染目标环境：

```bash
scripts/platform/render.sh -f environments/139/edream-deployment.yaml >/tmp/edream-render.yaml
```

查看状态：

```bash
scripts/platform/status.sh -f environments/139/edream-deployment.yaml
```

常用 smoke：

```bash
kubectl -n platform get pods
kubectl -n platform get pvc

curl -sS http://127.0.0.1:30080/readyz
curl -sS http://127.0.0.1:30080/healthz
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30081
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30082
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30084
```

Casdoor OAuth 检查：

```bash
curl -sS 'http://127.0.0.1:30082/api/get-app-login?clientId=<client-id>&responseType=code&redirectUri=<urlencoded-redirect>&type=code&scope=read&state=test'
```

返回中应包含：

```json
{"status":"ok"}
```

## 新手操作顺序

### 完整上线

1. 确认各代码仓分支正确。
2. 本机执行远端完整打包。
3. 把平台小包传到目标服务器。
4. 解压平台小包并切换 `current`。
5. 跑 preflight。
6. 跑 upgrade。
7. 检查 Pod/PVC/smoke。

命令示例：

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/build/remote-package-all.sh

cd /root/edream-deploy/current
scripts/platform/preflight.sh -f environments/139/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
scripts/platform/status.sh -f environments/139/edream-deployment.yaml
```

### 保留数据卸载重装

```bash
cd /root/edream-deploy/current
scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
```

确认 PVC 没变：

```bash
kubectl -n platform get pvc data-platform-postgres-0 -o wide
```

### 只换一个服务

```bash
scripts/images/build-new-api.sh
vi environments/139/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## 注意事项

- 不要在脚本里写死 134/139 这种环境 IP。环境差异放在 `environments/<env>/edream-deployment.yaml`。
- 不要提交 `config/build.env`。
- 不要提交构建产物、临时包、解压目录。
- 不要绕过 preflight。
- 不要把临时 `kubectl set image` 当成最终发布。
- 不要随手执行 `DELETE_DATA=1`。
- 生产环境恢复前，优先做 Postgres 逻辑备份。

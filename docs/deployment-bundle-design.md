# 一体化部署包设计

## 目标

部署仓交付两类能力，这两类能力是两个独立步骤：

1. 一键构建：按构建配置拉取指定分支代码，构建各服务镜像，保存为 tar，并打出完整 bundle。
2. 一键部署：把 bundle 拷贝到新机器，修改 `values/values.yaml`，执行部署脚本。

最终效果：

```text
本机/CI 一键构建 bundle
  -> 拷贝 platform-bundle-*.tar.gz 到新服务器
  -> 编辑 values/values.yaml
  -> 加载 images/*.tar
  -> 一键 helm upgrade --install
```

## 部署包结构

```text
platform-bundle-<env>-<timestamp>/
  charts/
    platform/
    broker/
    casdoor/
    edreamcrowd/
    gateway/
    new-api/
    postgres/
  values/
    values.yaml
  images/
    *.tar
    images.txt
  scripts/
    load-platform-images.sh
    install-platform-bundle.sh
    deploy-platform-bundle.sh
  README.md
```

## 配置边界

`values/values.yaml` 是新机器部署时唯一需要编辑的部署配置文件，承载：

- 服务器 IP 与域名。
- gateway 路由。
- 各服务 image repository/tag/pullPolicy。
- Service、端口、存储类、资源规格。
- 服务环境变量。
- Secret 初始值或私有占位值。
- Broker 的 `NEWAPI_PUBLIC_BASE_URL`，即桌面端官方供应商实际访问的
  new-api 公网地址；`NEWAPI_BASE_URL` 仍然只用于集群内管理调用。

各 chart 的 `templates/deployment.yaml`、`templates/statefulset.yaml`、
`templates/service.yaml`、`templates/configmap.yaml`、`templates/secret.yaml`
只表达部署结构，不承载环境差异。

`values/values.yaml` 不承载源码仓库、分支、Docker build args 等构建期配置，避免把构建阶段和部署阶段混在一起。

## 一键构建

镜像构建配置来自 `build/images.env`：

- `BROKER_REPO_URL` / `BROKER_REPO_REF` 控制 Broker 代码来源。
- `EDREAMCROWD_REPO_URL` / `EDREAMCROWD_REPO_REF` 控制众筹代码来源。
- `*_IMAGE_REPOSITORY` 和 `*_IMAGE_TAG` 控制镜像名称。
- `UPSTREAM_IMAGES` 控制 Casdoor、new-api、Postgres、Nginx 等第三方镜像。

构建镜像：

```bash
scripts/build-platform-images.sh build/images.env
```

一键构建完整部署包：

```bash
scripts/build-platform-bundle.sh
```

## 一键部署

```bash
tar -xzf platform-bundle-*.tar.gz
cd platform-bundle-*
vim values/values.yaml
LOAD_IMAGES=true scripts/deploy-platform-bundle.sh
```

后续升级只需要改 `values/values.yaml` 的镜像 tag，再执行：

```bash
scripts/deploy-platform-bundle.sh
```

从已有散装环境迁移时，可以先用辅助脚本把旧 secret env 和现有
Kubernetes Secret 合并成一个完整 values 文件，再打包或部署：

```bash
scripts/materialize-platform-values.py \
  --input environments/staging/platform.values.yaml \
  --output environments/staging/values.bundle-139.yaml \
  --secret-env /root/platform-secrets/staging.env \
  --namespace platform
```

## 与 139 环境的关系

139 现有脚本继续保留，作为兼容入口。新的 bundle 流程不依赖 139 硬编码，目标是支撑任意新服务器复刻 139 这种一体化 K8s/Helm 部署形态。

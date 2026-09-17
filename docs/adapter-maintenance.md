# Adapter 开发与升级

目标：其他开发者按两个代码仓完成源码修改、测试、标准构建、Helm 预检、发布及回滚，不依赖手工替换线上文件。

## 当前基线

截至 2026-09-17：

| 项目 | 当前值 |
| --- | --- |
| Adapter 源码 | ai-relay-broker/main，7a9a137 |
| 运维配置 | ai-relay-ops，environments/134/edream-deployment.yaml |
| 构建机 | ubuntu@81.71.122.120 |
| 运行机 | ubuntu@134.175.68.24 |
| namespace / release | platform / platform-relay |
| Deployment / container | ai-provider-adapter / ai-provider-adapter |
| 线上镜像 tag | wan3-content-7a9a137-20260917095000 |
| 线上镜像 digest | sha256:d88a698f10b172bdd764543a004e315bc8bd32a2a9d577e8e3888259a35dbdab |
| Service | ai-provider-adapter:80，容器端口 8080 |
| 现有 Secret | ai-provider-adapter-secret，secret.create=false |
| Helm 已保存状态 | revision 12，deployed；镜像及配置与运行状态一致 |
| New API 限流 | CRITICAL_RATE_LIMIT_ENABLE=true，2000 次 / 1200 秒 |

2026-09-17 已完成首次 Helm 基线同步及限流发布。Adapter 保留已经验证的修复镜像；New API 保留原镜像，只有三个限流环境变量变更。主业务 edream.service 未重启，其余 8 个长期运行 Pod 的 UID、镜像和重启次数不变。后续从 Ops 最新 main 制包，不能继续使用旧发布包。

本次线上版本是在此前正常镜像上只替换 Lingzhi 下载文件的紧急镜像；后续日常开发应走本仓库的标准 Dockerfile，不要永久依赖本次手工 overlay 构建。

## 源码和配置分别改什么

- ai-relay-broker/provider_adapter/providers：上游创建、上传、查询、下载和协议转换。修改 Wan3 时保留直接返回视频和受信 HTTPS 跳转两条下载路径。
- ai-relay-broker/provider_adapter/providers/factory.py、settings.py：注册供应商与读取环境变量；新变量应保持默认值兼容。
- ai-relay-broker/tests/provider_adapter：供应商测试及 Adapter API 合约测试。
- ai-relay-ops/environments/<env>/edream-deployment.yaml：实际镜像及完整模型映射、URL、超时、Secret 名称和资源配置。
- ai-relay-ops/docker/ai-relay-broker/ai-provider-adapter.Dockerfile：标准镜像入口及依赖构建；非必要不调整。
- 密钥只放目标集群 Secret，不能加入 values、测试日志或 Git。LINGZHI_API_KEY 允许保留空值，由原渠道 Authorization 传入，但 Secret 中必须有该 key。

模型同名不决定是否走 Adapter，New API 渠道的地址和类型决定路由。需要另一套转换逻辑时新增 provider 名称，保留任务 ID 中的 provider 前缀，以便旧任务继续查询和下载。

## 日常开发与标准构建

1. 拉取已合并的源码和 Ops 版本，不覆盖构建机的 config/build.env；部署期间不要并发修改同一环境。
2. 修改供应商源码，先在 ai-relay-broker 执行 pytest 和 Ruff，提交源码，记录 commit。
3. 在本机 ai-relay-ops 上传已提交源码：

```bash
BUILD_ENV_FILE=config/build-81.env \
UPLOAD_TARGETS="ops broker" \
scripts/sources/upload-local.sh
```

4. 在构建机执行标准 Adapter 构建，不构建其他镜像：

```bash
ssh ubuntu@81.71.122.120
cd /data/edream-build/sources/ai-relay-ops
BUILD_ENV_FILE=config/build-81.env \
DEPLOYMENT_VALUES_FILE=/data/edream-build/sources/ai-relay-ops/environments/134/edream-deployment.yaml \
scripts/images/build-ai-provider-adapter.sh
```

脚本使用标准多阶段 Dockerfile，推送 Harbor，自动把构建机上的指定 values 更新到新 tag。构建输出不能代替 Git 提交：核对 values 的改动只涉及本次 Adapter，带回 Ops 源码仓提交并推送。记录源码 commit、最终 tag 和 digest；建议把 tag 写为 `<tag>@sha256:<digest>` 固定不可变版本。可用 `docker buildx imagetools inspect <构建输出的镜像>` 查看 digest。

5. 测试完整构建出来的镜像，包括默认应用启动和 multipart 图片上传，不能只测 mock 供应商或 /healthz。确认没有漏掉 runtime 依赖。
6. 按 README 的标准 package 流程制作并传输平台小包，或在目标机使用对应已提交的 Ops checkout；不要把构建机的私有配置和缓存同步到目标运行目录。

本次修复源码的既有验证为 188 项测试通过；后续以当前仓库实际测试数量及结果为准。

## Adapter 专用发布入口

在目标运行机的 Ops 工作目录执行，需 helm、kubectl、Python 3、PyYAML 和可读 KUBECONFIG。需要 root 权限时按现有部署约定使用 sudo。

```bash
# 默认只预检，不修改任何工作负载
scripts/platform/upgrade-adapter.sh -f environments/134/edream-deployment.yaml

# 预检通过且审查结果确认后发布
scripts/platform/upgrade-adapter.sh -f environments/134/edream-deployment.yaml --apply
```

默认把候选 values、Helm 原状态、实际资源、外部 Secret 和 Pod 快照保存到 `$HOME/edream-backups` 的 700 权限目录，文件为 600 权限。不要将该目录上传 Git、共享文档或普通构建产物。

该入口仍升级已有 **platform-relay 整个 release**，不是新建独立 Adapter release。它先比对所有非 Adapter 资源和集群当前状态，发现镜像、环境变量、列表顺序、Service、配置或资源增删差异就停止；新增 hook 也会停止。不会通过关闭其他组件 enabled 来“单组件发布”，那会导致 Helm 删除原资源。

阻止信息只显示资源名和字段路径，不显示配置值或 Secret。其他组件有漂移时，应先审查并完成平台基线同步，不能删掉校验或改用旧包绕过。预检并不能阻止其他操作者同时部署，必须避免并发发布。

## 本次同步与启动兼容性

- revision 9：先将当前 Adapter 修复镜像、完整 Wan3 映射、外部 Secret 和超时纳入已有 platform-relay；其他组件不变。
- revision 10：经审查加入三个 New API 限流参数，新实例启动迁移被运维只读视图的列依赖阻挡。旧健康实例持续提供服务。
- revision 11：回退到已经验收的 revision 9，保留 Adapter 修复；没有回退到旧 revision 8。
- revision 12：原子修复运维视图后，重新发布相同限流参数。New API Ready、重启次数为 0；实际进程环境变量及 Helm 保存值均已核验。

视图属于 `ops-agent` 的部署辅助文件，不是视频生成代码。原视图直接引用业务表字段，导致 GORM 即使把 `channels.status_code_mapping` 迁移到相同的 varchar(1024) 也被 PostgreSQL 拒绝；这会影响任何后续 New API 重启，与限流数值无关。

修复位于 `ops-agent/deploy/host/newapi-readonly-views.sql`：用整行 JSON 读取原白名单字段并显式保留原类型，解除列依赖。四个视图在同一事务内更新；现场验证 39 个字段类型、结果、view ID、owner 和 ACL 不变，两个 reader 仍可查询且没有表写权限。保留 ops_agent_reader 原有 channels 只读权限，不扩权也不撤权。该修复不修改业务表或业务数据，不需要重部署 Ops Agent、主业务或其他容器，也不能重跑会改密码和 Secret 的 install-readers.py。维护及隔离数据库测试见该仓库 `deploy/host/newapi-readonly-views.md`。

首次预检还发现 Broker 已有 `NEWAPI_CATALOG_REFRESH_ENABLED=true` 未写入 Git，以及本地 CRLF 导致 Secret checksum 不一致。已保留原刷新参数和 Secret 引用顺序，并通过 .gitattributes 固定部署文件 LF；没有通过修改现有 Secret 或重启 Broker 绕过校验。

Ops 源码仓自动检查：`python3 -m unittest discover -s tests -p 'test_adapter_upgrade*.py' -v`，并执行 `scripts/verify-standard-deployment.sh`。本次 17 项发布保护测试及 3 项隔离 PostgreSQL 视图测试通过。测试目录不随运行发布包分发。

## 最小验收

| 验证 | 必须确认 |
| --- | --- |
| Kubernetes | Adapter Ready；其他 Pod 的 UID、镜像和重启次数未变化 |
| 路由与鉴权 | New API 原渠道能访问 Adapter；密钥不出现在页面或跨域媒体请求中 |
| 提交与上传 | multipart 多参考图能解析；正常提交返回带 provider 前缀任务号 |
| 查询 | 明确终态正常；临时 408/429/5xx 不误判生成失败，查询不会无界占连接 |
| 下载 | 上游直接 200 视频和媒体跳转都支持；空文件、HTML/JSON 不伪装成成功 |
| 主业务 | 既有成功任务能下载完整 MP4，进入 COS 后签名播放正常 |
| 其他供应商 | 抽查 Seedance、Veo、Grok 的现有路由和查询，不强制新建付费任务 |
| Helm/Git | 保存的镜像及配置等于验收版本；源码、Ops 提交和 Helm revision 可追溯 |

可以复用既有已完成任务验证查询和下载，不再次生成、不重复扣费。若测试新生成任务，应另行确认企业账号、预算和数量，不自动批量重试。

revision 12 发布后，主业务原 AIClient 经 New API 查询并下载了 3 个既有任务，均为有效完整 MP4，字节数和 SHA256 与发布前一致。本次未新建付费任务，未写 COS 或修改授权/计费记录；上游直接返回视频和受信媒体跳转的兼容验证已在同一 Adapter 镜像上通过。这不等于重新执行了所有供应商的付费生成流程。

历史记录修复属于独立数据维护，不是 Helm 发布步骤。已回填的 8 条记录、原任务和已返还次数不会因升级自动改变。

## 回滚

发布前保留旧镜像 digest，确认 Harbor 仍可拉取，必要时按标准备份流程导出镜像。专用入口的快照用于核对和恢复，不等于数据库或镜像本体备份。

- 如果本次仅改镜像，可临时 kubectl set image 恢复发布前的精确镜像，再同步 Ops 与 Helm 状态。
- 如果同时改了 Adapter 环境配置，必须依据受限快照恢复完整 Adapter Deployment；不能只回退镜像。保持原 Service 和 Secret，不修改其他组件。
- 只有在之前的 Helm revision 与当时线上正常状态一致、且整个 release 的回滚影响已经审查时，才使用 helm rollback。
- 数据库、COS 视频、授权和计费流水不在镜像回滚中操作。

本次紧急修复前的生产备份位于 `/home/ubuntu/edream-backups/20260917-0945-before-wan3-content-fix`；其中 rollback.sh 会回退到下载修复之前的版本，虽然保留旧查询修复，但会重新触发本次 302 空内容问题，不应作为下一次正常升级的“成功基线”。下一次发布应先备份当前已修复版本。

本次受限备份（目录 700、文件 600）：

- `/home/ubuntu/edream-backups/20260917-2218-before-helm-adoption`：已经修复的 Adapter 镜像本体、校验和、全平台快照及首次同步验收。
- `/home/ubuntu/edream-backups/20260917-2222-before-rate-limit`：revision 9、原视图定义/字段/owner/ACL 及原子修复 SQL。
- `/home/ubuntu/edream-backups/20260917-2235-before-rate-limit-retry`：revision 11、限流发布前快照及 revision 12 的最终验收快照。

正常后续升级以 revision 12 的当前健康状态为基线，发布前再备份。不要回滚 revision 8；不要恢复存在列依赖的旧运维视图。仅回退限流时，revision 11 的平台配置已包含 Adapter 修复，但仍须审查整个 release 的回滚影响。

# eDream Ops

This repository owns the standard image build and Helm deployment flow for the
eDream relay platform.

## Standard Flow

The deployment source of truth is the environment deployment file:

```text
environments/134/edream-deployment.yaml
environments/139/edream-deployment.yaml
```

To replace an image manually, edit the image repository and tag in the target
environment file, then run the platform upgrade command.

```bash
scripts/platform/upgrade.sh 139
```

## Image Builds

Base images are a separate pipeline stage. They are stored in Harbor and split
into generic language/system bases and project-specific bases with dependencies
preinstalled. Runtime image builds only pull these images from Harbor. They do
not create base images or download dependencies.

```bash
scripts/images/sync-base-images.sh 139
scripts/images/build-project-base-images.sh 139
```

Every base image also has its own build entrypoint:

```text
scripts/images/base/build-*.sh
scripts/images/project-base/build-*.sh
```

Each runtime image has one build entrypoint:

```bash
scripts/images/build-new-api.sh 139
scripts/images/build-broker.sh 139
scripts/images/build-ai-provider-adapter.sh 139
scripts/images/build-newapi-compat-gateway.sh 139
scripts/images/build-edreamcrowd-backend.sh 139
scripts/images/build-edreamcrowd-frontend.sh 139
scripts/images/build-casdoor.sh 139
scripts/images/build-gateway.sh 139
scripts/images/build-all.sh 139
```

`sync-base-images.sh`, `build-project-base-images.sh`, and `build-all.sh` are
composition scripts. They do not contain per-image Docker build logic; they call
the single-image scripts above. `build-all.sh` only builds runnable service
images; it does not build generic or project-base images.

Only `scripts/images/base/build-*.sh` may mirror upstream generic images into
Harbor. Project-base image scripts pull generic bases from Harbor only. Runtime
image scripts require both generic and project-base Harbor images to already
exist. If a base image is missing, the build fails instead of building it
implicitly.

Images default to `linux/amd64`, matching the current 134/139 servers. Override
with `IMAGE_PLATFORM` only when deploying to a different node architecture.
When building from an exported source tree without `.git`, set
`IMAGE_REF_LABEL=<branch-or-commit>` so the pushed image tag remains traceable.

Harbor projects:

```text
base-images           generic language/system bases, for example python/node/go/nginx/postgres
project-base-images   project-specific builder/runtime bases with dependencies preinstalled
platform              runnable service images
```

Project base images use the fixed `harbor.projectBaseTag` from
`environments/<env>/harbor.yaml`. They do not include application source code.
Application images may compile local source code, but they must not download
dependencies or install system packages during runtime-image builds.

Harbor location and project names are configured only in:

```text
environments/<env>/harbor.yaml
```

Switching Harbor must not require editing Dockerfiles or per-image build
scripts.

After a runtime image is pushed, the script updates:

```text
environments/<env>/edream-deployment.yaml
```

## Platform Commands

Install, upgrade, and uninstall are separate operations:

```bash
scripts/platform/install.sh 139
scripts/platform/upgrade.sh 139
scripts/platform/uninstall.sh 139
```

`upgrade.sh` uses `helm upgrade`, not `helm upgrade --install`.
`install.sh` uses `helm install`.
`uninstall.sh` keeps Secret, ConfigMap, and PVC data by default. To delete data,
set `DELETE_DATA=1` and confirm with `CONFIRM_DELETE_DATA=delete-<env>`.

## Packaging

Create a deployable package:

```bash
scripts/platform/package.sh 139
```

The default package name is environment-neutral, for example
`edream-platform-20260716152118.tar.gz`. The package contains charts, the
selected environment deployment file, image build scripts, platform scripts,
Harbor scripts, and Dockerfile wrappers.

## Validation

Run:

```bash
scripts/verify-standard-deployment.sh
scripts/platform/render.sh 139
scripts/harbor/check.sh 139
```

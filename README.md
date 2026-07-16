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

Build scripts pull base images from Harbor first. If Harbor does not have the
base image, the script pulls the public image, pushes it back to Harbor, and
then builds the runtime image from the Harbor image.

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

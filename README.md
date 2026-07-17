# eDream Ops

This repository owns the standard image build, package, and Helm deployment
flow for the eDream relay platform.

## Build Configuration

Image builds are environment-neutral. They do not take `134` or `139` as input.
Build scripts source one local configuration file:

```bash
cp config/build.env.example config/build.env
vi config/build.env
```

`config/build.env` contains Harbor location, Harbor project names, source
directories, image tag labels, and local build cache directories for the build
host.

On the 81 build host, source code refs are configured in the same file:

```bash
BROKER_LOCAL_DIR=/data/edream-build/sources/ai-relay-broker
BROKER_GIT_REF=main
NEW_API_LOCAL_DIR=/data/edream-build/sources/new-api
NEW_API_GIT_REF=main
CASDOOR_LOCAL_DIR=/data/edream-build/sources/casdoor
CASDOOR_GIT_REF=main
EDREAMCROWD_LOCAL_DIR=/data/edream-build/sources/EDreamCrowd
EDREAMCROWD_GIT_REF=main
```

If a source directory is missing, set the matching `*_GIT_URL` so the sync
script can clone it. Existing repositories are fetched from `origin` and checked
out to the configured ref:

```bash
scripts/sources/sync.sh
```

For the 81 build host, the standard path is local source upload because direct
GitHub access from 81 can be unstable. Configure the remote build target and run:

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

`upload-local.sh` archives each local repository, uploads it to the configured
remote `*_LOCAL_DIR`, and keeps the previous remote source under
`/data/edream-build/source-snapshots`. Casdoor upload is skipped by default
unless `SYNC_CASDOOR=1` or `BUILD_CASDOOR=1`.

Dirty local sources are rejected by default so temporary build files and
unexpected local edits are not pushed to the build host. For an intentional
dirty-source test build, use:

```bash
ALLOW_DIRTY_UPLOAD=1 REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

## Image Builds

Harbor stores only generic base images and final runnable service images:

```text
base-images   generic language/system bases, for example python/node/go/nginx/postgres
platform      runnable service images
```

There is no project-base image layer. Build dependencies stay on the 81 build
host as Docker/language build cache and intermediate build layers. Final images
only contain runtime files required to start each service.

Sync generic base images when the build host or Harbor is initialized:

```bash
scripts/images/sync-base-images.sh
```

Build one service image:

```bash
scripts/images/build-new-api.sh
scripts/images/build-broker.sh
scripts/images/build-ai-provider-adapter.sh
scripts/images/build-newapi-compat-gateway.sh
scripts/images/build-edreamcrowd-backend.sh
scripts/images/build-edreamcrowd-frontend.sh
scripts/images/build-casdoor.sh
scripts/images/ensure-casdoor.sh
scripts/images/build-gateway.sh
```

Build all service images:

```bash
scripts/images/build-all.sh
```

Build a complete release on the build host:

```bash
scripts/build/package-all.sh
```

This runs image preflight, all image builds, and platform package creation on
the build host. It produces a small Helm deployment package and a separate image
archive package with the same values/image set. Each script and package-all
substep prints a `[timing]` line. By default `package-all.sh` expects source
directories to have been prepared by `upload-local.sh`; set `SKIP_SOURCE_SYNC=0`
only when the build host should fetch directly from Git.

From a local machine, run the full remote flow with:

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/build/remote-package-all.sh
```

This uploads local sources first, then runs `package-all.sh` on the build host.

`build-all.sh` uses `ensure-casdoor.sh`. Casdoor is reused from Harbor by
default because it is a third-party fixed component. It is rebuilt only when the
configured image is missing or when explicitly requested:

```bash
BUILD_CASDOOR=1 scripts/images/build-all.sh
```

Set `CASDOOR_IMAGE` to pin a known-good Casdoor image. If omitted,
`ensure-casdoor.sh` reads the current Casdoor image from `DEPLOYMENT_VALUES_FILE`.

If `DEPLOYMENT_VALUES_FILE` is set in `config/build.env`, image scripts update
that values file after pushing a new image. Otherwise they only print the built
image reference.

## Deployment Values

Deployment source of truth is the top-level values file:

```text
environments/134/edream-deployment.yaml
environments/139/edream-deployment.yaml
```

To replace an image manually, edit the image repository and tag in the target
values file, then run upgrade on the target server.

## Platform Commands

Install, upgrade, render, status, and uninstall are explicit values-file
operations:

```bash
scripts/platform/install.sh -f environments/139/edream-deployment.yaml
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
scripts/platform/render.sh -f environments/139/edream-deployment.yaml
scripts/platform/status.sh -f environments/139/edream-deployment.yaml
scripts/platform/uninstall.sh -f environments/139/edream-deployment.yaml
```

`upgrade.sh` uses `helm upgrade`, not `helm upgrade --install`.
`install.sh` uses `helm install`.
Rollout waiting uses `ROLLOUT_TIMEOUT=600s` by default and can be overridden for
slow image pulls:

```bash
ROLLOUT_TIMEOUT=900s scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

`uninstall.sh` keeps Secret, ConfigMap, and PVC data by default. To delete data,
set `DELETE_DATA=1` and confirm with `CONFIRM_DELETE_DATA=delete-<env>`.

## Build Host Maintenance

Run the build preflight before long builds:

```bash
scripts/images/preflight.sh
```

Clean the build host with a dry-run first:

```bash
scripts/maintenance/cleanup-build-host.sh
CLEANUP_CONFIRM=1 scripts/maintenance/cleanup-build-host.sh
```

The cleanup keeps recent packages and Docker cache by default. It does not
delete source repositories, volumes, or Harbor base images.

## Packaging

Create an environment-neutral deployable package:

```bash
scripts/platform/package.sh
```

The package contains charts, all environment values files, image build scripts,
platform scripts, Harbor scripts, Dockerfile wrappers, and the build config
example. It does not contain container images. Deployment is completed on the
target server by replacing the desired top-level values file and running the
platform command with `-f`.

Create the matching image archive package when offline deployment or external
delivery needs it:

```bash
scripts/platform/package-images.sh
```

Online deployments normally pull images from Harbor. Offline deployments should
load the image archive explicitly before install or upgrade:

```bash
scripts/platform/load-images.sh edream-platform-images-current.tar
scripts/platform/upgrade.sh -f environments/139/edream-deployment.yaml
```

## Validation

Run:

```bash
scripts/verify-standard-deployment.sh
scripts/platform/render.sh -f environments/139/edream-deployment.yaml
scripts/harbor/check.sh
```

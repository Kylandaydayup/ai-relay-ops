# Harbor Image Supply Chain

This document describes the Harbor based image flow for the platform.

## Roles

- `81.71.122.120`: build host and Harbor host.
- `139.196.254.8`: staging k3s runtime.
- `134.175.68.24`: production k3s runtime.

Build scripts are independent of 134/139. Runtime deployment happens on the
target server using a top-level Helm values file.

## Harbor Projects

Harbor stores two classes of images:

```text
base-images   generic language/system bases
platform      final runnable service images
```

It must not store project-specific builder images. Build tools, dependency
caches, and intermediate layers remain on the 81 build host.

## Build Configuration

Build and Harbor parameters live in one file:

```text
config/build.env
```

Copy the example and edit it on the build host:

```bash
cp config/build.env.example config/build.env
```

The file contains Harbor registry/project names, source directories, image tag
label, dependency proxy/mirror settings, and local cache directories.

## First Time Harbor Setup

Download or copy the Harbor offline installer to:

```text
/opt/harbor/harbor-offline-installer-v2.12.2.tgz
```

Then run:

```bash
scripts/harbor/bootstrap.sh
scripts/harbor/check.sh
```

## Insecure Registry Setup

On the build host:

```bash
bash scripts/harbor/configure-docker-registry.sh 81.71.122.120
sudo systemctl restart docker
```

On each k3s node:

```bash
bash scripts/harbor/configure-k3s-registry.sh 81.71.122.120
sudo systemctl restart k3s
```

Restarting k3s briefly impacts the node, so do this during a controlled
maintenance window.

## Base Image Sync

After logging in to Harbor:

```bash
scripts/images/sync-base-images.sh
```

`BASE_IMAGE_TARGETS` can limit the generic base image targets.

## Build And Push

Each service has a dedicated build script. To build all runtime images:

```bash
scripts/images/build-all.sh
```

The build scripts pull generic base images from Harbor. They may use Docker
intermediate layers and BuildKit cache mounts on the build host, but only push
final runnable images to Harbor. BuildKit local cache export can be enabled with
`USE_BUILDX_LOCAL_CACHE=1`; it is disabled by default because large image cache
exports can be slower than Docker's internal builder cache on the 81 host. If
`DEPLOYMENT_VALUES_FILE` is configured, the scripts also write the new image
reference into that top-level values file.

## Current Network Constraint

Direct Docker Hub and GitHub release downloads from 81 can be slow or timeout.
Keep generic base images mirrored in Harbor and keep build caches on the 81
build host. Runtime nodes should only pull final service images and generic
runtime images from Harbor.

## Source And Artifact Locations

81 is the build host. Source directories are defined in `config/build.env`.
Because direct GitHub access from 81 can be unstable, the preferred source
supply path is local upload:

```bash
REMOTE_BUILD_HOST=81.71.122.120 scripts/sources/upload-local.sh
```

The upload script sends local Git working trees to the configured remote source
directories and snapshots the previous remote source before replacement.

Optional Git remotes and refs can still be configured and synchronized directly
on 81 with:

```bash
scripts/sources/sync.sh
```

The sync step updates local repositories from `origin` and checks out the
configured ref, for example `NEW_API_GIT_REF=main`. Image build scripts consume
only these local source directories and do not decide branches themselves.

Build packages are written under `dist/` in the ops workspace. When
`BUILD_PACKAGE_DIR` is configured, `scripts/platform/package.sh` also copies the
timestamped package and `edream-platform-current.tar.gz` there, for example:

```text
/data/edream-build/packages/edream-platform-20260717132946.tar.gz
/data/edream-build/packages/edream-platform-current.tar.gz
```

Casdoor is treated as a fixed third-party component by default. `build-all.sh`
reuses the configured Harbor image through `ensure-casdoor.sh`; set
`BUILD_CASDOOR=1` only when upgrading or changing Casdoor itself.

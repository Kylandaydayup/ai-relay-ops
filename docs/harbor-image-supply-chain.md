# Harbor Image Supply Chain

This document describes the HTTP Harbor based image flow for the platform.

## Roles

- `81.71.122.120`: build host and Harbor host.
- `139.196.254.8`: staging k3s runtime.
- `134.175.68.24`: production k3s runtime.

Do not install a duplicate 139/134 k3s cluster on the build host. Install
`kubectl` and `helm` on the build host only as clients if remote deployment is
needed from 81.

## Harbor Endpoint

The current environment uses HTTP:

```text
81.71.122.120
```

Every Docker or k3s node pulling from this endpoint must trust it as an
insecure registry.

## Image Naming

Final application images are named with the stable workload/container name,
the source branch, and a timestamp precise to seconds:

```text
<registry>/<project>/<name>:<branch>-<yyyyMMddHHmmss>
```

Examples:

```text
81.71.122.120/platform/relay-new-api:main-20260712230501
81.71.122.120/platform/relay-broker:main-20260712230501
81.71.122.120/platform/ai-provider-adapter:main-20260712230501
```

Use the pod/container base name, not ReplicaSet or Pod suffixes.

## First Time Setup

1. Copy `build/harbor.env.example` to `build/harbor.env`.
2. Set `HARBOR_ADMIN_PASSWORD`.
3. Download or copy the Harbor offline installer to the build host:

```text
/opt/harbor/harbor-offline-installer-v2.12.2.tgz
```

4. Run:

```bash
bash scripts/harbor/bootstrap.sh build/harbor.env
```

If external downloads are slow, copy the offline installer through an internal
object store or another fast channel first. The online installer needs Docker
Hub access and is not reliable in this environment.

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
scripts/images/sync-base-images.sh 139
```

The base image list can be overridden with `BASE_IMAGES`.

## Build And Push

Each runtime image has a dedicated build script. To build all runtime images:

```bash
scripts/images/build-all.sh 139
```

Each build script resolves base images through Harbor first, falls back to the
public source only when Harbor misses the image, pushes the mirrored base image
back to Harbor, and then updates `environments/<env>/edream-deployment.yaml`
with the new runtime image.

## Helm Pull Secrets

Charts support:

```yaml
global:
  imagePullSecrets:
    - name: harbor-regcred
```

Create the secret in each runtime namespace when Harbor projects are private:

```bash
kubectl -n platform create secret docker-registry harbor-regcred \
  --docker-server=81.71.122.120 \
  --docker-username='<robot-user>' \
  --docker-password='<robot-token>'
```

## Current Network Constraint

Direct Docker Hub and GitHub release downloads from 81 can be slow or timeout.
Prefer the Harbor offline installer and registry cache. Do not rely on each
runtime node pulling build dependencies from the public internet.

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

Initial rollout uses HTTP:

```text
81.71.122.120:8088
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
81.71.122.120:8088/edreamcrowd/new-api:main-20260712230501
81.71.122.120:8088/edreamcrowd/broker:main-20260712230501
81.71.122.120:8088/edreamcrowd/ai-provider-adapter:main-20260712230501
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
bash scripts/bootstrap-harbor-81.sh build/harbor.env
```

If external downloads are slow, copy the offline installer through an internal
object store or another fast channel first. The online installer needs Docker
Hub access and is not reliable in this environment.

## Insecure Registry Setup

On the build host:

```bash
bash scripts/configure-docker-insecure-registry.sh 81.71.122.120:8088
sudo systemctl restart docker
```

On each k3s node:

```bash
bash scripts/configure-k3s-insecure-registry.sh 81.71.122.120:8088
sudo systemctl restart k3s
```

Restarting k3s briefly impacts the node, so do this during a controlled
maintenance window.

## Base Image Sync

After logging in to Harbor:

```bash
bash scripts/sync-base-images-to-harbor.sh build/harbor.env
```

The initial base image list is in `build/platform-images.harbor.env.example`.

## Build And Push

Copy `build/platform-images.harbor.env.example` to
`build/platform-images.harbor.env`, then run:

```bash
bash scripts/build-push-platform-images.sh build/platform-images.harbor.env
```

The script writes an image manifest under `.build/harbor-platform-images/`.

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
  --docker-server=81.71.122.120:8088 \
  --docker-username='<robot-user>' \
  --docker-password='<robot-token>'
```

## Current Network Constraint

Direct Docker Hub and GitHub release downloads from 81 can be slow or timeout.
Prefer the Harbor offline installer and registry cache. Do not rely on each
runtime node pulling build dependencies from the public internet.

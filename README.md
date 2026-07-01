# ai-relay-ops

Deployment and operations repository for the AI relay platform.

## Scope

This repository manages:

- Kubernetes namespaces.
- Helm charts for `new-api`, `ai-relay-broker`, Casdoor, EDreamCrowd, `platform-gateway`, and the shared staging Postgres.
- Environment values for staging and production.
- Secret templates without committing real secrets.
- Version locks, upgrade notes, rollback notes, and smoke tests.
- A Kubernetes-managed Nginx gateway chart for the staging validation host, plus legacy host Nginx templates kept only for transition.

It does not contain business code. Broker business logic lives in `ai-relay-broker`.

## Common Commands

```bash
make template SERVICE=broker ENV=prod
make template SERVICE=platform ENV=staging
make install SERVICE=broker ENV=prod
make upgrade SERVICE=broker ENV=prod IMAGE_TAG=v0.1.1
make rollback SERVICE=broker ENV=prod REVISION=1
make status ENV=prod
make verify-platform-chart
```

## Portable Bundle

The portable flow has two separate steps:

1. Build once: create a deployable bundle with charts and image tar files.
2. Deploy once: copy the bundle to a server, edit `values/values.yaml`, then run one deploy command.

The build step and deploy step are intentionally separate. Runtime environment
settings belong to `values/values.yaml`; source repository and image-build
settings belong to `build/images.env`.

```text
charts/ + values/values.yaml + images/*.tar + install scripts
```

One-click build:

```bash
cp build/images.env.example build/images.env
vim build/images.env
make build-bundle BUNDLE_ENV=template BUILD_ENV_FILE=build/images.env
```

One-click deploy on the target server:

```bash
tar -xzf platform-bundle-*.tar.gz
cd platform-bundle-*
vim values/values.yaml
LOAD_IMAGES=true scripts/deploy-platform-bundle.sh
```

Later upgrades should only require changing image names or tags in
`values/values.yaml` and rerunning `scripts/deploy-platform-bundle.sh`.

## Staging 139

The 139 validation host runs the platform as one integrated Kubernetes-managed stack:

- Casdoor as the identity source.
- EDreamCrowd frontend and backend.
- `new-api` as the model relay console and upstream channel manager.
- `ai-relay-broker` as the product-facing quota and relay layer.
- `platform-gateway` as the Kubernetes-managed Nginx public entrypoint for `/`, `/zhongchou/`, `/casdoor/`, and `/broker/`.
- Host Nginx is a transition fallback only. The deployment script refuses to let the gateway Pod bind host port 80 unless `ALLOW_HOST_GATEWAY_CUTOVER=1` is explicitly set.

System-level deployment parameters, including ports and public paths, live in:

- `environments/staging/*.values.yaml`
- `environments/staging/platform.values.yaml`
- `nginx/staging/platform.values.env`

Service runtime configuration is rendered into each workload's Pod spec from the chart templates. Real secrets stay outside git in Kubernetes Secrets and `/root/platform-secrets`.

```bash
scripts/deploy-staging-139.sh
scripts/configure-casdoor-staging-139.sh
scripts/migrate-newapi-docker-to-k8s-139.sh
```

`scripts/deploy-staging-139.sh` is a compatibility wrapper for the umbrella chart deployment:

```bash
# Safe mode: install/upgrade the platform release while keeping host Nginx and NodePorts.
scripts/deploy-staging-139.sh

# Cutover mode: stop host Nginx and let platform-gateway bind port 80.
GATEWAY_HOST_NETWORK=true ALLOW_HOST_GATEWAY_CUTOVER=1 scripts/deploy-staging-139.sh
```

## Broker Public API

ArcReel Desktop should talk to Broker as an OpenAI-compatible provider:

```text
Base URL = BROKER_PUBLIC_BASE_URL + /v1
API Key = Broker-issued brk_... key
```

Do not expose temporary deployment words such as `k8s` in user-facing API URLs. `BROKER_PUBLIC_BASE_URL` is the canonical public base used by Broker when issuing keys, and it can be configured per environment:

```yaml
env:
  BROKER_PUBLIC_BASE_URL: https://broker.example.com
  NEWAPI_BASE_URL: http://relay-new-api:3000
  BROKER_MODEL_CATALOG_JSON: '{"text":[{"id":"ZHIPU/GLM-5.2","name":"GLM 5.2","capabilities":["text"]}]}'
```

`NEWAPI_BASE_URL` is internal service-to-service routing. Users and ArcReel Desktop should never receive the managed new-api `sk-...` key.

## Production Migration Principle

Production is still the source of truth and must not be changed during staging validation. Use 139 to prove the integrated stack first, including database migration, OAuth callback rewrites, Nginx routing, and smoke checks. Move production only after the same scripts are proven repeatable and a rollback window is agreed.

# ai-relay-ops

Deployment and operations repository for the AI relay platform.

## Scope

This repository manages:

- Kubernetes namespaces.
- Helm charts for `new-api`, `ai-relay-broker`, Casdoor, EDreamCrowd, and the shared staging Postgres.
- Environment values for staging and production.
- Secret templates without committing real secrets.
- Version locks, upgrade notes, rollback notes, and smoke tests.
- Nginx host routing templates for the staging validation host.

It does not contain business code. Broker business logic lives in `ai-relay-broker`.

## Common Commands

```bash
make template SERVICE=broker ENV=prod
make install SERVICE=broker ENV=prod
make upgrade SERVICE=broker ENV=prod IMAGE_TAG=v0.1.1
make rollback SERVICE=broker ENV=prod REVISION=1
make status ENV=prod
```

## Staging 139

The 139 validation host runs the platform as one integrated Kubernetes-managed stack:

- Casdoor as the identity source.
- EDreamCrowd frontend and backend.
- `new-api` as the model relay console and upstream channel manager.
- `ai-relay-broker` as the product-facing quota and relay layer.
- Host Nginx as the public entrypoint for `/`, `/zhongchou/`, `/casdoor/`, and `/broker/`.

System-level deployment parameters, including ports and public paths, live in:

- `environments/staging/*.values.yaml`
- `nginx/staging/platform.values.env`

Service runtime configuration is rendered into each workload's Pod spec from the chart templates. Real secrets stay outside git in Kubernetes Secrets and `/root/platform-secrets`.

```bash
scripts/deploy-staging-139.sh
scripts/apply-nginx-config.sh
scripts/configure-casdoor-staging-139.sh
scripts/migrate-newapi-docker-to-k8s-139.sh
```

## Production Migration Principle

Production is still the source of truth and must not be changed during staging validation. Use 139 to prove the integrated stack first, including database migration, OAuth callback rewrites, Nginx routing, and smoke checks. Move production only after the same scripts are proven repeatable and a rollback window is agreed.

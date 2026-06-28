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

System-level deployment parameters, including ports and public paths, live in:

- `environments/staging/*.values.yaml`
- `nginx/staging/platform.values.env`

Service runtime configuration is rendered into each workload's Pod spec from the chart templates. Real secrets stay outside git in Kubernetes Secrets and `/root/platform-secrets`.

```bash
scripts/deploy-staging-139.sh
scripts/apply-nginx-config.sh
```

## Production Migration Principle

Existing production services stay on the host first. Deploy `new-api` and `ai-relay-broker` into k8s as new capabilities, then connect the existing ArcReel deployment to Broker. Migrate Casdoor and EDreamCrowd only after the new chain is stable.

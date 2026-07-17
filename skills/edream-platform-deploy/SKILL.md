---
name: edream-platform-deploy
description: Build, package, deploy, upgrade, uninstall, and validate the eDream platform on k3s/Kubernetes environments. Use when the user asks to deploy a full k3s environment, install or upgrade the platform, uninstall while keeping or deleting data, build one or more service images, replace images for validation, build a full release package, load an offline image package, configure Harbor/k3s registry access, or operate the ai-relay-ops deployment flow for any environment.
---

# eDream Platform Deploy

Use this skill to operate the `ai-relay-ops` repository. It provides the workflow for deploying the eDream platform to arbitrary k3s/Kubernetes environments, including full-package deployment and single/multiple image replacement.

## Safety Rules

- Never assume missing production parameters. Ask the user for missing target host, SSH user, namespace, release name, values file, Harbor address, image tag, data-retention intent, and credentials location.
- Never print secrets. Use environment variables, local secret files, Kubernetes Secrets, or user-provided secure channels.
- Never run `DELETE_DATA=1`, `kubectl delete pvc`, `docker volume prune`, or destructive k3s reset commands unless the user explicitly confirms the exact target environment and data deletion intent.
- Treat `kubectl set image` as temporary validation only. If validation succeeds, update the target `environments/<env>/edream-deployment.yaml` and run Helm upgrade for the durable state.
- Preserve `config/build.env` on build hosts. It is local runtime configuration and must not be overwritten by source sync.
- Prefer platform scripts over raw Helm commands: `scripts/platform/install.sh`, `upgrade.sh`, `uninstall.sh`, `preflight.sh`, `status.sh`.

## Required Context

Before acting, identify:

```text
ops repository path
target environment name
target host and SSH user
KUBECONFIG path or k3s default
deployment values file
release name and namespace
build host
Harbor registry
operation type
data retention policy
image components to build or replace
whether online Harbor pull is available
```

If any item is unavailable and cannot be discovered from files or the remote host, ask the user.

## Standard Repository Assumptions

- Ops repository: `ai-relay-ops`
- Standard build host: `81.71.122.120`
- Standard build config template: `config/build-81.env`
- Build host runtime config: `/data/edream-build/sources/ai-relay-ops/config/build.env`
- Environment values:
  - `environments/134/edream-deployment.yaml`
  - `environments/139/edream-deployment.yaml`
- Kubernetes namespace usually comes from the values file and is commonly `platform`.

## Workflow Selection

Use this decision tree:

```text
Need a k3s cluster installed or prepared?
  -> read references/operations.md section "K3S Bootstrap"

Need full release build?
  -> remote-package-all or package-all

Need full install/upgrade from package?
  -> platform package transfer, preflight, install/upgrade

Need uninstall?
  -> default keep-data uninstall unless user explicitly confirms delete data

Need one image replaced?
  -> build that image, update values, Helm upgrade, or temporary kubectl set image

Need multiple images replaced?
  -> upload selected sources, build selected images, package values, Helm upgrade

Need offline deployment?
  -> load image archive, then install/upgrade

Need restore/backup?
  -> back up Secret/ConfigMap/PVC metadata and Postgres logical data
```

## References

Read `references/operations.md` when concrete commands are needed. It contains:

- k3s bootstrap and registry preparation
- configuration files and their roles
- full build and package commands
- install, upgrade, uninstall commands
- keep-data and delete-data flows
- backup and restore commands
- single-image replacement examples
- multi-image replacement examples
- validation and smoke tests

## Validation

For documentation or skill changes, run:

```bash
scripts/verify-standard-deployment.sh
git diff --check
```

For deployment operations, validate at minimum:

```bash
scripts/platform/preflight.sh -f <deployment-values.yaml>
scripts/platform/status.sh -f <deployment-values.yaml>
kubectl -n <namespace> get pods,pvc,deploy,svc
```

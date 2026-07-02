# Rollback Runbook

## Broker

```bash
helm history broker -n platform
make rollback SERVICE=broker ENV=prod NAMESPACE=platform REVISION=<revision>
```

If Broker is unhealthy, switch ArcReel configuration back to the previous model path or disable the new model entitlement entry.

## new-api

```bash
helm history new-api -n platform
make rollback SERVICE=new-api ENV=prod NAMESPACE=platform REVISION=<revision>
```

Before rolling back new-api, confirm database compatibility. If the upgrade changed schema, restore from backup only after explicit approval.

## Existing Host Services

When migrating old services, keep the host deployment for 1-2 release cycles. Rollback by switching the reverse proxy upstream back to the host process.

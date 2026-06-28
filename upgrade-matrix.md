# Upgrade Matrix

| Service | Current | Target | DB Change | Backup Required | Smoke Test | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| broker | v0.1.1 | v0.1.1 | No | Yes before prod | `/healthz`, `/readyz`, entitlement query | `helm rollback broker <revision> -n platform` |
| new-api | latest | pinned release | Unknown | Yes | login, token CRUD, `/v1/chat/completions` | `helm rollback new-api <revision> -n platform` |

Before production upgrades, replace `latest` with immutable tags and record the image digest.

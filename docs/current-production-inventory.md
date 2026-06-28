# Current Production Inventory

Fill this file before changing production traffic.

## Host

- Host: `139.196.254.8`
- SSH user: `root`

## Existing Direct Deployments

| Service | Directory | Process Manager | Port | Database | Notes |
| --- | --- | --- | --- | --- | --- |
| Casdoor |  |  |  |  | Existing identity source, migrate last. |
| ArcReel / WhiteLabel |  |  |  |  | Keep direct deployment while connecting to Broker. |
| EDreamCrowd |  |  |  |  | Migrate last or keep direct deployment. |

## Reverse Proxy

Record Nginx/Caddy config paths, upstreams, domains, and certificate paths.

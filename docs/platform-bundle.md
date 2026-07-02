# Platform Bundle

This bundle contains the Helm chart tree, one editable environment values file,
and an optional `images/` directory with Docker image tar files.

## Directory Layout

```text
charts/                  Helm charts for the integrated platform
values/values.yaml
images/*.tar             Optional image archives
scripts/load-platform-images.sh
scripts/install-platform-bundle.sh
scripts/deploy-platform-bundle.sh
README.md
```

## New Server Prerequisites

- Kubernetes or K3s is installed.
- `kubectl` points to the target cluster.
- `helm` is installed.
- DNS records already point to this server when domain routing is used.
- Ports 80 and 443 are opened as required by the gateway configuration.
- A storage class exists for Postgres persistence. K3s normally provides
  `local-path`.

## Install Flow

1. Unpack the bundle on the new server.

```bash
tar -xzf platform-bundle-*.tar.gz
cd platform-bundle-*
```

2. Edit only the environment values file.

```bash
vim values/values.yaml
```

Replace all `CHANGE_ME_*` placeholders and update `namespace`, domains, public
IP, image repositories, image tags, ports, and storage class if needed.

3. Run one deploy command. Set `LOAD_IMAGES=true` when the bundle includes
`images/*.tar`.

```bash
LOAD_IMAGES=true scripts/deploy-platform-bundle.sh
```

If the server can pull images from a registry, loading local image tar files is
optional:

```bash
scripts/deploy-platform-bundle.sh
```

4. Upgrade later by changing only image names or tags in
`values/values.yaml`, then running the same install command again.

`NAMESPACE=...` can override the file for one run, but normal bundle installs
should keep the namespace in top-level `namespace:` inside `values/values.yaml`.

```bash
scripts/deploy-platform-bundle.sh
```

The command uses `helm upgrade --install`, so it is safe for both first install
and later upgrades.

## Runtime URLs

The gateway chart supports both IP/path and domain routing. For a 139-like
environment, configure:

```text
auth domain      -> Casdoor
api domain       -> new-api at / and Broker at /broker/
zhongchou domain -> EDreamCrowd
```

If `api.<domain>/broker/` is used as the Broker public URL, keep the gateway
route for `/broker/` before the catch-all new-api route.

For new Desktop official-provider packages, set:

```yaml
broker:
  env:
    BROKER_PUBLIC_BASE_URL: http://api.example.com/broker
    NEWAPI_BASE_URL: http://relay-new-api:3000
    NEWAPI_PUBLIC_BASE_URL: http://api.example.com
    DESKTOP_PUBLIC_CONFIG_JSON: '{"brand":"edream","subscription":{"relayBrokerBaseUrl":"http://api.example.com/broker"},"whitelabel":{"presetProvider":{"mediaBaseUrl":"http://api.example.com/v1","agentMessagesUrl":"http://api.example.com"}}}'
```

`DESKTOP_PUBLIC_CONFIG_JSON` is returned by Broker from
`/v1/public/desktop-config`. New Desktop packages read that runtime config before
writing their local sidecar config, so bundle users can unpack, edit
`values/values.yaml` for namespace/domains/public URLs, and deploy with one
Helm command. `NEWAPI_BASE_URL` stays inside the cluster.

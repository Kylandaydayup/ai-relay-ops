# AI Provider Adapter Implementation Plan

This is the final implementation plan used for the 139 integration. The adapter source is intentionally placed in `ai-relay-broker`, while build, packaging, values, Helm, and New API channel operations live in `ai-relay-ops`.

## Scope

- Do not modify `/Users/bytedance/dev/drama/new-api` source.
- Keep existing production Keyiyun channel untouched; add via-adapter backup channels.
- Update the original MOMA Seedance channel to point at the adapter.
- Keep API keys in New API channels or Helm Secrets; never log key values.
- Use Helm `--reuse-values` for 139 validation so unrelated release values and persistent data are preserved.

## Broker Work

Files:

- `/Users/bytedance/dev/drama/ai-relay-broker/provider_adapter/`
- `/Users/bytedance/dev/drama/ai-relay-broker/tests/provider_adapter/`
- `/Users/bytedance/dev/drama/ai-relay-broker/Dockerfile.ai-provider-adapter`
- `/Users/bytedance/dev/drama/ai-relay-broker/vendor/maas_seedance_sdk-1.0.0-py3-none-any.whl`

Implementation:

- Expose `GET /healthz`, `GET /readyz`.
- Expose New API compatible video task endpoints:
  - `POST /api/v3/contents/generations/tasks`
  - `GET /api/v3/contents/generations/tasks/{task_id}`
  - `POST /v1/videos`
  - `GET /v1/videos/{task_id}`
- Resolve provider by explicit provider, `X-Adapter-Provider`, model map, or default provider.
- Prefix public upstream task IDs with provider name so fetch can dispatch statelessly.
- Forward New API channel Authorization to upstream when Helm provider key is blank.

MOMA Seedance:

- Resolve endpoint through `POST {root_base_url}/api/v3/mapping/query`.
- Fall back to `{root_base_url}/mapping/query` for compatibility.
- Create/query tasks through `{root_base_url}/api/v3/contents/generations/tasks`.
- Default `MOMA_SEEDANCE_ENABLE_VIDEO_ENCRYPT=false`.
- Set `Input-Has-Video: true` for video input payloads.

Keyiyun:

- VEO create path: `{KEYIYUN_BASE_URL}/v1/veo/videos`.
- Fetch path: `{KEYIYUN_BASE_URL}/v1/result/{task_id}`.
- Grok uses the same provider class with configurable create path.

## Ops Work

Files:

- `/Users/bytedance/dev/drama/ai-relay-ops/charts/ai-provider-adapter/`
- `/Users/bytedance/dev/drama/ai-relay-ops/charts/platform/Chart.yaml`
- `/Users/bytedance/dev/drama/ai-relay-ops/charts/platform/values.yaml`
- `/Users/bytedance/dev/drama/ai-relay-ops/environments/template/values.yaml`
- `/Users/bytedance/dev/drama/ai-relay-ops/environments/staging/platform.values.yaml`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/build-platform-images.sh`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/package-platform-bundle.sh`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/install-platform-bundle.sh`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/deploy-platform-staging-139.sh`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/configure-newapi-provider-adapter-139.sh`
- `/Users/bytedance/dev/drama/ai-relay-ops/scripts/verify-newapi-provider-adapter-139.sh`

Helm:

- `ai-provider-adapter.enabled`
- `ai-provider-adapter.image.repository/tag/pullPolicy`
- `ai-provider-adapter.env`
- `ai-provider-adapter.secret`
- Service port `80`, target container port `8080`.
- SDK log envs default to `ERROR`: `LOG_LEVEL`, `TOP_LOGGER_LEVEL`, `TASK_LOGGER_LEVEL`.

New API channel config on 139:

- MOMA Seedance channel id `3`: keep type/model/key, set `base_url` to `http://ai-provider-adapter.platform.svc.cluster.local`.
- Keyiyun source channel id `6`: leave unchanged.
- Add/update backup channels:
  - `Keyiyun VEO via Adapter`
  - `Keyiyun Grok via Adapter`
- Refresh `abilities` for the backup channels.
- Back up `channels` and `abilities` before changing data.

## Validation

Local:

```bash
cd /Users/bytedance/dev/drama/ai-relay-broker
.venv/bin/python -m pytest tests/provider_adapter -q
.venv/bin/python -m ruff check provider_adapter tests/provider_adapter

cd /Users/bytedance/dev/drama/ai-relay-ops
bash -n scripts/configure-newapi-provider-adapter-139.sh scripts/verify-newapi-provider-adapter-139.sh
scripts/verify-platform-chart.sh
```

139:

- Build and import adapter image into k3s containerd.
- `helm upgrade --install platform charts/platform -n platform --reuse-values -f adapter-overlay.yaml`.
- Confirm adapter `Deployment` and `Service` are healthy.
- Run `/root/ai-relay-ops/scripts/configure-newapi-provider-adapter-139.sh`.
- Verify channel config with `/root/ai-relay-ops/scripts/verify-newapi-provider-adapter-139.sh`.
- Run one low-cost Seedance 5-second task through New API and poll until `SUCCESS`.
- Do not delete the `platform` namespace; namespace deletion conflicts with the no-data-loss requirement.

#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import subprocess
import time
import urllib.request
import uuid
from pathlib import Path

CONTRACTS = r"""
import asyncio
import hashlib
import importlib.metadata
import json
from pathlib import Path

import httpx
import maas_seedance
import python_multipart
from bytedance.volcengine_aicc_sdk.seedance_inference_client import SeedanceClient
from provider_adapter.app import create_app
from provider_adapter.providers.base import ProviderCreateResult, ProviderFetchResult
from provider_adapter.providers.lingzhi import LingzhiWan3Provider, WAN3_STANDARD_MODEL
from provider_adapter.settings import Settings

VIDEO = b"\x00\x00\x00\x18ftypisom" + bytes(4096)

class RecordingProvider:
    name = 'smoke'
    payload = None

    async def create_task(self, payload, authorization):
        assert authorization == 'Bearer smoke-only-credential'
        self.payload = payload
        return ProviderCreateResult(provider=self.name, upstream_task_id='local-only', model=payload['model'], raw={})

    async def fetch_task(self, task, authorization):
        return ProviderFetchResult(provider=self.name, upstream_task_id=task, model='smoke-model', status='succeeded', progress=100, video_url='https://example.invalid/video.mp4', raw={})

    async def fetch_content(self, task, authorization):
        return VIDEO, 'video/mp4'

async def verify():
    provider = RecordingProvider()
    app = create_app(settings=Settings(default_provider=provider.name), providers={provider.name: provider})
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://adapter.invalid') as client:
        created = await client.post('/v1/videos', headers={'Authorization': 'Bearer smoke-only-credential'}, data={'model': 'smoke-model', 'prompt': 'local validation', 'seconds': '5'}, files=[('input_reference', ('a.png', b'\x89PNG\r\n\x1a\na', 'image/png')), ('input_reference', ('b.png', b'\x89PNG\r\n\x1a\nb', 'image/png'))])
        assert created.status_code == 200 and created.json()['id'] == 'smoke:local-only'
        assert len(provider.payload['images']) == 2
        assert provider.payload['input_reference'] == provider.payload['images'][0]
        assert all(image.startswith('data:image/png;base64,') for image in provider.payload['images'])
        fetched = await client.get('/v1/videos/smoke:local-only')
        assert fetched.status_code == 200 and fetched.json()['status'] == 'completed'
        content = await client.get('/v1/videos/smoke:local-only/content')
        head = await client.head('/v1/videos/smoke:local-only/content')
        assert content.status_code == head.status_code == 200 and content.content == VIDEO
        assert head.headers['content-length'] == str(len(VIDEO))

    mode = 'direct'
    mime = 'video/mp4'
    query_status = 200
    uploads = []
    cross_domain_checks = []

    async def upstream(request):
        nonlocal mode, mime, query_status
        assert request.url.host in {'upstream.invalid', 'media.youkou.cc'}
        if request.url.host == 'media.youkou.cc':
            assert 'authorization' not in request.headers and 'cookie' not in request.headers
            cross_domain_checks.append(True)
            return httpx.Response(200, content=VIDEO, headers={'content-type': 'video/mp4'})
        if request.url.path == '/v1/media/uploads':
            assert request.method == 'POST' and 'multipart/form-data' in request.headers['content-type']
            uploads.append(True)
            return httpx.Response(200, json={'media_id': 'local-' + str(len(uploads))})
        if request.url.path == '/v1/videos':
            assert request.method == 'POST'
            payload = json.loads(request.content)
            assert payload['model'] == WAN3_STANDARD_MODEL and payload['duration_seconds'] == 5
            # Existing multipart input keeps the primary alias alongside its image list.
            assert len(payload['input_images']) == 3
            return httpx.Response(200, json={'id': 'local-upstream-only'})
        assert request.method == 'GET'
        if request.url.path.endswith('/content'):
            if mode == 'redirect':
                return httpx.Response(302, headers={'location': 'https://media.youkou.cc/local.mp4'})
            if mode == 'untrusted':
                return httpx.Response(302, headers={'location': 'http://untrusted.invalid/private'})
            if mode == 'empty':
                return httpx.Response(200, content=b'', headers={'content-type': 'video/mp4'})
            if mode == 'json':
                return httpx.Response(200, json={'message': 'not a video'})
            return httpx.Response(200, content=VIDEO, headers={'content-type': mime} if mime else {})
        if query_status != 200:
            return httpx.Response(query_status, json={'message': 'local transient query'})
        return httpx.Response(200, json={'status': 'completed', 'content_url': 'https://media.youkou.cc/local.mp4'})

    async with httpx.AsyncClient(transport=httpx.MockTransport(upstream), headers={'Authorization': 'Bearer inherited-local-credential', 'Cookie': 'local=only'}) as upstream_client:
        lingzhi = LingzhiWan3Provider(name='lingzhi_wan3', base_url='https://upstream.invalid', api_key='', http_client=upstream_client)
        app = create_app(settings=Settings(default_provider=lingzhi.name), providers={lingzhi.name: lingzhi})
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://adapter.invalid') as client:
            created = await client.post('/v1/videos', headers={'Authorization': 'Bearer smoke-only-credential'}, data={'model': 'wan3_480p', 'prompt': 'local validation', 'seconds': '5'}, files=[('input_reference', ('a.png', b'\x89PNG\r\n\x1a\na', 'image/png')), ('input_reference', ('b.png', b'\x89PNG\r\n\x1a\nb', 'image/png'))])
            assert created.status_code == 200 and created.json()['id'] == 'lingzhi_wan3:local-upstream-only'
            assert len(uploads) == 3
            for query_status in (408, 429, 500, 502, 503):
                response = await client.get('/v1/videos/lingzhi_wan3:existing')
                assert response.status_code == 200 and response.json()['status'] == 'processing'
            query_status = 200
            response = await client.get('/v1/videos/lingzhi_wan3:existing')
            assert response.status_code == 200 and response.json()['status'] == 'completed'
            for mime in ('video/mp4', 'application/octet-stream', None):
                response = await client.get('/v1/videos/lingzhi_wan3:existing/content')
                assert response.status_code == 200 and response.content == VIDEO
            mode = 'redirect'
            response = await client.get('/v1/videos/lingzhi_wan3:existing/content', headers={'Authorization': 'Bearer smoke-only-credential'})
            assert response.status_code == 200 and response.content == VIDEO and cross_domain_checks
            for mode in ('untrusted', 'empty', 'json'):
                response = await client.get('/v1/videos/lingzhi_wan3:existing/content')
                assert response.status_code == 502

    paths = sorted(Path('provider_adapter').rglob('*.py')) + sorted(Path('vendor').glob('*.whl')) + [Path('pyproject.toml')]
    print(json.dumps({'runtime_contracts': 'passed', 'multipart_images': 2, 'lingzhi_upload_and_submit': 'mock_only_passed', 'transient_queries': 'passed', 'direct_and_redirect_downloads': 'passed', 'cross_domain_credentials_removed': True, 'invalid_content_rejected': True, 'vendor_sdk_import': 'passed', 'no_paid_requests': True, 'source_hashes': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}, 'runtime_versions': {name: importlib.metadata.version(name) for name in ('fastapi', 'starlette', 'httpx', 'python-multipart', 'uvicorn', 'maas-seedance-sdk')}}))

asyncio.run(verify())
"""


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


def run(image, source_dir):
    container = None
    try:
        container = docker(
            "run",
            "-d",
            "--name",
            "adapter-image-verify-" + uuid.uuid4().hex[:12],
            "--tmpfs",
            "/tmp:rw,size=16m",
            "--memory",
            "512m",
            "--cpus",
            "1",
            "--pids-limit",
            "128",
            "--cap-drop",
            "ALL",
            "--security-opt",
            "no-new-privileges",
            "-p",
            "127.0.0.1::8080",
            image,
        )
        port = docker("port", container, "8080/tcp").splitlines()[0].rsplit(":", 1)[1]
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for attempt in range(30):
            try:
                for path, expected in (("healthz", "ok"), ("readyz", "ready")):
                    with opener.open(f"http://127.0.0.1:{port}/{path}", timeout=2) as response:
                        assert response.status == 200 and json.load(response)["status"] == expected
                break
            except (OSError, ValueError, AssertionError):
                if attempt == 29 or docker("inspect", "--format", "{{.State.Running}}", container) != "true":
                    raise RuntimeError("Default image entrypoint failed readiness") from None
                time.sleep(1)
        completed = subprocess.run(
            ["docker", "exec", "-i", container, "python", "-"],
            input=CONTRACTS,
            text=True,
            capture_output=True,
            timeout=90,
        )
        if completed.returncode:
            raise RuntimeError("Image runtime contracts failed: " + completed.stderr[-2000:])
        result = json.loads(completed.stdout)
        if source_dir:
            for relative, digest in result["source_hashes"].items():
                assert hashlib.sha256((source_dir / relative).read_bytes()).hexdigest() == digest, (
                    "Image/source mismatch: " + relative
                )
            expected = {str(path.relative_to(source_dir)) for path in (source_dir / "provider_adapter").rglob("*.py")}
            assert expected == {path for path in result["source_hashes"] if path.startswith("provider_adapter/")}
            result["image_matches_source"] = True
        details = json.loads(docker("image", "inspect", image))[0]
        assert details["Os"] == "linux" and details["Architecture"] == "amd64"
        result.update(
            image=image,
            image_id=details["Id"],
            repo_digests=details.get("RepoDigests", []),
            default_entrypoint="passed",
            published_port="loopback_only",
        )
        return result
    finally:
        if container:
            subprocess.run(["docker", "rm", "-f", container], check=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(
        description="Verify a built Adapter image without supplier credentials or paid requests."
    )
    parser.add_argument("--image", required=True)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = run(args.image, args.source_dir)
    except Exception as exc:
        print(json.dumps({"image_verification": "failed", "error_type": type(exc).__name__, "reason": str(exc)}))
        return 1
    if args.output:
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

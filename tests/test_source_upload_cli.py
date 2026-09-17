import os
import shutil
import subprocess
import tempfile
import unittest
import uuid
from pathlib import Path


@unittest.skipUnless(os.name == "posix", "Linux source-upload checks")
class SourceUploadCliTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="ops-source-upload-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.ops = self.root / "local ops"
        self.home = self.root / "remote home"
        self.home.mkdir()
        self.remote = self.root / "build root/sources/ops"
        self.remote.mkdir(parents=True)
        (self.remote / "old-source").write_text("previous checkout", encoding="utf-8")
        (self.remote / "config").mkdir()
        (self.remote / "config/build.env").write_text("PRIVATE_SENTINEL=retained\n", encoding="utf-8")
        repo = Path(__file__).parents[1]
        for relative in ("scripts/sources/upload-local.sh", "scripts/lib/timing.sh"):
            target = self.ops / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repo / relative, target)
        self.init_repo(self.ops)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.executable(
            "scp",
            """#!/usr/bin/env python3
import os
import pathlib
import shutil
import sys
source, destination = sys.argv[-2:]
destination = pathlib.Path(destination.split(':', 1)[1])
with (pathlib.Path(os.environ['FIXTURE']) / 'copied-paths').open('a') as handle:
    handle.write(str(destination) + '\\n')
if os.environ.get('CORRUPT_ARCHIVE') == '1':
    destination.write_bytes(b'not a tar archive')
else:
    shutil.copyfile(source, destination)
""",
        )
        self.executable(
            "ssh",
            """#!/usr/bin/env python3
import os
import subprocess
import sys
raise SystemExit(subprocess.run(['bash', '-c', sys.argv[-1]], cwd=os.environ['REMOTE_HOME']).returncode)
""",
        )
        self.addCleanup(self.remove_uploaded_archives)

    def remove_uploaded_archives(self):
        log = self.root / "copied-paths"
        if log.exists():
            for name in log.read_text().splitlines():
                Path(name).unlink(missing_ok=True)

    def init_repo(self, path):
        path.mkdir(parents=True, exist_ok=True)
        (path / "source-marker").write_text(str(uuid.uuid4()), encoding="utf-8")
        for args in (
            ("init", "-q"),
            ("config", "user.email", "test@example.invalid"),
            ("config", "user.name", "Source Upload Test"),
            ("add", "."),
            ("commit", "-qm", "fixture"),
        ):
            subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True)

    def executable(self, name, source):
        path = self.bin / name
        path.write_text(source, encoding="utf-8")
        path.chmod(0o700)

    def upload(self, *, target="ops", ops=None, **settings):
        env = dict(os.environ)
        env.update(
            PATH=f"{self.bin}:{env['PATH']}",
            FIXTURE=str(self.root),
            REMOTE_HOME=str(self.home),
            BUILD_ENV_FILE=str(self.root / "no-config"),
            REMOTE_BUILD_TARGET="fixture-host",
            REMOTE_SSH_OPTS="",
            REMOTE_OPS_DIR=str(self.remote),
            BUILD_ROOT=str(self.root / "build root"),
            UPLOAD_TARGETS=target,
            ALLOW_DIRTY_UPLOAD="0",
            SYNC_CASDOOR="0",
            BUILD_CASDOOR="0",
        )
        env.update(settings)
        return subprocess.run(
            ["bash", str((ops or self.ops) / "scripts/sources/upload-local.sh")],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_clean_upload_preserves_private_config_and_snapshots_previous_source(self):
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.remote / "source-marker").read_text(), (self.ops / "source-marker").read_text())
        self.assertFalse((self.remote / ".git").exists())
        self.assertEqual((self.remote / "config/build.env").read_text(), "PRIVATE_SENTINEL=retained\n")
        self.assertEqual((self.remote / "config/build.env").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.remote / ".edream-source-meta").stat().st_mode & 0o777, 0o600)
        commit = subprocess.check_output(
            ["git", "-C", str(self.ops), "rev-parse", "--short", "HEAD"], text=True
        ).strip()
        self.assertIn(f"commit={commit}\n", (self.remote / ".edream-source-meta").read_text())
        snapshots = list((self.root / "build root/source-snapshots").iterdir())
        self.assertEqual(len(snapshots), 1)
        self.assertEqual((snapshots[0] / "old-source").read_text(), "previous checkout")
        self.assertEqual((snapshots[0] / "config/build.env").read_text(), "PRIVATE_SENTINEL=retained\n")
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual(list(self.remote.parent.glob("ops.upload-*")), [])
        self.assertNotIn("PRIVATE_SENTINEL", result.stdout + result.stderr)

    def test_dirty_source_is_rejected_before_upload(self):
        (self.ops / "uncommitted").write_text("dirty", encoding="utf-8")
        result = self.upload()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("uncommitted changes", result.stderr)
        self.assertTrue((self.remote / "old-source").exists())
        self.assertFalse((self.root / "copied-paths").exists())

    def test_bad_archive_does_not_replace_previous_source(self):
        result = self.upload(CORRUPT_ARCHIVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.remote / "old-source").read_text(), "previous checkout")
        self.assertEqual((self.remote / "config/build.env").read_text(), "PRIVATE_SENTINEL=retained\n")
        self.assertEqual(list((self.root / "build root/source-snapshots").iterdir()), [])

    def test_git_worktree_is_supported(self):
        worktree = self.root / "local worktree"
        subprocess.run(
            ["git", "-C", str(self.ops), "worktree", "add", "--detach", str(worktree)], check=True, capture_output=True
        )
        self.assertTrue((worktree / ".git").is_file())
        result = self.upload(ops=worktree)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("branch=detached\n", (self.remote / ".edream-source-meta").read_text())

    def test_explicit_targets_override_config_default(self):
        config = self.root / "upload.env"
        config.write_text('UPLOAD_TARGETS="broker"\n', encoding="utf-8")
        result = self.upload(BUILD_ENV_FILE=str(config))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("name=ops\n", (self.remote / ".edream-source-meta").read_text())

    def test_broker_upload_only_changes_selected_source(self):
        broker = self.root / "local broker"
        self.init_repo(broker)
        target = self.root / "build root/sources/broker"
        target.mkdir()
        (target / "old-source").write_text("previous broker", encoding="utf-8")
        result = self.upload(target="broker", BROKER_UPLOAD_DIR=str(broker), BROKER_LOCAL_DIR=str(target))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.remote / "old-source").exists())
        self.assertEqual((target / "source-marker").read_text(), (broker / "source-marker").read_text())
        self.assertIn("name=broker\n", (target / ".edream-source-meta").read_text())


if __name__ == "__main__":
    unittest.main()

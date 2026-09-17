import copy
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

import test_adapter_upgrade as contracts


@unittest.skipUnless(os.name == "posix", "Linux release-script checks")
class AdapterUpgradeCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        repo = Path(__file__).parents[1]
        for file in (
            "scripts/platform/lib-platform.sh",
            "scripts/platform/upgrade-adapter.sh",
            "scripts/platform/check-adapter-upgrade.py",
            "scripts/lib/timing.sh",
        ):
            target = self.root / file
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repo / file, target)
        self.write_executable("scripts/platform/preflight.sh", "#!/bin/sh\nexit 0\n")
        fixture = contracts.AdapterUpgradeTests()
        fixture.setUp()
        self.saved = fixture.saved
        self.desired = fixture.desired
        self.live = fixture.live
        self.desired[fixture.target]["spec"]["template"]["spec"]["containers"][0][
            "image"
        ] = "verified-new-image"
        (self.root / "saved.yaml").write_text(
            yaml.safe_dump_all(self.saved.values()), encoding="utf-8"
        )
        self.write_desired()
        for key, doc in self.live.items():
            (self.root / f"{key[3]}.json").write_text(json.dumps(doc), encoding="utf-8")
        (self.root / "values.yaml").write_text(
            yaml.safe_dump(
                {
                    "namespace": "platform",
                    "deployment": {"releaseName": "platform-relay"},
                    "ai-provider-adapter": {
                        "enabled": True,
                        "fullnameOverride": "ai-provider-adapter",
                        "secret": {"create": False},
                    },
                }
            ),
            encoding="utf-8",
        )
        self.write_executable(
            "bin/helm",
            """#!/bin/bash
echo "$*" >> "$FIXTURE/helm-calls.txt"
case "$1 $2" in
  "get manifest") cat "$FIXTURE/saved.yaml" ;;
  "get values") echo '{}' ;;
  "template "*) cat "$FIXTURE/desired.yaml" ;;
  "history "*) echo '[]' ;;
  "status "*|"upgrade "*) echo 'OK' ;;
  *) exit 2 ;;
esac
""",
        )
        self.write_executable(
            "bin/kubectl",
            """#!/bin/bash
if [ "$1 $2" = "get pods" ]; then
  echo '{"items":[]}'
elif [ "$1 $3 $4" = '-n get Deployment' ]; then
  cat "$FIXTURE/$5.json"
elif [ "$1 $2" = 'rollout status' ]; then
  echo 'Ready'
else
  exit 2
fi
""",
        )

    def write_executable(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(0o700)

    def write_desired(self):
        (self.root / "desired.yaml").write_text(
            yaml.safe_dump_all(self.desired.values()), encoding="utf-8"
        )

    def run_upgrade(self, apply=False):
        command = [
            "bash",
            str(self.root / "scripts/platform/upgrade-adapter.sh"),
            "-f",
            str(self.root / "values.yaml"),
        ]
        if apply:
            command.append("--apply")
        env = dict(os.environ)
        env.update(
            PATH=f"{self.root / 'bin'}:{env['PATH']}",
            FIXTURE=str(self.root),
            ADAPTER_BACKUP_ROOT=str(self.root / "backups"),
        )
        return subprocess.run(command, env=env, capture_output=True, text=True)

    def test_default_only_dry_runs_and_protects_backup(self):
        result = self.run_upgrade()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        upgrades = [
            line
            for line in (self.root / "helm-calls.txt").read_text().splitlines()
            if line.startswith("upgrade ")
        ]
        self.assertEqual(len(upgrades), 1)
        self.assertIn("--dry-run=server", upgrades[0])
        backup = next((self.root / "backups").iterdir())
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        for file in backup.iterdir():
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)

    def test_apply_requires_preflight_then_waits_without_atomic(self):
        result = self.run_upgrade(apply=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        upgrades = [
            line
            for line in (self.root / "helm-calls.txt").read_text().splitlines()
            if line.startswith("upgrade ")
        ]
        self.assertEqual(len(upgrades), 2)
        self.assertIn("--dry-run=server", upgrades[0])
        self.assertIn("--wait", upgrades[1])
        self.assertNotIn("--atomic", upgrades[1])

    def test_drift_blocks_even_explicit_apply(self):
        key = ("apps/v1", "Deployment", "platform", "relay-new-api")
        self.desired = copy.deepcopy(self.desired)
        self.desired[key]["spec"]["template"]["spec"]["containers"][0]["image"] = (
            "would-change-other-service"
        )
        self.write_desired()
        result = self.run_upgrade(apply=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Adapter-only upgrade blocked", result.stdout)
        self.assertFalse(
            any(
                line.startswith("upgrade ")
                for line in (self.root / "helm-calls.txt").read_text().splitlines()
            )
        )


if __name__ == "__main__":
    unittest.main()

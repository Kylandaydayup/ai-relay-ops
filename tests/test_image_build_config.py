import os
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(os.name == "posix", "Linux image-build checks")
class ImageBuildConfigTests(unittest.TestCase):
    def read_values_target(self, override=None):
        with tempfile.TemporaryDirectory(prefix="ops-build-config-") as directory:
            config = Path(directory) / "build.env"
            config.write_text('DEPLOYMENT_VALUES_FILE="/configured/139.yaml"\n', encoding="utf-8")
            env = dict(os.environ)
            env.pop("DEPLOYMENT_VALUES_FILE", None)
            env.update(
                BUILD_ENV_FILE=str(config),
                BUILD_LIB=str(Path(__file__).parents[1] / "scripts/images/lib-image-build.sh"),
            )
            if override is not None:
                env["DEPLOYMENT_VALUES_FILE"] = override
            result = subprocess.run(
                ["bash", "-c", '. "$BUILD_LIB"; source_build_config; printf "%s" "$DEPLOYMENT_VALUES_FILE"'],
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

    def test_omitted_target_uses_build_config(self):
        self.assertEqual(self.read_values_target(), "/configured/139.yaml")

    def test_explicit_target_overrides_config(self):
        self.assertEqual(self.read_values_target("/candidate/134.yaml"), "/candidate/134.yaml")

    def test_explicit_empty_target_disables_values_update(self):
        self.assertEqual(self.read_values_target(""), "")


if __name__ == "__main__":
    unittest.main()

import copy
import importlib.util
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "guard", Path(__file__).parents[1] / "scripts/platform/check-adapter-upgrade.py"
)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class AdapterUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.target = ("apps/v1", "Deployment", "platform", "ai-provider-adapter")
        self.other = ("apps/v1", "Deployment", "platform", "relay-new-api")
        self.saved = {}
        for key in (self.target, self.other):
            self.saved[key] = {
                "apiVersion": key[0],
                "kind": key[1],
                "metadata": {"name": key[3], "labels": {"app": key[3]}},
                "spec": {
                    "selector": {"matchLabels": {"app": key[3]}},
                    "template": {
                        "spec": {
                            "containers": [
                                {
                                    "name": "service",
                                    "image": "original",
                                    "env": [{"name": "MODE", "value": "original"}],
                                }
                            ]
                        }
                    },
                },
            }
        self.desired = copy.deepcopy(self.saved)
        self.live = copy.deepcopy(self.saved)
        for item in self.live.values():
            item["metadata"]["annotations"] = {
                "meta.helm.sh/release-name": "platform-relay"
            }
            item["metadata"]["resourceVersion"] = "42"
            item["spec"]["template"]["spec"]["containers"][0]["imagePullPolicy"] = (
                "IfNotPresent"
            )
            item["status"] = {"availableReplicas": 1}

    def check(self):
        return guard.check(
            self.saved, self.desired, self.live, self.target, "platform-relay"
        )

    def test_only_adapter_image_or_env_can_change(self):
        container = self.desired[self.target]["spec"]["template"]["spec"]["containers"][
            0
        ]
        container["image"] = "new@sha256:pinned"
        container["env"][0]["value"] = "new"
        self.assertEqual(self.check(), [])

    def test_existing_live_settings_can_be_recorded_without_modifying_other_component(
        self,
    ):
        for data in (self.desired, self.live):
            data[self.other]["spec"]["template"]["spec"]["containers"][0]["image"] = (
                "already-live"
            )
        self.assertEqual(self.check(), [])

    def test_other_image_change_is_rejected(self):
        self.desired[self.other]["spec"]["template"]["spec"]["containers"][0][
            "image"
        ] = "changed"
        self.assertTrue(self.check())

    def test_saved_values_do_not_hide_live_configuration_drift(self):
        self.live[self.other]["spec"]["template"]["spec"]["containers"][0]["env"][0][
            "value"
        ] = "private-secret-sentinel"
        errors = self.check()
        self.assertTrue(errors)
        self.assertNotIn("private-secret-sentinel", str(errors))

    def test_env_reordering_could_restart_other_pod_and_is_rejected(self):
        for data in (self.desired, self.live):
            data[self.other]["spec"]["template"]["spec"]["containers"][0]["env"].append(
                {"name": "EXTRA", "value": "same"}
            )
        self.live[self.other]["spec"]["template"]["spec"]["containers"][0][
            "env"
        ].reverse()
        self.assertTrue(self.check())

    def test_removing_previously_managed_field_is_rejected(self):
        for data in (self.saved, self.live):
            data[self.other]["spec"]["strategy"] = {"type": "Recreate"}
        self.assertTrue(self.check())

    def test_resource_removal_is_rejected(self):
        del self.desired[self.other]
        self.assertTrue(self.check())

    def test_removing_managed_field_inside_named_list_is_rejected(self):
        del self.desired[self.other]["spec"]["template"]["spec"]["containers"][0][
            "env"
        ][0]["value"]
        self.assertTrue(self.check())

    def test_removing_managed_label_is_rejected(self):
        del self.desired[self.other]["metadata"]["labels"]["app"]
        self.assertTrue(self.check())

    def test_recording_live_named_list_order_does_not_count_as_field_removal(self):
        for data in (self.saved, self.desired, self.live):
            data[self.other]["spec"]["template"]["spec"]["containers"][0]["env"].append(
                {"name": "EXTRA", "value": "same"}
            )
        for data in (self.desired, self.live):
            data[self.other]["spec"]["template"]["spec"]["containers"][0][
                "env"
            ].reverse()
        self.assertEqual(self.check(), [])

    def test_resource_addition_is_rejected(self):
        key = ("v1", "Service", "platform", "extra")
        self.desired[key] = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {"name": "extra"},
        }
        self.assertTrue(self.check())

    def test_hook_is_rejected(self):
        self.desired[self.target]["metadata"]["annotations"] = {
            "helm.sh/hook": "pre-upgrade"
        }
        self.assertTrue(self.check())

    def test_selector_change_is_rejected(self):
        self.desired[self.target]["spec"]["selector"] = {
            "matchLabels": {"app": "other"}
        }
        self.assertTrue(self.check())

    def test_release_mismatch_is_rejected(self):
        self.live[self.target]["metadata"]["annotations"][
            "meta.helm.sh/release-name"
        ] = "different-release"
        self.assertTrue(self.check())


if __name__ == "__main__":
    unittest.main()

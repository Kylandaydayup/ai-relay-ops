"""Reject an umbrella-chart upgrade that could change non-adapter resources."""

import argparse
import json
import os
import subprocess
from pathlib import Path

import yaml


def identity(doc, namespace):
    metadata = doc["metadata"]
    return (
        doc["apiVersion"],
        doc["kind"],
        metadata.get("namespace", namespace),
        metadata["name"],
    )


def manifests(path, namespace):
    result = {}
    for doc in yaml.safe_load_all(Path(path).read_text(encoding="utf-8")):
        if not isinstance(doc, dict):
            continue
        key = identity(doc, namespace)
        if key in result:
            raise ValueError("duplicate manifest identity")
        result[key] = doc
    return result


def differences(expected, actual, path=""):
    """Allow API-server defaults, but preserve explicit values and list order."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [path]
        return [
            item
            for key, value in expected.items()
            for item in differences(
                value, actual.get(key), f"{path}.{key}" if path else key
            )
        ]
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            return [path]
        return [
            item
            for i, value in enumerate(expected)
            for item in differences(value, actual[i], f"{path}[{i}]")
        ]
    return [] if expected == actual else [path]


def removed_fields(previous, desired, live, path=""):
    if all(isinstance(value, list) for value in (previous, desired, live)):
        # Kubernetes merges named lists by name, even when their order changes.
        if all(
            isinstance(item, dict) and "name" in item
            for values in (previous, desired, live)
            for item in values
        ):
            wanted = {item["name"]: item for item in desired}
            current = {item["name"]: item for item in live}
            return [
                field
                for item in previous
                if item["name"] in current
                for field in (
                    removed_fields(
                        item,
                        wanted[item["name"]],
                        current[item["name"]],
                        f"{path}[name={item['name']}]",
                    )
                    if item["name"] in wanted
                    else [path]
                )
            ]
        if len(previous) == len(desired) == len(live):
            return [
                field
                for i, item in enumerate(previous)
                for field in removed_fields(item, desired[i], live[i], f"{path}[{i}]")
            ]
        return []
    if (
        not isinstance(previous, dict)
        or not isinstance(desired, dict)
        or not isinstance(live, dict)
    ):
        return []
    removed = []
    for key, value in previous.items():
        child = f"{path}.{key}" if path else key
        if key not in desired and key in live:
            removed.append(child)
        elif key in desired:
            removed.extend(removed_fields(value, desired[key], live.get(key), child))
    return removed


def check(saved, desired, live, target, release):
    errors = []
    if saved.keys() != desired.keys():
        errors.append(
            "resource additions/removals detected; use the reviewed platform upgrade flow"
        )
    if target not in saved or target not in desired or target not in live:
        errors.append("adapter Deployment must already belong to this release")
        return errors
    deployment = live[target]
    annotations = deployment.get("metadata", {}).get("annotations", {})
    if annotations.get("meta.helm.sh/release-name") != release:
        errors.append("adapter Helm release ownership mismatch")
    if desired[target]["spec"].get("selector") != deployment["spec"].get("selector"):
        errors.append("adapter selector change rejected")
    for key, doc in desired.items():
        hooks = doc.get("metadata", {}).get("annotations", {}).get("helm.sh/hook", "")
        if hooks:
            errors.append(
                f"{key[1]}/{key[3]}: hook execution is not allowed in adapter-only upgrades"
            )
        if key == target:
            continue
        current = live.get(key)
        if current is None:
            errors.append(f"{key[1]}/{key[3]}: live resource missing")
            continue
        paths = differences(doc, current)
        old = saved.get(key, {})
        for field in ("spec", "data", "stringData", "binaryData"):
            paths.extend(
                removed_fields(
                    old.get(field, {}),
                    doc.get(field, {}),
                    current.get(field, {}),
                    field,
                )
            )
        for field in ("annotations", "labels"):
            paths.extend(
                removed_fields(
                    old.get("metadata", {}).get(field, {}),
                    doc.get("metadata", {}).get(field, {}),
                    current.get("metadata", {}).get(field, {}),
                    "metadata." + field,
                )
            )
        if paths:
            errors.append(f"{key[1]}/{key[3]}: " + ", ".join(sorted(set(paths))[:8]))
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--saved", required=True)
    parser.add_argument("--desired", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--release", required=True)
    parser.add_argument("--adapter", required=True)
    parser.add_argument("--snapshot", required=True)
    args = parser.parse_args()
    saved = manifests(args.saved, args.namespace)
    desired = manifests(args.desired, args.namespace)
    target = ("apps/v1", "Deployment", args.namespace, args.adapter)
    live = {}
    for key in saved.keys() | desired.keys():
        try:
            value = subprocess.check_output(
                ["kubectl", "-n", key[2], "get", key[1], key[3], "-o", "json"],
                stderr=subprocess.DEVNULL,
            )
            live[key] = json.loads(value)
        except subprocess.CalledProcessError:
            continue
    # External credentials are backed up without decoding or logging their values.
    secrets = {}
    for container in (
        desired.get(target, {})
        .get("spec", {})
        .get("template", {})
        .get("spec", {})
        .get("containers", [])
    ):
        for env in container.get("env", []):
            ref = env.get("valueFrom", {}).get("secretKeyRef")
            if not ref:
                continue
            if ref["name"] not in secrets:
                secrets[ref["name"]] = json.loads(
                    subprocess.check_output(
                        [
                            "kubectl",
                            "-n",
                            args.namespace,
                            "get",
                            "secret",
                            ref["name"],
                            "-o",
                            "json",
                        ],
                        stderr=subprocess.DEVNULL,
                    )
                )
            if ref["key"] not in secrets[ref["name"]].get("data", {}):
                raise ValueError("referenced adapter Secret key is missing")
    snapshot = {
        "resources": list(live.values()),
        "external_secrets": list(secrets.values()),
    }
    fd = os.open(args.snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(snapshot, handle, indent=2)
    errors = check(saved, desired, live, target, args.release)
    if errors:
        print("Adapter-only upgrade blocked (paths only; values redacted):")
        for error in errors:
            print("- " + error)
        raise SystemExit(1)
    print(
        "PASS: no non-adapter resource changes detected; external Secret references verified"
    )
    print(
        "Current adapter image: "
        + live[target]["spec"]["template"]["spec"]["containers"][0]["image"]
    )
    print(
        "Desired adapter image: "
        + desired[target]["spec"]["template"]["spec"]["containers"][0]["image"]
    )


if __name__ == "__main__":
    try:
        main()
    except (
        ValueError,
        KeyError,
        OSError,
        yaml.YAMLError,
        subprocess.CalledProcessError,
    ) as exc:
        print(
            f"Adapter preflight failed ({type(exc).__name__}); credentials and manifest values redacted"
        )
        raise SystemExit(1)

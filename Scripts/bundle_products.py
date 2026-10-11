#!/usr/bin/env python3
"""Reads resource products from the selected Xcode scheme's build description."""

import argparse
import json
import math
import time
from pathlib import Path


def read_json(path):
    with path.open() as file:
        return json.load(file)


def matches_request(request, repository, products, scheme):
    parameters = request.get("parameters", {})
    arena = parameters.get("arenaInfo", {})
    return (
        request.get("configuredTargets") == [{"guid": f"PACKAGE-PRODUCT:{scheme}"}]
        and request.get("buildCommand", {}).get("command") == "build"
        and request.get("containerPath") == str(repository)
        and parameters.get("configurationName") == products.name
        and arena.get("buildProductsPath") == str(products.parent)
    )


def directory_identity(path):
    stat = path.stat()
    return {"device": stat.st_dev, "inode": stat.st_ino, "mtime_ns": stat.st_mtime_ns}


def snapshot_descriptions(derived):
    root = derived / "Build/Intermediates.noindex/XCBuildData"
    entries = {}
    for path in root.glob("*.xcbuilddata"):
        if not path.is_dir() or path.is_symlink():
            raise ValueError("invalid Xcode description directory")
        entries[path.name] = directory_identity(path)
    return {"derived": str(derived), "entries": entries, "captured_ns": time.time_ns()}


def read_snapshot(path, derived, since):
    if not math.isfinite(since) or since < 0:
        raise ValueError("invalid Xcode description invocation start")
    snapshot = read_json(path)
    if not isinstance(snapshot, dict) or snapshot.get("derived") != str(derived):
        raise ValueError("invalid Xcode description snapshot")
    if not isinstance(snapshot.get("entries"), dict):
        raise ValueError("invalid Xcode description snapshot")
    captured = snapshot.get("captured_ns")
    if type(captured) is not int or captured < since * 1_000_000_000 or captured > time.time_ns():
        raise ValueError("stale or invalid Xcode description snapshot")
    if path.stat().st_mtime < since:
        raise ValueError("stale Xcode description snapshot file")
    for name, identity in snapshot["entries"].items():
        if not name.endswith(".xcbuilddata") or Path(name).name != name:
            raise ValueError("invalid Xcode description snapshot name")
        if not isinstance(identity, dict) or set(identity) != {"device", "inode", "mtime_ns"}:
            raise ValueError("invalid Xcode description snapshot identity")
        if any(type(value) is not int or value < 0 for value in identity.values()):
            raise ValueError("invalid Xcode description snapshot identity")
    return snapshot


def select_used_description(snapshot, derived, repository, products, scheme):
    root = derived / "Build/Intermediates.noindex/XCBuildData"
    matches = []
    for path in root.glob("*.xcbuilddata"):
        if not path.is_dir() or path.is_symlink():
            raise ValueError("invalid Xcode description directory")
        identity = directory_identity(path)
        prior = snapshot["entries"].get(path.name)
        if prior is not None and identity == prior:
            continue
        if identity["mtime_ns"] <= snapshot["captured_ns"] or identity["mtime_ns"] > time.time_ns():
            raise ValueError("invalid Xcode description use timestamp")
        if prior is not None and identity["mtime_ns"] <= prior["mtime_ns"]:
            raise ValueError("Xcode description use timestamp did not advance")
        if prior is not None and any(identity[key] != prior[key] for key in ("device", "inode")):
            raise ValueError("Xcode description directory was replaced during the build")
        if matches_request(read_json(path / "build-request.json"), repository, products, scheme):
            matches.append(path)
    if len(matches) != 1:
        raise ValueError("missing or ambiguous current Xcode build description use")
    return matches[0]


def select_description(derived, repository, products, scheme, since=0):
    descriptions = derived / "Build/Intermediates.noindex/XCBuildData"
    matches = []
    for path in descriptions.glob("*.xcbuilddata/build-request.json"):
        if path.stat().st_mtime >= since and matches_request(read_json(path), repository, products, scheme):
            matches.append(path)
    if not matches:
        raise ValueError("no matching Xcode build description for the app scheme")
    newest = max(path.stat().st_mtime_ns for path in matches)
    latest = [path for path in matches if path.stat().st_mtime_ns == newest]
    if len(latest) != 1:
        raise ValueError("ambiguous Xcode build descriptions for the app scheme")
    return latest[0].parent


def bundle_products(description, products, scheme):
    manifest = read_json(description / "manifest.json")
    outputs = [path for command in manifest["commands"].values()
               for path in command.get("outputs", [])]
    if str(products / scheme) not in outputs:
        raise ValueError("the Xcode build description does not produce the app executable")
    bundles = set()
    for output in outputs:
        try:
            name = Path(output).relative_to(products).parts[0]
        except (ValueError, IndexError):
            continue
        if name.endswith(".bundle"):
            if not Path(output).exists():
                raise ValueError(f"required build resource is missing: {Path(output).relative_to(products)}")
            bundles.add(products / name)
    for bundle in bundles:
        if not bundle.is_dir():
            raise ValueError(f"required build resource is missing: {bundle.name}")
    return sorted(bundles)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("derived", "repository", "products", "scheme"):
        parser.add_argument(argument)
    parser.add_argument("--since", type=float, required=True)
    snapshot_mode = parser.add_mutually_exclusive_group()
    snapshot_mode.add_argument("--snapshot-out", type=Path)
    snapshot_mode.add_argument("--snapshot", type=Path)
    arguments = parser.parse_args()
    derived, repository, products = (Path(getattr(arguments, name)).resolve()
                                     for name in ("derived", "repository", "products"))
    try:
        if arguments.snapshot_out:
            arguments.snapshot_out.write_text(json.dumps(snapshot_descriptions(derived)))
            return
        if arguments.snapshot:
            snapshot = read_snapshot(arguments.snapshot, derived, arguments.since)
            description = select_used_description(snapshot, derived, repository, products, arguments.scheme)
        else:
            description = select_description(derived, repository, products, arguments.scheme, arguments.since)
        for bundle in bundle_products(description, products, arguments.scheme):
            print(bundle)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"bundle products: {error}\n")


if __name__ == "__main__":
    main()

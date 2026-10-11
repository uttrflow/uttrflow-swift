#!/usr/bin/env python3
"""Reads resource products from the selected Xcode scheme's build description."""

import argparse
import json
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
    arguments = parser.parse_args()
    derived, repository, products = (Path(getattr(arguments, name)).resolve()
                                     for name in ("derived", "repository", "products"))
    try:
        description = select_description(derived, repository, products, arguments.scheme, arguments.since)
        for bundle in bundle_products(description, products, arguments.scheme):
            print(bundle)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"bundle products: {error}\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Checks every bundled resource file against Resources/DataManifest.json."""

import argparse
import glob
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join("Resources", "DataManifest.json")
ASSET_GLOB = os.path.join("Sources", "*", "Resources")
ORIGINS = ("authored", "generated", "third-party", "unrecorded")
REQUIRED = ("path", "origin", "licence", "redistribution", "sha256", "bytes")
THIRD_PARTY_REQUIRED = ("source", "revision")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def bundled_files(root):
    found = []
    for folder in glob.glob(os.path.join(root, ASSET_GLOB)):
        for parent, _, names in os.walk(folder):
            for name in names:
                if name != ".DS_Store":
                    found.append(os.path.relpath(os.path.join(parent, name), root))
    return sorted(found)


def check(root):
    """Returns (failures, notes): failures fail the gate, notes are reported only."""
    failures, notes = [], []
    try:
        with open(os.path.join(root, MANIFEST), encoding="utf-8") as handle:
            entries = json.load(handle)["assets"]
    except (OSError, ValueError, KeyError) as error:
        return [f"{MANIFEST}: unreadable ({error})"], notes
    listed = {}
    for entry in entries:
        path = entry.get("path", "<no path>")
        if path in listed:
            failures.append(f"{path}: listed twice")
        listed[path] = entry
        missing = [key for key in REQUIRED if key not in entry]
        if entry.get("origin") == "third-party":
            missing += [key for key in THIRD_PARTY_REQUIRED if not entry.get(key)]
        if missing:
            failures.append(f"{path}: missing {', '.join(missing)}")
        if entry.get("origin") not in ORIGINS:
            failures.append(f"{path}: origin must be one of {', '.join(ORIGINS)}")
        if entry.get("origin") == "unrecorded":
            notes.append(f"{path}: origin unrecorded, owner to confirm source and licence")
    on_disk = bundled_files(root)
    for path in on_disk:
        entry = listed.get(path)
        if entry is None:
            failures.append(f"{path}: bundled but not in {MANIFEST}")
            continue
        full = os.path.join(root, path)
        if entry.get("bytes") != os.path.getsize(full) or entry.get("sha256") != digest(full):
            failures.append(f"{path}: size or SHA-256 differs from {MANIFEST}")
    for path in sorted(set(listed) - set(on_disk)):
        failures.append(f"{path}: in {MANIFEST} but not bundled")
    return failures, notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=ROOT)
    args = parser.parse_args()
    failures, notes = check(args.root)
    for note in notes:
        print(f"note: {note}")
    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    if failures:
        print(f"data manifest: {len(failures)} problem(s); see Docs/data-manifest.md", file=sys.stderr)
        return 1
    print(f"data manifest: every bundled file listed and matching ({len(notes)} unrecorded)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

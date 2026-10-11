#!/usr/bin/env python3
"""Registers and verifies the optional Google Sign-In artwork against its published archive."""

import argparse
import json
import os

import data_manifest

MARK_PATH = data_manifest.MARK_PATH
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = "Resources/DataManifest.json"


def registered(root):
    with open(os.path.join(root, MANIFEST), encoding="utf-8") as handle:
        entries = json.load(handle)["assets"]
    matches = [entry for entry in entries if entry.get("path") == MARK_PATH]
    if len(matches) != 1 or matches[0].get("optional") is not True:
        raise ValueError("the optional Google mark must have exactly one registered manifest entry")
    problems = data_manifest.provider_metadata_problems(matches[0])
    if problems:
        raise ValueError("; ".join(problems))
    return matches[0]


def register(root, archive, mark):
    entry = {"path": MARK_PATH, "origin": "third-party", "source": data_manifest.MARK_SOURCE,
             "revision": "sha256:" + data_manifest.digest(archive), "licence": data_manifest.MARK_LICENCE,
             "redistribution": True, "producedBy": data_manifest.MARK_PRODUCED_BY, "optional": True,
             "sha256": data_manifest.digest(mark), "bytes": os.path.getsize(mark)}
    path = os.path.join(root, MANIFEST)
    with open(path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    manifest["assets"] = [item for item in manifest["assets"] if item.get("path") != MARK_PATH]
    manifest["assets"].append(entry)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("register", "verify-archive", "verify-mark"))
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--archive")
    parser.add_argument("--mark")
    args = parser.parse_args()
    try:
        if args.command == "register":
            if not args.archive or not args.mark:
                raise ValueError("registration needs --archive and --mark")
            register(args.root, args.archive, args.mark)
        else:
            entry = registered(args.root)
            if args.command == "verify-archive":
                if not args.archive or "sha256:" + data_manifest.digest(args.archive) != entry["revision"]:
                    raise ValueError("Google artwork archive differs from its registered SHA-256")
            else:
                mark = args.mark or os.path.join(args.root, MARK_PATH)
                if data_manifest.digest(mark) != entry["sha256"] or os.path.getsize(mark) != entry["bytes"]:
                    raise ValueError("Google mark differs from its registered SHA-256 or size")
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"provider mark: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

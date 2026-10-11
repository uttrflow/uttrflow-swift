#!/usr/bin/env python3
"""Registers and verifies the optional Google Sign-In artwork against its published archive."""

import argparse
import hashlib
import json
import os
import re

MARK_PATH = "Sources/Uttrflow/Resources/GoogleG.png"
SOURCE = "https://developers.google.com/static/identity/images/signin-assets.zip"
LICENCE = "LicenseRef-GoogleSignInBranding"
PRODUCED_BY = "Scripts/select-google-mark.sh and Scripts/lift-google-mark.swift"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = "Resources/DataManifest.json"


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def metadata_problems(entry):
    problems = []
    expected = {"path": MARK_PATH, "origin": "third-party", "source": SOURCE,
                "licence": LICENCE, "redistribution": True, "producedBy": PRODUCED_BY}
    for key, value in expected.items():
        if entry.get(key) != value:
            problems.append(f"optional provider artwork requires {key} {value}")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(entry.get("revision", ""))):
        problems.append("optional provider artwork requires its archive SHA-256 revision")
    if not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))):
        problems.append("optional provider artwork requires its output SHA-256")
    if type(entry.get("bytes")) is not int or entry["bytes"] <= 0:
        problems.append("optional provider artwork requires a positive output size")
    return problems


def registered(root):
    with open(os.path.join(root, MANIFEST), encoding="utf-8") as handle:
        entries = json.load(handle)["assets"]
    matches = [entry for entry in entries if entry.get("path") == MARK_PATH]
    if len(matches) != 1 or matches[0].get("optional") is not True:
        raise ValueError("the optional Google mark must have exactly one registered manifest entry")
    problems = metadata_problems(matches[0])
    if problems:
        raise ValueError("; ".join(problems))
    return matches[0]


def register(root, archive, mark):
    entry = {"path": MARK_PATH, "origin": "third-party", "source": SOURCE,
             "revision": "sha256:" + digest(archive), "licence": LICENCE,
             "redistribution": True, "producedBy": PRODUCED_BY, "optional": True,
             "sha256": digest(mark), "bytes": os.path.getsize(mark)}
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
                if not args.archive or "sha256:" + digest(args.archive) != entry["revision"]:
                    raise ValueError("Google artwork archive differs from its registered SHA-256")
            else:
                mark = args.mark or os.path.join(args.root, MARK_PATH)
                if digest(mark) != entry["sha256"] or os.path.getsize(mark) != entry["bytes"]:
                    raise ValueError("Google mark differs from its registered SHA-256 or size")
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"provider mark: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Checks every bundled resource file against Resources/DataManifest.json."""

import argparse
import glob
import hashlib
import json
import os
import sys

import provider_mark

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join("Resources", "DataManifest.json")
ASSET_GLOB = os.path.join("Sources", "*", "Resources")
# Kept in step with ALLOWED_DIRECTORY in audio_audit.py: the only audio the tree may hold, each a synthesised take.
SYNTHETIC_AUDIO = os.path.join("Tests", "Fixtures", "SyntheticAudio")
ORIGINS = ("authored", "generated", "third-party", "unrecorded")
REQUIRED = ("path", "origin", "licence", "redistribution", "sha256", "bytes")
THIRD_PARTY_REQUIRED = ("source", "revision")
RECIPE_REQUIRED = ("fitToolRevision", "featureSpecVersion", "inputs", "seeds", "engine", "command")
INPUT_WHERE = ("tree", "cache")


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def recipe_problems(entry):
    """What is wrong with an entry's fit recipe; an empty list when it has none or it is whole."""
    recipe = entry.get("recipe")
    if recipe is None:
        return []
    if not isinstance(recipe, dict):
        return ["recipe must be an object"]
    problems = [f"recipe missing {key}" for key in RECIPE_REQUIRED if key not in recipe]
    for key in ("fitToolRevision", "featureSpecVersion", "engine"):
        if key in recipe and (not isinstance(recipe[key], str) or not recipe[key]):
            problems.append(f"recipe {key} must be a non-empty string")
    seeds = recipe.get("seeds")
    if "seeds" in recipe and (not isinstance(seeds, list) or any(type(seed) is not int for seed in seeds)):
        problems.append("recipe seeds must be a list of whole numbers")
    command = recipe.get("command")
    if "command" in recipe and (not isinstance(command, list) or not command or not all(isinstance(part, str) for part in command)):
        problems.append("recipe command must be a non-empty list of strings")
    inputs = recipe.get("inputs")
    if "inputs" in recipe:
        if not isinstance(inputs, list):
            problems.append("recipe inputs must be a list")
        else:
            for item in inputs:
                if not isinstance(item, dict) or not item.get("path") or not item.get("sha256") or item.get("where") not in INPUT_WHERE:
                    problems.append(f"recipe input needs path, sha256 and where ({', '.join(INPUT_WHERE)})")
    return problems


def bundled_files(root):
    found = []
    for folder in glob.glob(os.path.join(root, ASSET_GLOB)) + glob.glob(os.path.join(root, SYNTHETIC_AUDIO)):
        for parent, _, names in os.walk(folder):
            for name in names:
                if name != ".DS_Store":
                    found.append(os.path.relpath(os.path.join(parent, name), root))
    return sorted(found)


def update(root):
    """Refresh digest and size for manifest entries whose files are bundled."""
    manifest_path = os.path.join(root, MANIFEST)
    try:
        with open(manifest_path, encoding="utf-8") as handle:
            manifest = json.load(handle)
        entries = manifest["assets"]
    except (OSError, ValueError, KeyError) as error:
        return 0, [f"{MANIFEST}: unreadable ({error})"]

    bundled = set(bundled_files(root))
    changed = 0
    for entry in entries:
        path = entry.get("path")
        if path not in bundled or entry.get("optional") is True:
            continue
        full_path = os.path.join(root, path)
        values = {"sha256": digest(full_path), "bytes": os.path.getsize(full_path)}
        if any(entry.get(key) != value for key, value in values.items()):
            entry.update(values)
            changed += 1

    if changed:
        try:
            with open(manifest_path, "w", encoding="utf-8") as handle:
                json.dump(manifest, handle, indent=2)
                handle.write("\n")
        except OSError as error:
            return 0, [f"{MANIFEST}: could not write ({error})"]
    return changed, []


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
        if "optional" in entry and type(entry["optional"]) is not bool:
            failures.append(f"{path}: optional must be a boolean")
        if entry.get("optional") is True:
            failures.extend(f"{path}: {problem}" for problem in provider_mark.metadata_problems(entry))
        missing = [key for key in REQUIRED if key not in entry]
        if entry.get("origin") == "third-party":
            missing += [key for key in THIRD_PARTY_REQUIRED if not entry.get(key)]
        if missing:
            failures.append(f"{path}: missing {', '.join(missing)}")
        if entry.get("origin") not in ORIGINS:
            failures.append(f"{path}: origin must be one of {', '.join(ORIGINS)}")
        if path.startswith(SYNTHETIC_AUDIO + os.sep) and (entry.get("origin") != "generated" or not entry.get("voice")):
            failures.append(f"{path}: a fixture take needs origin generated and the synthesiser's voice")
        budget = entry.get("budgetBytes")
        if budget is not None and (type(budget) is not int or budget <= 0):
            failures.append(f"{path}: budgetBytes must be a positive whole number of bytes")
        failures.extend(f"{path}: {problem}" for problem in recipe_problems(entry))
        if entry.get("origin") == "unrecorded":
            notes.append(f"{path}: origin unrecorded, owner to confirm source and licence")
    on_disk = bundled_files(root)
    for path in on_disk:
        entry = listed.get(path)
        if entry is None:
            failures.append(f"{path}: bundled but not in {MANIFEST}")
            continue
        full = os.path.join(root, path)
        size, sha256 = os.path.getsize(full), digest(full)
        if entry.get("bytes") != size or entry.get("sha256") != sha256:
            failures.append(f"{path}: size or SHA-256 differs from {MANIFEST}; "
                            f"if the change is meant, update its entry to bytes {size}, sha256 {sha256}")
        budget = entry.get("budgetBytes")
        if type(budget) is int and size > budget:
            failures.append(f"{path}: {size:,} bytes, over its budgetBytes of {budget:,}")
    for path in sorted(set(listed) - set(on_disk)):
        if listed[path].get("optional") is not True or provider_mark.metadata_problems(listed[path]):
            failures.append(f"{path}: in {MANIFEST} but not bundled")
    return failures, notes


def budgeted(root):
    """Each bundled file whose entry sets budgetBytes, as (path, bytes on disk, budget)."""
    try:
        with open(os.path.join(root, MANIFEST), encoding="utf-8") as handle:
            entries = json.load(handle)["assets"]
    except (OSError, ValueError, KeyError):
        return []
    return [(entry["path"], os.path.getsize(os.path.join(root, entry["path"])), entry["budgetBytes"])
            for entry in entries
            if type(entry.get("budgetBytes")) is int and os.path.isfile(os.path.join(root, entry.get("path", "")))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=ROOT)
    parser.add_argument(
        "--update",
        action="store_true",
        help="refresh sha256 and bytes for existing entries whose files are bundled",
    )
    args = parser.parse_args()
    if args.update:
        changed, errors = update(args.root)
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        if errors:
            return 1
        print(f"data manifest: updated {changed} existing entries")
    failures, notes = check(args.root)
    for path, size, budget in budgeted(args.root):
        print(f"size: {path} {size:,} bytes of a {budget:,} budget")
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

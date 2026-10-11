#!/usr/bin/env python3
"""Rebuilds every fitted asset a tag shipped from its manifest recipe and compares digests; never tags."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

import data_manifest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)


def file_digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def reproduce_entry(entry, repo, tree, cache):
    """Returns a list of problems; empty when the recipe rebuilds the manifest's bytes."""
    path, recipe = entry["path"], entry["recipe"]
    problems = data_manifest.recipe_problems(entry)
    if problems:
        return problems
    if git(repo, "cat-file", "-e", recipe["fitToolRevision"] + "^{commit}").returncode != 0:
        return [f"fit tool revision {recipe['fitToolRevision']} is not a commit in this repository"]
    for item in recipe["inputs"]:
        base = tree if item["where"] == "tree" else cache
        if base is None:
            return [f"input {item['path']} is in the cache and no --cache was given"]
        location = os.path.join(base, item["path"])
        if not os.path.isfile(location):
            return [f"input {item['path']} is missing from the {item['where']}"]
        if file_digest(location) != item["sha256"]:
            return [f"input {item['path']} differs from the digest the recipe recorded"]
    output = os.path.join(tree, path)
    if os.path.exists(output):
        os.remove(output)
    env = dict(os.environ, RECIPE_SEEDS=",".join(str(seed) for seed in recipe["seeds"]),
               RECIPE_OUTPUT=path, RECIPE_ENGINE=recipe["engine"], RECIPE_SPEC=recipe["featureSpecVersion"],
               RECIPE_CACHE=cache or "")
    ran = subprocess.run(recipe["command"], cwd=tree, env=env, capture_output=True, text=True)
    if ran.returncode != 0:
        return [f"command exited {ran.returncode}: {(ran.stderr or ran.stdout).strip()[-300:]}"]
    if not os.path.isfile(output):
        return ["command did not write the asset"]
    built = file_digest(output)
    if built != entry["sha256"]:
        return [f"rebuilt sha256 {built} differs from the manifest's {entry['sha256']}"]
    return []


def reproduce(repo, tag, cache):
    """Builds in a scratch worktree at the tag. Returns (lines, failed)."""
    scratch = tempfile.mkdtemp(prefix="reproduce-assets-")
    tree = os.path.join(scratch, "tree")
    added = git(repo, "worktree", "add", "--detach", tree, tag)
    if added.returncode != 0:
        shutil.rmtree(scratch, ignore_errors=True)
        return [f"cannot check out {tag}: {added.stderr.strip()}"], True
    try:
        with open(os.path.join(tree, data_manifest.MANIFEST), encoding="utf-8") as handle:
            entries = json.load(handle)["assets"]
        lines, failed = [f"reproduce-assets {tag}"], False
        fitted = [entry for entry in entries if "recipe" in entry]
        for entry in fitted:
            problems = reproduce_entry(entry, repo, tree, cache)
            failed = failed or bool(problems)
            lines.append(f"{'FAIL' if problems else 'ok  '} {entry['path']}")
            lines.extend(f"     {problem}" for problem in problems)
        lines.append(f"{len(fitted)} fitted asset(s), {'FAILED' if failed else 'every digest matches'}")
        return lines, failed
    finally:
        git(repo, "worktree", "remove", "--force", tree)
        shutil.rmtree(scratch, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--cache", help="folder outside the repository holding the pinned source archives")
    args = parser.parse_args()
    lines, failed = reproduce(args.root, args.tag, args.cache)
    print("\n".join(lines))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

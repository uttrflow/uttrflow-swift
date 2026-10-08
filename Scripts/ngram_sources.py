#!/usr/bin/env python3
"""Checks the pinned build-source manifest, and verifies a snapshot cache against it before a build."""

import argparse
import hashlib
import json
import os
import re
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join("Resources", "NgramSources.json")
ALLOWED_LICENCES = ("MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "PSF-2.0", "CC0-1.0")
REQUIRED = ("name", "kind", "publisher", "url", "revision", "licence", "archive", "sha256", "fetched")
# A text source feeds a count table; a lexicon ships its own entries, so it carries the licence notice.
KINDS = ("text", "lexicon")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
USER_DATA = os.path.join("Library", "Application Support")


def digest(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(block)
    return hasher.hexdigest()


def load(root):
    with open(os.path.join(root, MANIFEST), encoding="utf-8") as handle:
        return json.load(handle)["sources"]


def check_entries(sources, root=ROOT):
    """Returns the failures in the manifest itself."""
    failures, archives = [], set()
    for entry in sources:
        name = entry.get("name", "<no name>")
        missing = [key for key in REQUIRED if not entry.get(key)]
        if missing:
            failures.append(f"{name}: missing {', '.join(missing)}")
        if entry.get("licence") not in ALLOWED_LICENCES:
            failures.append(f"{name}: licence {entry.get('licence')} is not in the allowlist")
        if not SHA256.match(str(entry.get("sha256", ""))):
            failures.append(f"{name}: sha256 is not 64 lower-case hex digits")
        if not DATE.match(str(entry.get("fetched", ""))):
            failures.append(f"{name}: fetched is not YYYY-MM-DD")
        archive = entry.get("archive", "")
        if os.path.basename(archive) != archive or archive in archives:
            failures.append(f"{name}: archive must be a unique bare file name")
        archives.add(archive)
        if entry.get("kind") not in KINDS:
            failures.append(f"{name}: kind must be one of {', '.join(KINDS)}")
        if entry.get("kind") == "lexicon":
            notice = entry.get("notice")
            if not notice or not entry.get("noticeInArchive"):
                failures.append(f"{name}: a lexicon needs notice and noticeInArchive")
            elif not os.path.isfile(os.path.join(root, notice)):
                failures.append(f"{name}: notice {notice} is not in the repository")
    return failures


def cache_refusal(cache, root):
    """Why a snapshot cache may not be used, or None: it is the user's data, or inside the repository."""
    real, tree = os.path.realpath(cache), os.path.realpath(root)
    if USER_DATA in real:
        return f"{cache}: the build never reads user data; use a cache outside Application Support"
    if os.path.commonpath([real, tree]) == tree:
        return f"{cache}: a pinned archive never sits in the repository; use a cache outside it"
    return None


def check_notice(entry, cache, root):
    """Returns a failure when the licence text in the archive differs from the tracked notice."""
    try:
        with tarfile.open(os.path.join(cache, entry["archive"])) as archive:
            member = archive.extractfile(entry["noticeInArchive"])
            shipped = member.read() if member else None
        with open(os.path.join(root, entry["notice"]), "rb") as handle:
            tracked = handle.read()
    except (OSError, KeyError, tarfile.TarError) as error:
        return [f"{entry['archive']}: notice unreadable ({error})"]
    if shipped != tracked:
        return [f"{entry['archive']}: licence text differs from {entry['notice']}"]
    return []


def check_cache(sources, cache, root=ROOT):
    """Returns the failures in a snapshot cache: an unlisted, missing or changed archive."""
    refusal = cache_refusal(cache, root)
    if refusal:
        return [refusal]
    failures = []
    listed = {entry.get("archive"): entry for entry in sources}
    present = sorted(name for name in os.listdir(cache) if name != ".DS_Store")
    for name in present:
        entry = listed.get(name)
        if entry is None:
            failures.append(f"{name}: in the cache but not in {MANIFEST}")
        elif digest(os.path.join(cache, name)) != entry.get("sha256"):
            failures.append(f"{name}: SHA-256 differs from {MANIFEST}")
        elif entry.get("kind") == "lexicon":
            failures += check_notice(entry, cache, root)
    for name in sorted(set(listed) - set(present)):
        failures.append(f"{name}: in {MANIFEST} but not in the cache")
    return failures


def fetch(sources, cache, opener=urllib.request.urlopen, root=ROOT):
    """Downloads each listed archive missing from the cache once, keeping it only if its digest matches."""
    refusal = cache_refusal(cache, root)
    if refusal:
        return [refusal]
    os.makedirs(cache, exist_ok=True)
    failures = []
    for entry in sources:
        target = os.path.join(cache, entry["archive"])
        if os.path.exists(target):
            continue
        partial = target + ".partial"
        with opener(entry["url"]) as response, open(partial, "wb") as handle:
            for block in iter(lambda: response.read(1 << 20), b""):
                handle.write(block)
        if digest(partial) != entry["sha256"]:
            os.remove(partial)
            failures.append(f"{entry['archive']}: downloaded archive differs from {MANIFEST}")
        else:
            os.rename(partial, target)
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--cache", help="snapshot folder to verify before a build reads it")
    parser.add_argument("--fetch", action="store_true", help="download missing archives into --cache first")
    args = parser.parse_args()
    try:
        sources = load(args.root)
    except (OSError, ValueError, KeyError) as error:
        print(f"error: {MANIFEST}: unreadable ({error})", file=sys.stderr)
        return 1
    failures = check_entries(sources, args.root)
    if args.fetch and args.cache and not failures:
        failures = fetch(sources, args.cache, root=args.root)
    if args.cache and not failures:
        failures = check_cache(sources, args.cache, args.root)
    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    if failures:
        print(f"ngram sources: {len(failures)} problem(s); see Docs/ngram-sources.md", file=sys.stderr)
        return 1
    print(f"ngram sources: {len(sources)} source(s) listed and valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())

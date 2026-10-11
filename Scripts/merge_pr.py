#!/usr/bin/env python3
"""Squash an already-authorized PR with an explicit audited message; grants no merge permission.

This prevents default squash metadata, not historical violations. Run the focused checks and
review first; this helper does not decide whether administrative bypass is authorized.
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

AUDIT = Path(__file__).with_name("disclosure_audit.py")
SHA = re.compile(r"[0-9a-f]{40}")
REPOSITORY = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")


def gh(*arguments):
    """Use the caller's authenticated CLI without a shell or implicit merge defaults."""
    return subprocess.run(
        ["gh", *arguments], check=True, capture_output=True, text=True).stdout


def audit(message, label):
    """Apply the existing strict text gate to the complete commit message."""
    result = subprocess.run(
        [sys.executable, str(AUDIT), "--text", "--label", label],
        input=message, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{label} failed the disclosure gate")


def view(number, repository):
    """Read the live PR state and exact head before and after mutation."""
    return json.loads(gh(
        "pr", "view", str(number), "--repo", repository, "--json",
        "state,isDraft,baseRefName,headRefOid,mergeCommit"))


def merge(number, repository, expected_head, subject, body_path):
    """Freeze the reviewed message, guard the live head, and verify the server result."""
    if not SHA.fullmatch(expected_head) or expected_head == "0" * 40:
        raise ValueError("expected head must be a complete nonzero SHA")
    if not REPOSITORY.fullmatch(repository):
        raise ValueError("repository must be owner/name")
    if not subject.strip() or "\n" in subject or "\r" in subject:
        raise ValueError("subject must be one nonempty line")
    body = Path(body_path).read_text(encoding="utf-8")
    if not body.strip():
        raise ValueError("an explicit nonempty body is required")
    audit(subject + "\n\n" + body, "prospective squash message")
    before = view(number, repository)
    if before["state"] != "OPEN" or before["isDraft"] or before["baseRefName"] != "main":
        raise ValueError("PR must be open, nondraft, and target main")
    if before["headRefOid"] != expected_head:
        raise ValueError("live PR head differs from expected head")
    with tempfile.TemporaryDirectory(prefix="uttrflow-merge-message-") as directory:
        frozen = Path(directory) / "body.txt"
        frozen.write_text(body, encoding="utf-8")
        gh("pr", "merge", str(number), "--repo", repository, "--squash", "--admin",
           "--match-head-commit", expected_head, "--subject", subject, "--body-file", str(frozen))
    # A post-merge failure reports an already performed mutation; never retry it automatically.
    try:
        after = view(number, repository)
        commit = (after.get("mergeCommit") or {}).get("oid", "")
        if (after["state"] != "MERGED" or after["headRefOid"] != expected_head
                or not SHA.fullmatch(commit)):
            raise ValueError("server did not confirm the expected merged head and commit")
        actual = json.loads(gh("api", f"repos/{repository}/git/commits/{commit}"))
        if actual["sha"] != commit:
            raise ValueError("returned commit differs from the PR merge commit")
        audit(actual["message"], "actual squash message")
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise ValueError("merge command succeeded but post-merge verification failed; inspect the PR") from error
    return commit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("number", type=int)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body-file", type=Path, required=True)
    arguments = parser.parse_args()
    if arguments.number < 1:
        parser.error("PR number must be positive")
    try:
        commit = merge(arguments.number, arguments.repo, arguments.expected_head,
                       arguments.subject, arguments.body_file)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"merge guard: {error}", file=sys.stderr)
        return 1
    print(f"Merged PR #{arguments.number}; verified squash message at {commit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Prints one version's section of CHANGELOG.md, for a release's notes.

The release notes on a tag and the changelog entry for the same version are the same
prose, and keeping them the same by hand means they drift the moment one is edited. This
reads the entry rather than restating it, so there is one place the wording lives.

    ./Scripts/changelog.py 0.5.0            the section under `## [0.5.0]`
    ./Scripts/changelog.py 0.5.0 --check    say whether it is there, print nothing

A version with no section is an error rather than an empty release: a release named after
a version the changelog does not describe is the drift this avoids, arriving by another
route.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def section(text: str, version: str) -> str | None:
    """Returns the body under `## [version]`, without the heading, or None."""
    # The heading carries a date the caller does not know, so only the version is matched.
    heading = re.compile(r"^## \[" + re.escape(version) + r"\]", re.MULTILINE)
    start = heading.search(text)
    if start is None:
        return None
    rest = text[start.end():]
    # The next `## ` heading ends the section; the link definitions at the foot end the last one.
    end = re.search(r"^(## |\[[^\]]+\]: )", rest, re.MULTILINE)
    body = rest[: end.start()] if end else rest
    # The first line is the remainder of the heading, which the release's title already says.
    return body.split("\n", 1)[1].strip() if "\n" in body else ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Print one version's changelog section.")
    parser.add_argument("version", help="the version, without a leading v")
    parser.add_argument("--check", action="store_true", help="report presence, print nothing")
    args = parser.parse_args()

    path = ROOT / "CHANGELOG.md"
    body = section(path.read_text(encoding="utf-8"), args.version)
    if not body:
        print(
            f"error: CHANGELOG.md has no section for {args.version}.\n"
            f"  Add `## [{args.version}] — <date>` before tagging; RELEASING.md step two.",
            file=sys.stderr,
        )
        return 1
    if not args.check:
        print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())

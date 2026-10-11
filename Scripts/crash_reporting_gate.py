#!/usr/bin/env python3
"""Require crash-report configuration at distribution boundaries without disclosing it."""

import argparse
import os
from pathlib import Path
import plistlib
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    environment = commands.add_parser("environment")
    environment.add_argument("mode")
    artifact = commands.add_parser("plist")
    artifact.add_argument("path", type=Path)
    args = parser.parse_args()
    if args.command == "environment":
        if args.mode != "distribution":
            return 0
        value = os.environ.get("SENTRY_DSN")
        error = "distribution mode needs a nonblank SENTRY_DSN"
    else:
        try:
            with args.path.open("rb") as source:
                values = plistlib.load(source)
            value = values.get("SentryDSN") if isinstance(values, dict) else None
        except (OSError, ValueError, plistlib.InvalidFileException):
            print("error: could not read crash-report configuration from the image", file=sys.stderr)
            return 1
        error = "the image needs a nonblank SentryDSN; rebuild with SENTRY_DSN configured"
    if not isinstance(value, str) or not value.strip():
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Validates the Sparkle feed a bundle or release artifact carries."""

import argparse
import base64
import binascii
import plistlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ElementTree


class FeedError(ValueError):
    """A feed URL or updater plist cannot be shipped."""


def classify(url):
    """Returns 'https' or 'local' for an accepted feed URL, or raises FeedError."""
    parsed = urllib.parse.urlparse(url)
    try:
        host = parsed.hostname
    except ValueError as error:
        raise FeedError(f"SUFeedURL is not a valid URL: {url}") from error

    if parsed.scheme == "https" and host:
        return "https"
    if parsed.scheme == "http" and host in {"127.0.0.1", "localhost", "::1"}:
        return "local"
    raise FeedError(f"SUFeedURL is neither https nor a loopback address: {url}")


def is_public_key(key):
    """Returns whether key is base64 for a 32-byte Ed25519 public key that is not all zeros."""
    if not isinstance(key, str):
        return False
    try:
        raw = base64.b64decode(key, validate=True)
    except (binascii.Error, ValueError):
        return False
    return len(raw) == 32 and any(raw)


def check_plist(path, forbid_local=False):
    """Validates the updater keys in an Info.plist, returning the feed kind or 'absent'."""
    with open(path, "rb") as handle:
        info = plistlib.load(handle)
    feed = info.get("SUFeedURL")
    if not feed:
        return "absent"

    kind = classify(feed)
    if forbid_local and kind == "local":
        raise FeedError(f"release artifacts must not use a loopback update feed: {feed}")

    key = info.get("SUPublicEDKey", "")
    if not is_public_key(key):
        raise FeedError("SUFeedURL is set and SUPublicEDKey is not a key")
    if info.get("SUVerifyUpdateBeforeExtraction") is not True:
        raise FeedError("SUFeedURL is set and SUVerifyUpdateBeforeExtraction is not true")
    return kind


SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def appcast_versions(path):
    """Returns (shortVersionString, version) of the one item in an appcast, or raises FeedError."""
    try:
        items = ElementTree.parse(path).getroot().findall("./channel/item")
    except (ElementTree.ParseError, OSError) as error:
        raise FeedError(f"{path} is not a readable appcast: {error}") from error
    if len(items) != 1:
        raise FeedError(f"{path} carries {len(items)} items; an appcast carries exactly one")
    short = items[0].findtext(f"{SPARKLE}shortVersionString", "")
    build = items[0].findtext(f"{SPARKLE}version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", short) or not build.isdigit():
        raise FeedError(f"{path} has version {short!r} build {build!r}; a full release is N.N.N with an integer build")
    return short, build


def check_order(broken, patch):
    """Raises FeedError unless the patch appcast sorts strictly above the broken one."""
    broken_short, broken_build = appcast_versions(broken)
    patch_short, patch_build = appcast_versions(patch)
    if int(patch_build) <= int(broken_build):
        raise FeedError(f"patch build {patch_build} does not rise above {broken_build}, so Sparkle would not offer it")
    if tuple(map(int, patch_short.split("."))) <= tuple(map(int, broken_short.split("."))):
        raise FeedError(f"patch version {patch_short} does not sort above {broken_short}")
    return f"{patch_short} ({patch_build}) above {broken_short} ({broken_build})"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    classify_command = subcommands.add_parser("classify", help="classify one feed URL")
    classify_command.add_argument("url")

    key_command = subcommands.add_parser("check-key", help="check one SUPublicEDKey value")
    key_command.add_argument("key")

    plist_command = subcommands.add_parser("check-plist", help="check updater keys in an Info.plist")
    plist_command.add_argument("plist")
    plist_command.add_argument("--forbid-local", action="store_true")

    order_command = subcommands.add_parser("check-order", help="check a patch appcast sorts above a broken one")
    order_command.add_argument("broken")
    order_command.add_argument("patch")

    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "classify":
            print(classify(arguments.url))
        elif arguments.command == "check-key":
            if not is_public_key(arguments.key):
                raise FeedError("SUPublicEDKey is not a key")
            print("key")
        elif arguments.command == "check-order":
            print(check_order(arguments.broken, arguments.patch))
        else:
            print(check_plist(arguments.plist, forbid_local=arguments.forbid_local))
    except FeedError as error:
        print(f"update_feed_gate.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

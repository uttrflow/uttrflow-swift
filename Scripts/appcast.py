#!/usr/bin/env python3
"""Writes the appcast a released build is advertised by.

Its own file rather than a heredoc inside `publish.sh`, because it is XML with quoting
rules of its own and a shell heredoc is the wrong place to reason about escaping — and
because the one thing that must never be mangled is in here: the enclosure's signature.

Called by `Scripts/publish.sh` with everything it needs in the environment. See
`Docs/releasing.md` ("Updating") for how the whole path fits together, and `internal/api/updates.go` in
uttrflow-backend for why the app asks our own API for this file rather than asking GitHub.
"""

import datetime
import os
import re
import pathlib
import sys
from xml.sax.saxutils import escape

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: appcast.py <path>", file=sys.stderr)
        return 2

    try:
        version = os.environ["VERSION"]
        build = os.environ["BUILD"]
        archive = os.environ["ARCHIVE_NAME"]
        size = os.environ["ARCHIVE_SIZE"]
        signature = os.environ["SIGNATURE"].strip()
        repository = os.environ["REPO"]
        notes = os.environ["NOTES_URL"]
        minimum = os.environ["MINIMUM_SYSTEM"]
    except KeyError as missing:
        print(f"appcast.py: {missing} is not set", file=sys.stderr)
        return 1

    # sign_update prints both attributes an enclosure needs — the signature and the
    # length — ready to paste. Only the signature is taken: emitting its length too put
    # `length` in the tag twice, which is malformed and which no reader complains about
    # in a way anybody would notice. The length below comes from the file on disk, which
    # is the one authority for how big it is.
    signature_value = re.search(r'sparkle:edSignature="([^"]+)"', signature)
    signed_length = re.search(r'length="(\d+)"', signature)
    if signature_value is None or signed_length is None:
        print("appcast.py: SIGNATURE is not what sign_update produces", file=sys.stderr)
        return 1

    # The two must describe the same file. They can only disagree if the archive was
    # rebuilt between signing and here, which would ship a signature for bytes nobody
    # will download — and Sparkle would reject the update with a message about a
    # corrupt archive rather than about a stale build.
    if signed_length.group(1) != size:
        print(
            f"appcast.py: signed {signed_length.group(1)} bytes but the archive is {size}",
            file=sys.stderr,
        )
        return 1

    # The constant address, as latest.json uses for the disk image: it is the one that
    # goes on working when the next version lands.
    url = f"https://github.com/{repository}/releases/latest/download/{archive}"
    published = datetime.datetime.now(datetime.UTC).strftime("%a, %d %b %Y %H:%M:%S +0000")

    appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="{SPARKLE}">
  <channel>
    <title>Uttrflow</title>
    <link>https://uttrflow.com</link>
    <description>Updates for Uttrflow.</description>
    <language>en</language>
    <item>
      <title>{escape(version)}</title>
      <pubDate>{published}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(minimum)}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{escape(notes)}</sparkle:releaseNotesLink>
      <enclosure url="{escape(url)}" type="application/octet-stream" length="{escape(size)}" sparkle:edSignature="{escape(signature_value.group(1))}" />
    </item>
  </channel>
</rss>
"""
    pathlib.Path(sys.argv[1]).write_text(appcast)
    print(f"  appcast      {version} ({build}), {size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Refuses a tracked or untracked-but-not-ignored audio file outside the synthetic fixture directory.

A voice recording is biometric personal data, and every other gate reads text, so a recorded take
would pass them all. A file is audio when its extension says so or its first bytes do, so renaming
a WAV to `.bin` does not hide it.

Usage:  python3 Scripts/audio_audit.py             (belongs in `make verify`)
        python3 Scripts/audio_audit.py --self-test   also proves extension and magic bytes are caught
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent

ALLOWED_DIRECTORY = "Tests/Fixtures/SyntheticAudio/"

AUDIO_EXTENSIONS = {".wav", ".wave", ".flac", ".m4a", ".mp3", ".opus", ".ogg", ".caf", ".aif", ".aiff"}

HEADER_BYTES = 12


def has_audio_magic(head):
    """Returns whether the first bytes of a file are a known audio container header."""
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return True
    if head[:4] == b"FORM" and head[8:12] in (b"AIFF", b"AIFC"):
        return True
    if head[:4] in (b"fLaC", b"caff", b"OggS"):
        return True
    if head[:3] == b"ID3" or (len(head) >= 2 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0):
        return True
    return head[4:8] == b"ftyp" and head[8:11] == b"M4A"


def is_audio(path):
    """Returns whether a path is audio by its extension or by its header."""
    if path.suffix.lower() in AUDIO_EXTENSIONS:
        return True
    try:
        with path.open("rb") as handle:
            return has_audio_magic(handle.read(HEADER_BYTES))
    except (IsADirectoryError, FileNotFoundError):
        return False


def stray_audio_files(root):
    """Returns the listed audio files that sit outside the allowed directory."""
    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.split("\0")
    return sorted(
        path for path in listed
        if path and not path.startswith(ALLOWED_DIRECTORY) and is_audio(Path(root) / path)
    )


def self_test():
    """Proves the audit passes text and allowed fixtures and fails audio found either way."""
    print("audio_audit self-test")
    wav_header = b"RIFF\x24\x00\x00\x00WAVEfmt "
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        subprocess.run(["git", "init", "-q", scratch], check=True)
        (root / "README.md").write_text("ok")
        (root / ALLOWED_DIRECTORY).mkdir(parents=True)
        (root / ALLOWED_DIRECTORY / "hello.wav").write_bytes(wav_header)
        assert stray_audio_files(root) == [], "text and the allowed directory must pass"
        (root / "take.wav").write_bytes(b"")
        (root / "notes.bin").write_bytes(wav_header)
        (root / "song.txt").write_bytes(b"ID3\x04\x00")
        found = stray_audio_files(root)
        assert found == ["notes.bin", "song.txt", "take.wav"], f"audio must be caught, got {found}"
    print("ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    strays = stray_audio_files(PACKAGE_ROOT)
    if strays:
        print("audio_audit: audio outside " + ALLOWED_DIRECTORY + ":", file=sys.stderr)
        for name in strays:
            print(f"  {name}", file=sys.stderr)
        print("  A recording is personal data: delete it, or add a synthesised take under "
              + ALLOWED_DIRECTORY, file=sys.stderr)
        sys.exit(1)
    print("audio_audit: no audio outside " + ALLOWED_DIRECTORY)


if __name__ == "__main__":
    main()

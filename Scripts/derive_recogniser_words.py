#!/usr/bin/env python3
"""Writes the words the recogniser spells as one token, the definition of an ordinary word.

Reads the pinned large-v3 tokenizer.json, refuses any other file, and keeps every lowercase
word the tokenizer encodes with a leading space as a single token, less any word the
disclosure audit refuses in a tracked file. See Docs/ordinary-words.md.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import disclosure_audit
from ordinary_word_probe import Tokenizer

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "Sources/UttrflowSpeech/SpeechModel.swift"
OUTPUT = ROOT / "Sources/UttrflowCore/Resources/Tables/recogniser-words.json"
REPOSITORY = "openai/whisper-large-v3"
WORD = re.compile(r"[a-z]+")
SPACE = "Ġ"


def pinned_digest():
    """The tokenizer.json digest the speech model pins, read from its one home."""
    text = MODELS.read_text()
    found = re.search(
        r'tokenizerRepository: "' + re.escape(REPOSITORY) + r'".*?"tokenizer\.json": "([0-9a-f]{64})"', text, re.S)
    if not found:
        sys.exit(f"no pinned tokenizer.json digest for {REPOSITORY} in {MODELS}")
    return found.group(1)


def publishable(word):
    """Whether the disclosure audit lets this word sit in a tracked file."""
    return next(disclosure_audit.hits(word, disclosure_audit.TIER1 + disclosure_audit.TIER2), None) is None


def one_token_words(path):
    """Every publishable lowercase word whose leading-space spelling is a single token."""
    tokenizer = Tokenizer(path)
    words = {entry[1:] for entry in tokenizer.vocab if entry.startswith(SPACE) and WORD.fullmatch(entry[1:])}
    return sorted(word for word in words if tokenizer.count(word) == 1 and publishable(word))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokenizer", required=True, help="the installed large-v3 tokenizer.json")
    args = parser.parse_args()
    found = hashlib.sha256(Path(args.tokenizer).read_bytes()).hexdigest()
    if found != pinned_digest():
        sys.exit(f"{args.tokenizer} is not the pinned {REPOSITORY} tokenizer (sha256 {found})")
    rows = ",\n".join(json.dumps({"id": word}) for word in one_token_words(args.tokenizer))
    OUTPUT.write_text('{\n"schema": 1,\n"rows": [\n' + rows + "\n]\n}\n")
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

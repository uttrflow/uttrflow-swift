#!/usr/bin/env python3
"""Derives the bundled pronunciation lexicon from the pinned snapshot cache.

A word is kept when it occurs at least --min-count times across the pinned text sources, or
when it sounds the same as, or within weighted phoneme distance 1 of, a kept word. Every
listed pronunciation of a kept word is kept. See Docs/pronunciation-lexicon.md.
"""

import argparse
import collections
import os
import re
import sys
import tarfile

import ngram_sources

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join("Sources", "UttrflowCore", "Resources", "Lexicon", "pronunciation-lexicon.dict")
NOTICE = os.path.join("Sources", "UttrflowCore", "Resources", "Lexicon", "cmudict-LICENSE.txt")
MIN_COUNT = 20
TEXT_SUFFIXES = (".md", ".rst", ".txt", ".py")
WORD = re.compile(r"[a-z]+(?:'[a-z]+)?")
VOWELS = {"AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW"}
VOICING = [("P", "B"), ("T", "D"), ("K", "G"), ("F", "V"), ("S", "Z"), ("TH", "DH"), ("SH", "ZH"), ("CH", "JH")]
CHEAP = {phone: "V" for phone in VOWELS}
CHEAP.update({phone: "+".join(pair) for pair in VOICING for phone in pair})


def phones(listing):
    """A listing's phonemes with stress marks dropped."""
    return tuple(re.sub(r"\d", "", phone) for phone in listing)


def cost(first, second):
    """Substitution cost: half for a vowel for a vowel or a voicing pair, one otherwise."""
    if first == second:
        return 0.0
    return 0.5 if CHEAP.get(first, first) == CHEAP.get(second, second) else 1.0


def distance(first, second, limit=1.0):
    """Weighted phoneme edit distance, stopping early once every path exceeds limit."""
    previous = [float(index) for index in range(len(second) + 1)]
    for row, phone in enumerate(first, 1):
        current = [float(row)]
        for column, other in enumerate(second, 1):
            current.append(min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost(phone, other)))
        if min(current) > limit:
            return min(current)
        previous = current
    return previous[-1]


def parse_lexicon(text):
    """Maps each word to its listing lines, in source order, alternatives merged under the word."""
    lines = collections.OrderedDict()
    for line in text.splitlines():
        line = line.split("#", 1)[0].rstrip()
        if not line:
            continue
        head, *listing = line.split()
        word = re.sub(r"\(\d+\)$", "", head)
        lines.setdefault(word, []).append((line, phones(listing)))
    return lines


def count_words(archives):
    """Counts lower-cased words across the text files of each archive."""
    counts = collections.Counter()
    for archive in archives:
        with tarfile.open(archive) as tar:
            for member in tar:
                if member.isfile() and member.name.endswith(TEXT_SUFFIXES):
                    data = tar.extractfile(member).read().decode("utf-8", "ignore").lower()
                    counts.update(WORD.findall(data))
    return counts


def keys(pron):
    """Index keys shared by any two pronunciations within weighted distance 1."""
    found = {("=",) + pron}
    found.update(("-",) + pron[:index] + pron[index + 1:] for index in range(len(pron)))
    found.add(("~",) + tuple(CHEAP.get(phone, phone) for phone in pron))
    return found


def derive(lexicon, counts, min_count):
    """The kept words: frequent ones, then every word that sounds the same or within distance 1."""
    frequent = {word for word in lexicon if counts.get(word, 0) >= min_count}
    index = collections.defaultdict(set)
    for word, listings in lexicon.items():
        for _, pron in listings:
            for key in keys(pron):
                index[key].add(word)
    kept = set(frequent)
    for word in frequent:
        for _, pron in lexicon[word]:
            for key in keys(pron):
                for other in index[key] - kept:
                    if any(distance(pron, theirs) <= 1.0 for _, theirs in lexicon[other]):
                        kept.add(other)
    return frequent, kept


def render(lexicon, kept):
    return "".join(line + "\n" for word, listings in lexicon.items() if word in kept for line, _ in listings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", required=True, help="the snapshot folder Scripts/ngram_sources.py checks")
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--min-count", type=int, default=MIN_COUNT)
    args = parser.parse_args()
    sources = ngram_sources.load(args.root)
    failures = ngram_sources.check_entries(sources, args.root) + ngram_sources.check_cache(sources, args.cache, args.root)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    lexicon_entry = next(entry for entry in sources if entry["kind"] == "lexicon")
    with tarfile.open(os.path.join(args.cache, lexicon_entry["archive"])) as tar:
        folder = os.path.dirname(lexicon_entry["noticeInArchive"])
        lexicon = parse_lexicon(tar.extractfile(f"{folder}/cmudict.dict").read().decode("utf-8"))
    counts = count_words(os.path.join(args.cache, entry["archive"]) for entry in sources if entry["kind"] == "text")
    frequent, kept = derive(lexicon, counts, args.min_count)
    text = render(lexicon, kept)
    os.makedirs(os.path.dirname(os.path.join(args.root, OUTPUT)), exist_ok=True)
    with open(os.path.join(args.root, OUTPUT), "w", encoding="utf-8") as handle:
        handle.write(text)
    with open(os.path.join(args.root, lexicon_entry["notice"]), encoding="utf-8") as source:
        with open(os.path.join(args.root, NOTICE), "w", encoding="utf-8") as handle:
            handle.write(source.read())
    print(f"lexicon: {len(frequent)} frequent words, {len(kept)} kept, {text.count(chr(10))} listings, {len(text.encode())} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())

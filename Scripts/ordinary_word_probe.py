#!/usr/bin/env python3
"""Scores definitions of "an ordinary word" against Tests/Fixtures/ordinary-words/labelled.tsv.

Definitions: the recogniser tokenizer's cost for the word (tokens for " word", byte-level BPE
from the tokenizer.json already on disk), alone and with the romanised Hindi list in
GeneralVocabulary.swift; and the system word list at /usr/share/dict/words. The English hand
list it was first scored against is deleted. Beside them, the English-word test
`LexicalClass.isKnownEnglishWord`, read through `uttrflow-eval english-words`, which answers a
different question. See Docs/ordinary-words.md.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "Tests/Fixtures/ordinary-words/labelled.tsv"
VOCABULARY = ROOT / "Sources/UttrflowDictionary/GeneralVocabulary.swift"
SHIPPED = ROOT / "Sources/UttrflowCore/Resources/Tables/recogniser-words.json"


def labelled():
    rows = []
    for line in FIXTURE.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        word, label, group = line.split("\t")
        rows.append((word, label == "ordinary", group))
    return rows


def hand_list(name):
    text = VOCABULARY.read_text()
    words = set()
    for block in re.findall(name + r': Set<String> = words\(\s*"""(.*?)"""', text, re.S):
        words.update(w.lower() for w in block.split())
    return words


def english_words(words):
    """The words the English model knows, from `uttrflow-eval english-words`; UTTRFLOW_EVAL overrides the path."""
    candidates = [os.environ.get("UTTRFLOW_EVAL")] + [str(ROOT / ".build" / c / "uttrflow-eval") for c in ("release", "debug")]
    tool = next((c for c in candidates if c and os.access(c, os.X_OK)), None)
    if not tool:
        sys.exit("no uttrflow-eval binary: run swift build --product uttrflow-eval, or set UTTRFLOW_EVAL")
    run = subprocess.run([tool, "english-words"], input="\n".join(words) + "\n", capture_output=True, text=True, check=True)
    answers = run.stdout.split()
    if len(answers) != len(words):
        sys.exit(f"uttrflow-eval english-words answered {len(answers)} lines for {len(words)} words")
    return {w for w, a in zip(words, answers) if a == "1"}


def byte_alphabet():
    keep = list(range(ord("!"), ord("~") + 1)) + list(range(0xA1, 0xAD)) + list(range(0xAE, 0x100))
    chars = keep[:]
    extra = 0
    for b in range(256):
        if b not in keep:
            keep.append(b)
            chars.append(256 + extra)
            extra += 1
    return {b: chr(c) for b, c in zip(keep, chars)}


class Tokenizer:
    def __init__(self, path):
        model = json.loads(Path(path).read_text())["model"]
        self.vocab = model["vocab"]
        merges = [tuple(m.split(" ")) if isinstance(m, str) else tuple(m) for m in model["merges"]]
        self.ranks = {pair: rank for rank, pair in enumerate(merges)}
        self.alphabet = byte_alphabet()

    def count(self, word):
        parts = [self.alphabet[b] for b in (" " + word).encode()]
        while len(parts) > 1:
            ranked = [(self.ranks.get((a, b), 1 << 30), i) for i, (a, b) in enumerate(zip(parts, parts[1:]))]
            rank, at = min(ranked)
            if rank == 1 << 30:
                break
            parts[at:at + 2] = [parts[at] + parts[at + 1]]
        return len(parts)


def score(rows, predicate):
    tp = sum(1 for w, o, _ in rows if o and predicate(w))
    fp = sum(1 for w, o, _ in rows if not o and predicate(w))
    fn = sum(1 for w, o, _ in rows if o and not predicate(w))
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    groups = {}
    for w, o, g in rows:
        hit = predicate(w) == o
        right, total = groups.get(g, (0, 0))
        groups[g] = (right + hit, total + 1)
    return precision, recall, groups


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tokenizer", required=True, help="path to the recogniser's tokenizer.json")
    parser.add_argument("--word-list", default="/usr/share/dict/words")
    args = parser.parse_args()
    rows = labelled()
    hinglish = hand_list("commonHinglish")
    shipped = {row["id"] for row in json.loads(SHIPPED.read_text())["rows"]}
    tokenizer = Tokenizer(args.tokenizer)
    english = english_words([w for w, _, _ in rows])
    dictionary = {w.strip().lower() for w in Path(args.word_list).read_text().splitlines()}
    definitions = [
        ("tokenizer, 1 token", lambda w: tokenizer.count(w.lower()) <= 1),
        ("tokenizer, at most 2 tokens", lambda w: tokenizer.count(w.lower()) <= 2),
        ("system word list", lambda w: w.lower() in dictionary),
        ("tokenizer, 1 token, or the Hinglish list", lambda w: tokenizer.count(w.lower()) <= 1 or w.lower() in hinglish),
        ("shipped: recogniser-words.json or the Hinglish list", lambda w: w.lower() in shipped or w.lower() in hinglish),
        ("English-word test (LexicalClass.isKnownEnglishWord)", lambda w: w in english),
    ]
    names = sorted({g for _, _, g in rows})
    print("| definition | precision | recall | " + " | ".join(f"{g} correct" for g in names) + " |")
    print("|---|---|---|" + "---|" * len(names))
    for name, predicate in definitions:
        precision, recall, groups = score(rows, predicate)
        cells = " | ".join(f"{groups[g][0]}/{groups[g][1]}" for g in names)
        print(f"| {name} | {precision:.3f} | {recall:.3f} | {cells} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())

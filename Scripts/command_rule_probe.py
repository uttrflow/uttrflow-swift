#!/usr/bin/env python3
"""Count false and missed commands for three rules that tell a spoken command from content."""

import argparse
import json
import sys

COMMANDS = ["delete that", "scratch that", "undo that", "new line", "new paragraph", "select all"]
DESTRUCTIVE = {"delete that", "scratch that", "undo that", "select all"}
PREFIX = "command"
FILLERS = {"um", "uh", "er", "erm", "okay", "ok", "so", "please", "now"}

EMBEDDED = [
    "i told him to {c} file before lunch",
    "she asked me to {c} part of the report",
    "if you {c} you lose the draft",
    "we should {c} section and start again",
    "can you {c} paragraph for me",
    "the reviewer wants us to {c} bit entirely",
    "nobody wanted to {c} so it stayed",
]
QUOTED = [
    "the button is labelled {c} in the menu",
    "the error said {c} and then closed",
    "type {c} into the search box",
    "the shortcut for {c} is on the toolbar",
]
MENTIONED = [
    "to remove a word you say {c}",
    "the phrase {c} is a voice command",
    "when i say {c} it should not type it",
]
CLAUSE_END = [
    "the old file is wrong so {c}",
    "that sentence was a mistake {c}",
]
CONTENT_ALONE = [
    "{c}",
]
COMMAND_FORMS = [
    ("alone", "{c}"),
    ("filler", "um {c}"),
    ("polite", "{c} please"),
]
LEAD = "the meeting moves to thursday at noon"


def norm(text):
    return " ".join(text.lower().replace(",", " ").replace(".", " ").split())


def strip_fillers(words):
    while words and words[0] in FILLERS:
        words = words[1:]
    while words and words[-1] in FILLERS:
        words = words[:-1]
    return words


def is_command_text(text, prefixed):
    words = norm(text).split()
    if prefixed:
        if not words or words[0] != PREFIX:
            return False
        words = words[1:]
    return " ".join(strip_fillers(words)) in COMMANDS


def build_corpus():
    cases = []
    for c in COMMANDS:
        for kind, rows in (("embedded", EMBEDDED), ("quoted", QUOTED), ("mentioned", MENTIONED), ("clause-end", CLAUSE_END)):
            for row in rows:
                for mode in ("hold", "hands-free"):
                    cases.append({"intent": "content", "kind": kind, "mode": mode, "command": c, "pieces": [row.format(c=c)]})
        for mode in ("hold", "hands-free"):
            cases.append({"intent": "content", "kind": "content-alone", "mode": mode, "command": c, "pieces": [c]})
            cases.append({"intent": "content", "kind": "content-after-pause", "mode": mode, "command": c, "pieces": [LEAD, c]})
            for kind, form in COMMAND_FORMS:
                cases.append({"intent": "command", "kind": "command-" + kind, "mode": mode, "command": c, "pieces": [form.format(c=c)]})
                cases.append({"intent": "command", "kind": "command-" + kind + "-continuation", "mode": mode, "command": c, "pieces": [LEAD, form.format(c=c)]})
            cases.append({"intent": "command", "kind": "command-run-on", "mode": mode, "command": c, "pieces": [LEAD + " " + c]})
    return cases


def spoken_pieces(case, rule):
    if case["intent"] == "command" and rule == "prefix":
        return case["pieces"][:-1] + [PREFIX + " " + case["pieces"][-1]]
    return case["pieces"]


def fires(case, rule):
    if rule == "key":
        return case["intent"] == "command"
    pieces = spoken_pieces(case, rule)
    prefixed = rule == "prefix"
    if case["mode"] == "hold":
        units = [" ".join(pieces)] if rule == "whole-utterance" else pieces
    else:
        units = pieces
    return any(is_command_text(u, prefixed) for u in units)


RULES = ["whole-utterance", "whole-piece", "key", "prefix"]


def measure(cases):
    out = {}
    for rule in RULES:
        rows = {"false": 0, "false_destructive": 0, "content": 0, "missed": 0, "commands": 0, "false_kinds": {}, "missed_kinds": {}}
        for case in cases:
            hit = fires(case, rule)
            if case["intent"] == "content":
                rows["content"] += 1
                if hit:
                    rows["false"] += 1
                    rows["false_destructive"] += case["command"] in DESTRUCTIVE
                    rows["false_kinds"][case["kind"]] = rows["false_kinds"].get(case["kind"], 0) + 1
            else:
                rows["commands"] += 1
                if not hit:
                    rows["missed"] += 1
                    key = case["mode"] + "/" + case["kind"]
                    rows["missed_kinds"][key] = rows["missed_kinds"].get(key, 0) + 1
        out[rule] = rows
    return out


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print the full result as JSON")
    args = parser.parse_args(argv)
    cases = build_corpus()
    result = measure(cases)
    if args.json:
        print(json.dumps({"cases": len(cases), "rules": result}, indent=2, sort_keys=True))
        return 0
    print(f"cases {len(cases)}")
    for rule, r in result.items():
        print(f"{rule:16} false {r['false']}/{r['content']} (destructive {r['false_destructive']})  missed {r['missed']}/{r['commands']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

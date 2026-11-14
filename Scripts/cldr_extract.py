#!/usr/bin/env python3
"""Derives the English spoken-number words from a pinned CLDR spell-out file.

Usage: cldr_extract.py <common/rbnf/en.xml> <release> > Sources/UttrflowCore/Resources/Tables/cldr-en-spellout.json

Cardinals come from the `spellout-cardinal` ruleset; ordinals from `spellout-ordinal`, whose
13-19 rule adds "th" to the cardinal, whose tens rules join a stem to "tieth" and whose scale
rules add "th" to the scale word. Only single words are kept, since `NumberWords` joins the
words into longer numbers itself.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET


def rules(root, name):
    for ruleset in root.iter("ruleset"):
        if ruleset.get("type") == name:
            return [(int(r.get("value")), r.text or "") for r in ruleset.iter("rbnfrule") if r.get("value", "").isdigit()]
    raise SystemExit(f"no ruleset {name}")


def main():
    path, release = sys.argv[1], sys.argv[2]
    root = ET.parse(path).getroot()
    rows = []
    cardinal = {}
    for value, text in rules(root, "spellout-cardinal"):
        word = re.sub(r"^←← ", "", text)
        word = re.split(r"[\[;]", word)[0].strip()
        if re.fullmatch(r"[a-z]+", word):
            cardinal[value] = word
            rows.append({"id": word, "value": value, "kind": "cardinal"})
    for value, text in rules(root, "spellout-ordinal"):
        if re.fullmatch(r"[a-z]+;", text):
            word = text[:-1]
        elif text.startswith("=%spellout-numbering=th"):
            continue
        elif "%%tieth" in text:
            word = text.split("→")[0] + "tieth"
        elif "→%%th→" in text:
            word = cardinal[value] + "th"
        else:
            continue
        rows.append({"id": word, "value": value, "kind": "ordinal"})
    for value in range(13, 20):
        rows.append({"id": cardinal[value] + "th", "value": value, "kind": "ordinal"})
    rows.sort(key=lambda r: (r["kind"], r["value"], r["id"]))
    seen, unique = set(), []
    for row in rows:
        if row["id"] not in seen:
            seen.add(row["id"])
            unique.append(row)
    out = {
        "schema": 1,
        "provenance": {
            "source": "Unicode CLDR common/rbnf/en.xml",
            "release": release,
            "licence": "Unicode-3.0",
            "producedBy": "Scripts/cldr_extract.py",
        },
        "rows": unique,
    }
    print(json.dumps(out, indent=2))


main()

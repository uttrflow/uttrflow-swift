#!/usr/bin/env python3
"""Fails when an Accessibility snapshot fixture holds an email address, a postal address, a long number or a real host."""

import json
import os
import re
import sys

FIXTURES = os.path.join("Tests", "Fixtures", "AccessibilitySnapshots")

# Domains reserved for documentation and private names, matched on the last labels of a host.
RESERVED = re.compile(r"(^|\.)(example(\.[a-z]+)*|invalid|test|local|internal|localhost|localdomain)$", re.IGNORECASE)

EMAIL = re.compile(r"[\w.%+-]+@([\w-]+(?:\.[\w-]+)+)")
URL_HOST = re.compile(r"\b[a-z][a-z0-9+.-]*://(?:[^@/\s\"]*@)?([^/:\s\"?#]+)", re.IGNORECASE)
BARE_HOST = re.compile(r"\bwww\.[\w-]+(?:\.[\w-]+)+", re.IGNORECASE)

# Nine or more digits, single spaces, dots or hyphens allowed between them: a phone, card or account number.
DIGIT_RUN = re.compile(r"\d(?:[ .-]?\d){8,}")

# A house number followed by a street word, the shape of a postal address in the languages the fixtures hold.
STREET = re.compile(
    r"\b\d{1,5}[a-z]?,?\s+(?:[A-Z][\w'-]*\s+){0,4}"
    r"(?:Street|St|Road|Rd|Avenue|Ave|Lane|Ln|Boulevard|Blvd|Drive|Dr|Marg|Nagar|Way|Court|Ct|Place|Pl)\b"
)


def strings(value):
    """Every string a decoded JSON value holds, keys and values alike."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def findings(text):
    """(kind, match) for each piece of personal data in one string."""
    found = []
    for match in EMAIL.finditer(text):
        if not RESERVED.search(match.group(1)):
            found.append(("email address", match.group(0)))
    for match in URL_HOST.finditer(text):
        host = match.group(1)
        if host and not RESERVED.search(host):
            found.append(("host", host))
    for match in BARE_HOST.finditer(text):
        if not RESERVED.search(match.group(0)):
            found.append(("host", match.group(0)))
    found += [("long number", match.group(0)) for match in DIGIT_RUN.finditer(text)]
    found += [("postal address", match.group(0)) for match in STREET.finditer(text)]
    return found


def audit(directory=FIXTURES):
    """(file, kind, match) for every finding, and how many fixtures were read."""
    names = sorted(name for name in os.listdir(directory) if name.endswith(".json"))
    results = []
    for name in names:
        with open(os.path.join(directory, name), encoding="utf-8") as handle:
            document = json.load(handle)
        for text in strings(document):
            results += [(name, kind, match) for kind, match in findings(text)]
    return results, len(names)


def main():
    if not os.path.isdir(FIXTURES):
        print(f"Snapshot fixtures: {FIXTURES} is missing, so nothing would be checked.")
        return 1
    results, count = audit()
    if count == 0:
        print(f"Snapshot fixtures: no JSON file in {FIXTURES}, so nothing was checked.")
        return 1
    if results:
        print("Snapshot fixtures: personal data in a fixture. Record with `uttrflow-dev probe snapshot`,")
        print("or hand-write the text with example.com hosts and invented names and numbers.\n")
        for name, kind, match in sorted(set(results)):
            print(f"  {FIXTURES}/{name}: {kind}: {match}")
        return 1
    print(f"Snapshot fixtures: {count} files, no email address, postal address, long number or real host.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

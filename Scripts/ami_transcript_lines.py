#!/usr/bin/env python3
"""Export AMI manual segments to a local speech-shape input, never repository data."""

import argparse
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

NITE = "{http://nite.sourceforge.net/}"
RANGE = re.compile(r"([^#]+)#id\(([^)]+)\)(?:\.\.id\(([^)]+)\))?$")


def referenced_elements(href, words, positions):
    match = RANGE.fullmatch(href)
    if match is None:
        raise ValueError("Unsupported AMI child reference")
    filename, first, last = match.groups()
    entries = words[filename]
    start = positions[filename][first]
    end = positions[filename][last or first]
    if end < start:
        raise ValueError("Reversed AMI word range")
    return entries[start:end + 1]


def segment_text(elements):
    tokens = []
    leading_marks = ""
    for element in elements:
        if element.tag != "w":
            continue
        text = element.text or ""
        if not text:
            raise ValueError("Empty AMI word")
        if "\n" in text or "\r" in text:
            raise ValueError("Multiline AMI word")
        if element.get("punc") == "true":
            if tokens:
                tokens[-1] += text
            else:
                leading_marks += text
        else:
            tokens.append(leading_marks + text)
            leading_marks = ""
    return " ".join(tokens)


def transcript_lines(archive):
    names = sorted(archive.namelist())
    word_files = [name for name in names if name.startswith("words/") and name.endswith(".xml")]
    words = {Path(name).name: list(ET.fromstring(archive.read(name))) for name in word_files}
    positions = {
        name: {element.attrib[NITE + "id"]: index for index, element in enumerate(entries)}
        for name, entries in words.items()
    }
    for name in names:
        if not name.startswith("segments/") or not name.endswith(".xml"):
            continue
        for segment in ET.fromstring(archive.read(name)):
            elements = []
            for child in segment.findall(NITE + "child"):
                elements.extend(referenced_elements(child.attrib["href"], words, positions))
            line = segment_text(elements)
            if line:
                yield line


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    destination = args.output.resolve()
    repository = Path(__file__).resolve().parent.parent
    if destination.is_relative_to(repository) or any(
        (parent / ".git").exists() for parent in destination.parents
    ):
        parser.error("Reference text must stay outside the repository")
    with zipfile.ZipFile(args.archive) as archive, args.output.open("w", encoding="utf-8") as output:
        count = 0
        for line in transcript_lines(archive):
            output.write(line + "\n")
            count += 1
    print(f"Exported {count} nonempty manual segments; transcript text remains local")


if __name__ == "__main__":
    main()

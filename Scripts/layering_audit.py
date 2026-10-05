#!/usr/bin/env python3
"""Counts logic modules that import a UI framework or depend on a platform module, and stops the count ever rising."""

import argparse
import os
import re
import sys

import ratchet

SOURCES = "Sources"
MANIFEST = "Package.swift"
BASELINE = os.path.join("Scripts", "layering_baseline.json")

# The only modules that may touch the UI frameworks. Every other directory under Sources is logic.
PLATFORM_MODULES = frozenset(
    {"Uttrflow", "UttrflowClipboard", "UttrflowContext", "UttrflowInput", "UttrflowPermissions", "uttrflow-dev",
     "uttrflow-insertion-fixture"}
)

UI_FRAMEWORKS = ("AppKit", "ApplicationServices", "SwiftUI", "Cocoa")

# `import AppKit`, `@preconcurrency import SwiftUI`, `import struct AppKit.NSRect`.
UI_IMPORT = re.compile(
    r"^\s*(?:@\w+\s+)*(?:(?:public|internal|package|private|fileprivate)\s+)?import\s+"
    r"(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?"
    r"(?:" + "|".join(UI_FRAMEWORKS) + r")\b"
)

TARGET_KINDS = (".target(", ".executableTarget(")


def is_logic(module):
    return module not in PLATFORM_MODULES


def logic_modules(root=SOURCES):
    return sorted(name for name in os.listdir(root) if is_logic(name) and os.path.isdir(os.path.join(root, name)))


def ui_imports_in(path):
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if UI_IMPORT.match(line):
                yield number, line.strip()


def import_violations(root=SOURCES):
    found = []
    for module in logic_modules(root):
        for directory, _, names in os.walk(os.path.join(root, module)):
            for name in sorted(names):
                if name.endswith(".swift"):
                    path = os.path.join(directory, name)
                    found += [(path, f"{path}:{number}: {text}") for number, text in ui_imports_in(path)]
    return found


def balanced(text, start):
    """The text from the bracket at `start` to its match."""
    depth = 0
    in_string = False
    for index in range(start, len(text)):
        char = text[index]
        if char == '"':
            in_string = not in_string
        elif not in_string and char in "([":
            depth += 1
        elif not in_string and char in ")]":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]
    raise ValueError(f"unbalanced bracket in {MANIFEST}")


def local_dependencies(declaration):
    """Names a target depends on inside the package: bare strings and `.target(name:)`, not products."""
    match = re.search(r"dependencies:\s*\[", declaration)
    if not match:
        return []
    body = balanced(declaration, match.end() - 1)
    body = re.sub(r"\.product\((?:[^()]|\([^()]*\))*\)", "", body)
    return re.findall(r'"([^"]+)"', body)


def targets_in(manifest_text):
    """Yield (name, local dependencies) for each non-test target in the manifest."""
    for kind in TARGET_KINDS:
        position = manifest_text.find(kind)
        while position != -1:
            declaration = balanced(manifest_text, position + len(kind) - 1)
            name = re.search(r'name:\s*"([^"]+)"', declaration)
            if name:
                yield name.group(1), local_dependencies(declaration)
            position = manifest_text.find(kind, position + len(kind))


def dependency_violations(manifest_text):
    return [
        (f"{MANIFEST}: {name} -> {dependency}", f"{MANIFEST}: logic module {name} depends on platform module {dependency}")
        for name, dependencies in targets_in(manifest_text)
        if is_logic(name)
        for dependency in dependencies
        if dependency in PLATFORM_MODULES
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every violation")
    arguments = parser.parse_args()

    with open(MANIFEST, encoding="utf-8") as handle:
        found = import_violations() + dependency_violations(handle.read())
    counts = {}
    for key, _ in found:
        counts[key] = counts.get(key, 0) + 1

    if arguments.report:
        print("\n".join(text for _, text in found))
        print(f"\n{len(found)} layering violations in {len(counts)} places")
        return 0
    if arguments.update:
        return ratchet.update(BASELINE, counts, "layering violations", "a module to bring back into its layer later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])
    rises = ratchet.risen(counts, baseline.get("files", {}))
    if rises:
        print("Layering: logic modules import no UI framework and depend on no platform module.")
        print("These gained a violation:\n")
        for key, text in found:
            if key in rises:
                print(f"  {text}")
        print("\nMove the platform call behind a protocol in the logic module and implement it in a platform module.")
        return 1

    print(f"Layering: {len(found)} violations, none higher than the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

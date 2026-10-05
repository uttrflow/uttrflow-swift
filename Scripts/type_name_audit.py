#!/usr/bin/env python3
"""Counts top-level type names declared in more than one module, and stops the count ever rising."""

import argparse
import os
import re
import sys

import ratchet

SOURCES = "Sources"
BASELINE = os.path.join("Scripts", "type_name_baseline.json")

# A declaration at column 0 is top level; `private` and `fileprivate` types cannot clash across modules.
DECLARATION = re.compile(
    r"^(?:@[\w.]+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|internal|package|open|final|indirect|nonisolated)\s+)*"
    r"(?:struct|class|enum|protocol|actor|typealias)\s+([A-Za-z_]\w*)"
)

# `typealias Name = Module.Name` re-exports the one type rather than declaring a second.
REEXPORT = re.compile(r"\btypealias\s+(\w+)\s*=\s*[\w.]+\.(\w+)\s*$")


def declared_names(path):
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            match = DECLARATION.match(line)
            reexport = REEXPORT.search(line)
            if match and not (reexport and reexport.group(1) == reexport.group(2)):
                yield match.group(1), number


def declarations(root=SOURCES):
    """Map each type name to its sorted (module, path:line) declarations."""
    found = {}
    for module in sorted(os.listdir(root)):
        module_root = os.path.join(root, module)
        if not os.path.isdir(module_root):
            continue
        for directory, _, names in os.walk(module_root):
            for name in sorted(names):
                if name.endswith(".swift"):
                    path = os.path.join(directory, name)
                    for type_name, number in declared_names(path):
                        found.setdefault(type_name, []).append((module, f"{path}:{number}"))
    return found


def duplicates(root=SOURCES):
    """Each name declared in two or more modules, counted as the number of modules past the first."""
    counts, places = {}, {}
    for name, where in declarations(root).items():
        modules = {module for module, _ in where}
        if len(modules) > 1:
            counts[name] = len(modules) - 1
            places[name] = [place for _, place in where]
    return counts, places


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every name declared in several modules")
    arguments = parser.parse_args()

    counts, places = duplicates()
    if arguments.report:
        for name in sorted(counts):
            print(f"{name}: {', '.join(places[name])}")
        print(f"\n{len(counts)} type names declared in more than one module")
        return 0
    if arguments.update:
        return ratchet.update(BASELINE, counts, "duplicate type names", "a name to give one meaning later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])
    rises = ratchet.risen(counts, baseline.get("files", {}))
    if rises:
        print("Type names: a top-level type name is declared in one module only.")
        print("These are now declared in another module as well:\n")
        for name in sorted(rises):
            print(f"  {name}: {', '.join(places[name])}")
        print("\nName the new type for what it means in its own module.")
        return 1

    print(f"Type names: {len(counts)} declared in more than one module, none above the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

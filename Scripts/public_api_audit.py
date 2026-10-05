#!/usr/bin/env python3
"""Lists each module's public declarations and fails when one appears that the baseline does not record."""

import argparse
import os
import re
import sys

import ratchet

SOURCES = "Sources"
TESTS = "Tests"
BASELINE = os.path.join("Scripts", "public_api_baseline.json")

MODIFIER = (
    r"(?:@[\w.]+(?:\([^)]*\))?|nonisolated(?:\(unsafe\))?|final|static|class|override|mutating|nonmutating|"
    r"convenience|required|indirect|lazy|dynamic|weak|unowned|distributed|"
    r"(?:private|fileprivate|internal|package)\(set\))"
)
KINDS = r"func|var|let|struct|class|enum|protocol|typealias|actor|init\??|subscript|extension|case|associatedtype|macro"

# `public static func run(`, `@MainActor public final class Store`, `public private(set) var count`.
DECLARATION = re.compile(
    rf"^\s*(?:{MODIFIER}\s+)*(?:public|open)\s+(?:{MODIFIER}\s+)*({KINDS})\b\s*([^\s(<:{{=,]+|[=!<>+\-*/%&|^~.?]+)?"
)
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def swift_files(root):
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(directory, name)


def modules(root=SOURCES):
    return sorted(name for name in os.listdir(root) if os.path.isdir(os.path.join(root, name)))


def declarations_in(path):
    """Yield (kind, name, line number) for each public or open declaration in one file."""
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            match = DECLARATION.match(line)
            if match:
                kind = match.group(1).rstrip("?")
                name = match.group(2) or kind
                yield kind, ("init" if kind == "init" else name), number


def surface(root=SOURCES):
    """Each public declaration as (key, location), keyed "Module kind name"."""
    found = []
    for module in modules(root):
        for path in swift_files(os.path.join(root, module)):
            found += [(f"{module} {kind} {name}", f"{path}:{number}") for kind, name, number in declarations_in(path)]
    return found


def words_in(path):
    with open(path, encoding="utf-8") as handle:
        return set(WORD.findall(handle.read()))


def outside_words(module, sources=SOURCES, tests=TESTS):
    """Every identifier written where `module` is reached only through its public surface."""
    words = set()
    for other in modules(sources):
        if other != module:
            for path in swift_files(os.path.join(sources, other)):
                words |= words_in(path)
    testable = re.compile(rf"@testable\s+import\s+{re.escape(module)}\b")
    for path in swift_files(tests) if os.path.isdir(tests) else ():
        with open(path, encoding="utf-8") as handle:
            if not testable.search(handle.read()):
                words |= words_in(path)
    return words


def unused(found, sources=SOURCES, tests=TESTS):
    """Public named declarations whose name is written nowhere outside their own module."""
    cache = {}
    result = []
    for key, location in found:
        module, kind, name = key.split(" ", 2)
        if kind in ("init", "subscript", "extension") or not WORD.fullmatch(name):
            continue
        if module not in cache:
            cache[module] = outside_words(module, sources, tests)
        if name not in cache[module]:
            result.append((key, location))
    return result


def counts_of(found):
    counts = {}
    for key, _ in found:
        counts[key] = counts.get(key, 0) + 1
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    ratchet.add_arguments(parser)
    parser.add_argument("--report", action="store_true", help="list every public declaration")
    parser.add_argument("--unused", action="store_true", help="list public declarations named nowhere outside their module")
    arguments = parser.parse_args()

    found = surface()
    counts = counts_of(found)

    if arguments.report:
        print("\n".join(f"{location}: {key}" for key, location in found))
        print(f"\n{len(found)} public declarations under {len(counts)} names")
        return 0
    if arguments.unused:
        candidates = unused(found)
        print("\n".join(f"{location}: {key}" for key, location in candidates))
        print(f"\n{len(candidates)} public declarations named nowhere outside their module")
        return 0
    if arguments.update:
        return ratchet.update(BASELINE, counts, "public declarations", "a public symbol to review later", arguments.after_merge)

    baseline = ratchet.load(BASELINE)
    if not baseline:
        return ratchet.missing(BASELINE, sys.argv[0])
    rises = ratchet.risen(counts, baseline.get("files", {}))
    if rises:
        print("Public API: every public declaration is recorded in the baseline, so a new one is reviewed.")
        print("These are new:\n")
        for key, location in found:
            if key in rises:
                print(f"  {location}: {key}")
        print("\nMake it internal if no other module needs it; otherwise run")
        print(f"  python3 {sys.argv[0]} --update")
        print("and let the baseline line show in the diff for review.")
        return 1

    print(f"Public API: {len(found)} declarations, none outside the baseline.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

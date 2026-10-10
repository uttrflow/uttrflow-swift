#!/usr/bin/env python3
"""Measures how merged changes land on the dictation pipeline and the meaning guard, the numbers Docs/module-decisions.md decides from."""

import argparse
import re
import statistics
import subprocess
import sys

FAMILIES = {
    "pipeline": (
        re.compile(r"^Sources/UttrflowPipeline/DictationPipeline(\+\w+)?\.swift$"),
        "Sources/UttrflowPipeline/DictationPipeline.swift",
    ),
    "guard": (
        re.compile(r"^Sources/UttrflowAI/(MeaningPreservationGuard|Guard\w+|MeaningGuardReference)\.swift$"),
        "Sources/UttrflowAI/MeaningPreservationGuard.swift",
    ),
}
# A merge whose only purpose is to put a broken main right again: the change before it failed.
REPAIR = re.compile(r"^(Revert|Restore main|Repair the build|Wrap (the )?lines .*main)", re.IGNORECASE)
MEMBER = re.compile(
    r"^    (@\w+ )*((public|private|internal|nonisolated|fileprivate|static|mutating) )*(func|init)\b"
)


def git(*arguments):
    """The standard output of one git command, failing loudly when git does."""
    return subprocess.run(["git", *arguments], capture_output=True, text=True, check=True).stdout


def merged_changes(since, until):
    """Each first-parent commit in the range as (hash, subject, [(path, lines changed)])."""
    log = git("log", "--first-parent", until, f"--since={since}", "--numstat", "--format=@@%h\t%s")
    changes = []
    for block in log.split("@@")[1:]:
        lines = block.strip("\n").split("\n")
        commit, subject = lines[0].split("\t", 1)
        files = []
        for line in lines[1:]:
            fields = line.split("\t")
            if len(fields) == 3 and fields[0] != "-":
                files.append((fields[2], int(fields[0]) + int(fields[1])))
        changes.append((commit, subject, files))
    return changes


def percentile(values, fraction):
    """The value at `fraction` of the sorted list, by the nearest-rank rule."""
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def family_row(changes, pattern):
    """The criteria for the changes that touch one family of files, or None when none does."""
    touching = [c for c in changes if any(pattern.match(path) for path, _ in c[2])]
    if not touching:
        return None
    churn = [sum(n for path, n in files if pattern.match(path)) for _, _, files in touching]
    own = [len({path for path, _ in files if pattern.match(path)}) for _, _, files in touching]
    other = [
        len({path for path, _ in files if path.startswith("Sources/") and not pattern.match(path)})
        for _, _, files in touching
    ]
    tests = [len({path for path, _ in files if path.startswith("Tests/")}) for _, _, files in touching]
    repairs = sum(1 for _, subject, _ in touching if REPAIR.match(subject))
    return {
        "changes": len(touching),
        "lines median": statistics.median(churn),
        "lines p90": percentile(churn, 0.9),
        "one file": f"{sum(1 for n in own if n == 1) / len(touching):.0%}",
        "other source files median": statistics.median(other),
        "test files median": statistics.median(tests),
        "repairs": f"{repairs} ({repairs / len(touching):.0%})",
    }


def member_starts(source):
    """The first line and name of each type-level function or initialiser in a Swift file."""
    starts = []
    for number, line in enumerate(source.split("\n"), start=1):
        if MEMBER.match(line):
            starts.append((number, re.sub(r"\(.*", "", line.strip())))
    return starts


def hottest_members(path, since, until):
    """How many merged changes edited each member of one file, most edited first."""
    counts = {}
    commits = git("log", "--first-parent", until, f"--since={since}", "--format=%h", "--", path).split()
    for commit in commits:
        starts = member_starts(git("show", f"{commit}:{path}"))
        diff = git("show", commit, "-U0", "--format=", "--", path)
        touched = set()
        for hunk in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", diff, re.MULTILINE):
            first, length = int(hunk.group(1)), int(hunk.group(2) or 1)
            for line in range(first, first + max(length, 1)):
                owner = "(declarations)"
                for start, name in starts:
                    if start <= line:
                        owner = name
                touched.add(owner)
        for owner in touched:
            counts[owner] = counts.get(owner, 0) + 1
    return len(commits), sorted(counts.items(), key=lambda item: -item[1])


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--since", required=True, help="first commit date measured, as git log --since reads it")
    parser.add_argument("--until", default="HEAD", help="last commit measured (default HEAD)")
    parser.add_argument("--members", type=int, default=6, help="members listed per family's main file")
    options = parser.parse_args(argv)
    changes = merged_changes(options.since, options.until)
    for name, (pattern, main_file) in FAMILIES.items():
        row = family_row(changes, pattern)
        print(f"{name}: " + ("no changes" if row is None else ", ".join(f"{k} {v}" for k, v in row.items())))
        total, members = hottest_members(main_file, options.since, options.until)
        for member, count in members[: options.members]:
            print(f"  {count:>3} of {total}  {member}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

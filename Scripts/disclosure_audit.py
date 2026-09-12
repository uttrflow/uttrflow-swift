#!/usr/bin/env python3
"""Keeps the private half of building this product out of the public half."""

# The conversation that produces the work is not public. The repository is. The boundary
# between them is one way, and every mechanism in this file exists because it is one way.
#
# What must not cross it is set out in AGENTS.md under "What must never reach a tracked
# file": named competitors, growth and business strategy, and anything said in a working
# session that is not a technical requirement. This script is that rule made mechanical,
# because the rule alone has already failed four times — a competitor feature-gap table
# reached four commits on `main`, the source list behind it reached a pull request body
# that is still served and indexed, a link to a third-party dictation page survived the
# manual sweep that was meant to remove exactly that, and the word for the person on the
# other end of the session reached twenty-nine files.
#
# None of those was carelessness. Every one was written by somebody who had just read the
# reference and was holding it in mind, which is the only moment the mistake is available
# to make. A convention lasts as long as the person who remembers it; a gate does not
# have to remember.
#
# ---------------------------------------------------------------------------
# Two tiers, because a gate that cries wolf is a gate somebody turns off
# ---------------------------------------------------------------------------
#
# Measured against this tree before either list was fixed: patterns naming a product or a
# growth idea outright matched nothing at all, and patterns naming the *vocabulary* around
# them — "competitor", "positioning", "the operator" — matched seventy-seven files, almost
# every one of them legitimate product copy. "Captured exactly as you said them" is a
# sentence about dictation, not a leak.
#
# So the two kinds are not scored the same:
#
#   TIER 1  A name, a domain or a strategy phrase. Zero tolerance, no baseline, no way to
#           record an exception. If one of these matches, something crossed the boundary.
#
#   TIER 2  Vocabulary that is usually innocent and occasionally the tell. Ratcheted
#           against Scripts/disclosure_baseline.json, the same way comment_audit.py
#           ratchets comment blocks: what is already here is recorded, and any *rise*
#           fails. Shrinking one file does not pay for growing another.
#
# The ratchet is what makes the gate installable today rather than after a cleanup that
# would never quite finish. It also means the count only ever goes down.
#
# Tier 1 is itself two lists, for a reason particular to this product. A name is a name
# wherever it appears. A phrase like "churn rate" is a name in a design document and
# ordinary speech in an evaluation corpus, and this repository has a corpus full of
# ordinary speech — which is why CORPUS above exempts those paths from the phrases and
# from nothing else.
#
# In text that is being written now — a commit message, a pull request body, a diff's
# added lines — there is no legacy to grandfather, so both tiers block. New writing is
# held to the whole bar.
#
# ---------------------------------------------------------------------------
# Why the terms are base64
# ---------------------------------------------------------------------------
#
# Same reason as the address constants in pii_audit.sh, and the reason is not obfuscation.
# A plain-text list of competitor names in a tracked file would publish, inside the gate,
# exactly what the gate exists to keep out — and it would match itself on every run, so
# the audit could never pass. Decoded at run time, the patterns exist only in memory.
#
#   See them:  python3 Scripts/disclosure_audit.py --show-terms
#
# ---------------------------------------------------------------------------
# Where this runs
# ---------------------------------------------------------------------------
#
#   make verify            the working tree, before the build, beside pii-audit
#   .githooks/pre-push     every ref, and every commit message in the push
#   .githooks/commit-msg   the message, before it is even recorded
#   .github/workflows/     the pull request's whole range, plus its title and body
#   .claude/settings.json  the text of a command an agent is about to run
#
# No one of those holds on its own. The hooks are skipped by --no-verify, the workflow is
# skipped by an admin merge, and the settings hook only binds agents on this machine. They
# are layered because the ways around each one do not overlap.

import argparse
import base64
import json
import os
import re
import subprocess
import sys

BASELINE = os.path.join("Scripts", "disclosure_baseline.json")

# This file and the baseline beside it are the only paths exempt, and they are exempt
# because they are the gate. Nothing else in the tree can be excluded.
SELF = ("Scripts/disclosure_audit.py", BASELINE.replace(os.sep, "/"))

# The one exemption, and it is from the phrase patterns only.
#
# This is an app for turning speech into text, so its evaluation corpus is arbitrary
# spoken English by construction — somebody dictating "uh churn rate is four point five
# percent" is a fixture for the percent rule, not a business plan. Three files tripped on
# exactly that. A corpus that cannot contain ordinary business vocabulary is not a corpus.
#
# The names list is NOT exempt here. A competitor has no business being in a speech
# fixture either, and that is the half worth protecting.
CORPUS = ("Sources/UttrflowEval/", "Tests/UttrflowEvalTests/")

NAMES_B64 = [
    "XGJ3aXNwclxi",
    "XGJzdXBlcltcc1wtXT93aGlzcGVyXGI=",
    "XGJtYWNbXHNcLV0/d2hpc3Blclxi",
    "XGJ3aGlzcGVyW1xzXC1dP2Zsb3dcYg==",
    "XGJhcXVhW1xzXC1dP3ZvaWNlXGI=",
    "XGJ2b2ljZVtcc1wtXT9pbmtcYg==",
    "XGJ3aWxsb3dbXHNcLV0/dm9pY2VcYg==",
    "XGJiZXR0ZXJbXHNcLV0/ZGljdGF0aW9uXGI=",
    "XGJ0YWxvblxzK3ZvaWNlXGI=",
    "XGJkcmFnb25ccysoZGljdGF0ZXxuYXR1cmFsbHlzcGVha2luZ3xuYXR1cmFsbHlccytzcGVha2luZylcYg==",
    "XGJvdHRlclwuYWlcYg==",
    "XGJzcGVlY2hsaXZlXGI=",
    "XGJwYXJha2VldHlcYg==",
    "XGJyZXZcLmNvbVxi",
    "XGJzb25peFwuYWlcYg==",
    "XGJkZXNjcmlwdFxi",
    "XGJnb29kXHM/dGFwZVxi",
    "XGJoYXBweVxzP3NjcmliZVxi",
    "XGJ0cmludFxi",
    "XGJmaXJlZmxpZXNcLmFpXGI=",
    "XGJmbG93XHM/dm9pY2VcYg==",
]

PHRASES_B64 = [
    "XGJzdGFyXHMrKGNvdW50fGdvYWx8dGFyZ2V0KXM/XGI=",
    "XGJnaXRodWJccytzdGFyc1xi",
    "XGJoYWNrZXJccz9uZXdzXGI=",
    "XGJzaG93XHMraG5cYg==",
    "XGJwcm9kdWN0XHMraHVudFxi",
    "XGJnbyhpbmcpP1xzK3ZpcmFsXGI=",
    "XGJ2aXJhbGl0eVxi",
    "XGJncm93dGhccysoc3RyYXRlZ3l8aGFja1x3Knxsb29wfHBsYW58Z29hbHx0YXJnZXR8cHJvZ3JhbW1lPylcYg==",
    "XGIoY29udmVyc2lvbnxzYWxlc3xtYXJrZXRpbmcpXHMrZnVubmVsXGI=",
    "XGJ0b3BccytvZlxzK2Z1bm5lbFxi",
    "XGJtYXJrZXRccytzaGFyZVxi",
    "XGJnb1tcc1wtXXRvW1xzXC1dbWFya2V0XGI=",
    "XGJsYXVuY2hccysocGxhbnx0aW1pbmd8d2luZG93fHN0cmF0ZWd5KVxi",
    "XGIobW9uZXRpc2F0aW9ufG1vbmV0aXphdGlvbnxwcmljaW5nKVxzK3N0cmF0ZWd5XGI=",
    "XGJjaHVyblxzK3JhdGVcYg==",
    "XGJjb21wZXRpdGl2ZVxzKyhhZHZhbnRhZ2V8YW5hbHlzaXN8bGFuZHNjYXBlfHBvc2l0aW9uXHcqKVxi",
    "XGJjb21wZXRpdG9yXHMrKGFuYWx5c2lzfHJlc2VhcmNofG1hdHJpeHxjb21wYXJpc29ufHRhYmxlKVxi",
    "XGJ0aGVccytvcGVyYXRvclxzKyhzYWlkfGFza2VkfHdhbnRzfHRvbGR8ZGVjaWRlZHxwcmVmZXJzfGluc3RydWN0ZWQpXGI=",
    "XGJ5b3Vccythc2tlZFxzK21lXHMrdG9cYg==",
    "XGJwZXJccytvdXJccysoY29udmVyc2F0aW9ufGRpc2N1c3Npb258Y2hhdHxjYWxsKVxi",
    "XGJhc1xzKyh3ZVxzKyk/ZGlzY3Vzc2VkXHMrKGlufG9ufGR1cmluZ3xlYXJsaWVyKVxi",
    "XGJpblxzKyh0aGVccyspPyhjaGF0fGNvbnZlcnNhdGlvbilccysoYWJvdmV8ZWFybGllcilcYg==",
    "XGJ0aGVccysodXNlcnxvcGVyYXRvcilccysoY29tcGxhaW5lZHxpc1xzK2ZydXN0cmF0ZWQpXGI=",
]

TIER2_B64 = [
    "XGJjb21wZXRpdG9yXHcq",
    "XGJjb21wZXRpbmdccysocHJvZHVjdHxhcHB8dG9vbHxzZXJ2aWNlKXM/XGI=",
    "XGJwb3NpdGlvbmluZ1xi",
    "XGJ0aGVccytvcGVyYXRvclxi",
    "XGJtb25ldGlzXHcq",
    "XGJtb25ldGl6XHcq",
    "XGJjaGF0Z3B0XGI=",
    "XGJhc3NlbWJseVxzP2FpXGI=",
    "XGJkZWVwZ3JhbVxi",
    "XGJlbGV2ZW5ccz9sYWJzXGI=",
    "XGJvdXJccysodXNlcnN8Y3VzdG9tZXJzKVxzK3dpbGxcYg==",
    "XGJ0aGVccyt1c2VyXHMrKHNhaWR8YXNrZWR8d2FudHN8cmVxdWVzdGVkKVxi",
    "XGJpblxzKyh0aGlzfG91cilccytzZXNzaW9uXGI=",
    "XGJtYXJrZXQoaW5nKT9ccysoYW5nbGV8bWVzc2FnZXxjb3B5KVxi",
]


def compile_terms(encoded):
    """Decodes the patterns and compiles them, refusing to run on a malformed constant."""
    patterns = []
    for token in encoded:
        try:
            source = base64.b64decode(token, validate=True).decode()
        except Exception:
            sys.exit(f"disclosure audit: a term constant is malformed ({token}). Fix it.")
        patterns.append(re.compile(source, re.IGNORECASE))
    return patterns


NAMES = compile_terms(NAMES_B64)
PHRASES = compile_terms(PHRASES_B64)
TIER1 = NAMES + PHRASES
TIER2 = compile_terms(TIER2_B64)


def hits(text, patterns):
    """Yields (line_number, line, matched_text) for every match in a block of text."""
    for number, line in enumerate(text.split("\n"), start=1):
        for pattern in patterns:
            found = pattern.search(line)
            if found:
                yield number, line.strip()[:160], found.group(0)


def git(*args):
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, errors="ignore"
    ).stdout


def tree_files():
    """Every file a clone would carry, plus every file written but not yet staged."""
    listed = git("ls-files", "--cached", "--others", "--exclude-standard").split("\n")
    return [path for path in listed if path and path not in SELF]


def read(path):
    try:
        with open(path, errors="ignore") as handle:
            return handle.read()
    except (OSError, IsADirectoryError):
        return ""


def report(findings, tier, what):
    print(f"\n  ✗ {what} carries {tier} text that must not be published\n")
    for where, number, line, matched in findings:
        location = f"{where}:{number}" if number else where
        print(f"    {location}")
        print(f"      matched {matched!r}  in  {line}")
    print()


def added_lines(patch):
    """The added side of a diff, kept per file so path rules still apply to it.

    Flattening a patch into one block loses which file each line came from, and with it
    every exemption the tree scan honours: the corpus carve-out, and this script's own
    prose about what it forbids. The gate refused its own introduction that way once.
    """
    per_file, path = {}, None
    for line in patch.split("\n"):
        if line.startswith("diff --git "):
            path = line.split(" b/", 1)[-1] if " b/" in line else None
        elif line.startswith("+") and not line.startswith("+++") and path:
            per_file.setdefault(path, []).append(line[1:])
    return {path: "\n".join(lines) for path, lines in per_file.items()}


def scan_diff(patch, label):
    """Scans a commit's added lines, file by file, under the same rules as the tree.

    Tier one only. The vocabulary tier is ratcheted per file against a baseline, and the
    tree scan is what owns that: judging it again on a diff double-counts, and can never
    be satisfied by a file that legitimately sits above zero.
    """
    findings = []
    for path, text in sorted(added_lines(patch).items()):
        if path in SELF:
            continue
        patterns = NAMES if path.startswith(CORPUS) else TIER1
        findings += [(path, n, line, m) for n, line, m in hits(text, patterns)]
    if findings:
        report(findings, "forbidden", label)
    return bool(findings)


def scan_text(text, label, strict=True):
    """Scans one block of new writing. Both tiers block: new text has no legacy."""
    one = [("line", n, line, m) for n, line, m in hits(text, TIER1)]
    two = [("line", n, line, m) for n, line, m in hits(text, TIER2)] if strict else []
    if one:
        report(one, "forbidden", label)
    if two:
        report(two, "internal-vocabulary", label)
    return bool(one or two)


def scan_tree():
    files = tree_files()
    if len(files) < 100:
        print(f"disclosure audit: only {len(files)} files found — this is not the tree.")
        print("Every check below would pass trivially on an empty list, so it stops here.")
        return 1, {}

    print(f"What is being scanned\n  ✓ {len(files)} files (tracked, plus not yet staged)")

    forbidden, counts = [], {}
    for path in files:
        text = read(path)
        if not text:
            continue
        patterns = NAMES if path.startswith(CORPUS) else TIER1
        for number, line, matched in hits(text, patterns):
            forbidden.append((path, number, line, matched))
        found = sum(1 for _ in hits(text, TIER2))
        if found:
            counts[path] = found

    if forbidden:
        report(forbidden, "forbidden", "the working tree")
        print("  Nothing here may be committed. See AGENTS.md, \"What must never reach a")
        print("  tracked file\". Take the requirement out of the reference and state it in")
        print("  the product's own words; the reference itself does not stay.\n")
        return 1, counts

    print("  ✓ no competitor, strategy or session text in any file")
    return 0, counts


def check_ratchet(counts):
    """Fails when any file gained internal vocabulary. What is here already is recorded."""
    if not os.path.exists(BASELINE):
        print(f"\nNo baseline at {BASELINE}. Record one:")
        print(f"  python3 {sys.argv[0]} --update-baseline")
        return 1

    recorded = json.load(open(BASELINE)).get("files", {})
    risen = [
        f"{path}: {count} occurrences, was {recorded.get(path, 0)}"
        for path, count in sorted(counts.items())
        if count > recorded.get(path, 0)
    ]
    if risen:
        print("\n  ✗ these files gained internal vocabulary\n")
        for line in risen:
            print(f"    {line}")
        print("\n  Words like these are usually innocent, which is why they are counted")
        print("  rather than banned. The count may fall and may not rise. Say the same")
        print("  thing in the product's own vocabulary, or bring the file down first.")
        print(f"  See them:  python3 {sys.argv[0]} --show-terms\n")
        return 1

    total = sum(counts.values())
    print(f"  ✓ internal vocabulary: {total} occurrences, none above the baseline")
    return 0


def update_baseline(counts, absorb=False):
    """Records the current counts, and refuses to record a rise unless told to absorb it."""
    # A first run has nothing to compare against, and treating an absent baseline as
    # all-zeros would make every existing occurrence read as a rise and refuse forever.
    first_run = not os.path.exists(BASELINE)
    recorded = {} if first_run else json.load(open(BASELINE)).get("files", {})
    risen = {p: (recorded.get(p, 0), c) for p, c in counts.items() if c > recorded.get(p, 0)}
    if risen and not first_run and not absorb:
        print("Refusing to record a rise. These would go up:\n")
        for path, (was, now) in sorted(risen.items()):
            print(f"  {path}: {was} -> {now}")
        print("\nThe baseline is a ratchet. Bring the file down instead.")
        print("If the rise is the rule itself — a document that has to name the category")
        print("it forbids — record it with --absorb, which prints every rise so it lands")
        print("in the baseline's diff where a reviewer will see it.")
        return 1
    if risen and absorb:
        print("Absorbing a rise. Each of these is a claim that the word belongs there:\n")
        for path, (was, now) in sorted(risen.items()):
            print(f"  {path}: {was} -> {now}")
        print()
    json.dump(
        {"total": sum(counts.values()), "files": dict(sorted(counts.items()))},
        open(BASELINE, "w"),
        indent=2,
    )
    print(f"Recorded {sum(counts.values())} occurrences across {len(counts)} files.")
    return 0


def scan_range(rev_range):
    """Every commit message and every added line in a range of commits."""
    shas = [s for s in git("log", "--format=%H", rev_range).split("\n") if s]
    if not shas:
        print(f"  ✓ {rev_range} adds no commits")
        return 0
    bad = False
    for sha in shas:
        subject = git("log", "-1", "--format=%s", sha).strip()
        message = git("log", "-1", "--format=%B", sha)
        if scan_text(message, f"commit {sha[:8]} message ({subject})"):
            bad = True
        patch = git("show", "--format=", "--no-color", sha)
        if scan_diff(patch, f"commit {sha[:8]} diff ({subject})"):
            bad = True
    if not bad:
        print(f"  ✓ {len(shas)} commit(s) in {rev_range}: messages and diffs clean")
    return 1 if bad else 0


def scan_history():
    """Every commit on every ref. What a repository about to go public is judged on."""
    shas = [s for s in git("log", "--all", "--format=%H").split("\n") if s]
    print(f"Scanning {len(shas)} commits across every ref")
    bad = False
    for sha in shas:
        message = git("log", "-1", "--format=%B", sha)
        if scan_text(message, f"commit {sha[:8]} message", strict=False):
            bad = True
        patch = git("show", "--format=", "--no-color", sha)
        if scan_diff(patch, f"commit {sha[:8]} diff"):
            bad = True
    if not bad:
        print(f"  ✓ nothing forbidden in {len(shas)} commits")
    else:
        print("  History cannot be fixed by a later commit. Anything above is already")
        print("  published if this repository is public, and rewriting reaches no clone,")
        print("  cache or fork. Report it rather than quietly removing it.")
    return 1 if bad else 0


def scan_hook():
    """Reads Claude Code's PreToolUse payload and blocks the command before it runs."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    tool = payload.get("tool_name", "")
    fields = payload.get("tool_input", {})
    text = fields.get("command", "") if tool == "Bash" else json.dumps(fields)
    # Only the commands that publish. Everything else an agent runs is its own business.
    if tool == "Bash" and not re.search(
        r"\bgit\s+(commit|push|tag|notes)\b|\bgh\s+(pr|issue|release|api|repo)\b", text
    ):
        return 0
    found = [m for _, _, m in hits(text, TIER1)]
    if not found:
        return 0
    names = ", ".join(sorted(set(found)))
    print(
        f"Blocked: this command would publish text the repository rule forbids ({names}).\n"
        "AGENTS.md, \"What must never reach a tracked file\": named competitors, growth or\n"
        "business strategy, and session talk never reach a commit, a PR, an issue or a\n"
        "tracked file. State the requirement in the product's own words instead.",
        file=sys.stderr,
    )
    return 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--range", help="commit messages and added lines in A..B")
    group.add_argument("--history", action="store_true", help="every commit on every ref")
    group.add_argument("--text", action="store_true", help="scan stdin as new writing")
    group.add_argument("--hook", action="store_true", help="Claude Code PreToolUse gate")
    group.add_argument("--show-terms", action="store_true", help="print the terms decoded")
    parser.add_argument("--update-baseline", action="store_true", help="record tier-2 counts")
    parser.add_argument(
        "--absorb",
        action="store_true",
        help="with --update-baseline, record a rise instead of refusing it",
    )
    parser.add_argument("--label", default="stdin", help="what --text is scanning")
    options = parser.parse_args()

    if options.show_terms:
        listing = (("Forbidden names", NAMES), ("Forbidden phrases", PHRASES),
                   ("Counted vocabulary", TIER2))
        for name, patterns in listing:
            print(f"\n{name}:")
            for pattern in patterns:
                print(f"  {pattern.pattern}")
        return 0
    if options.hook:
        return scan_hook()
    if options.text:
        return 1 if scan_text(sys.stdin.read(), options.label) else 0
    if options.history:
        return scan_history()
    if options.range:
        return scan_range(options.range)

    status, counts = scan_tree()
    if options.update_baseline:
        return update_baseline(counts, absorb=options.absorb)
    if status:
        return status
    return check_ratchet(counts)


if __name__ == "__main__":
    sys.exit(main())

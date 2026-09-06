#!/usr/bin/env bash
#
# Catches documentation that has drifted away from the tree it describes.
#
# Two issues in this repository were the same bug wearing different clothes. In #77 the
# source paths in `Docs/predict-context.md` were written module-relative — `UttrflowPredict/
# Verifier.swift` rather than `Sources/UttrflowPredict/Verifier.swift` — so none of them
# resolved from the repository root, and nobody noticed because they look right to a reader
# who already knows the layout. In #76 the size of the test suite was documented as 2,640 in
# one file and 2,900 in three others while the real number was 4,038; every one of those was
# true on the day it was written.
#
# Neither was carelessness. Prose has no compiler, so a claim about the tree is checked
# exactly once — when it is typed — and then decays silently while the tree moves under it.
# Both classes recur for the same reason a convention lasts only as long as the person who
# remembers it, which is why this is a gate rather than a line in a review checklist.
#
# The cost of the drift is paid by whoever trusts the document: a path that does not resolve
# sends a new contributor looking for a file that is not there, and a test count that is off
# by a third makes every other number in the same sentence suspect.
#
# This audit is deliberately narrow. It checks claims that the tree can contradict — does
# this file exist, does this link resolve, is this number still true — and nothing about
# whether the prose around them is accurate, which no script can answer. It needs no build.
#
# Usage:  ./Scripts/docs_audit.sh        (belongs in `make verify`, ahead of the build)
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

failures=0

# Each failure says what broke and why it matters. The same shape as pii_audit.sh, and for
# the same reason: "docs_audit.sh: FAILED" tells the next person nothing they can act on.
fail() {
    printf '\n  ✗ %s\n' "$1" >&2
    shift
    for line in "$@"; do printf '    %s\n' "$line" >&2; done
    failures=$((failures + 1))
}

pass() { printf '  ✓ %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 0. The scan must actually be looking at something.
# ---------------------------------------------------------------------------
#
# An audit that silently scans nothing is worse than no audit, because it reports success.
# This repository has been caught by that before, in `BackendContractTests`, which returned
# nil for a missing fixture and so could not tell a wrong path from an absent backend.
#
# `--others --exclude-standard` here and below, because a document written but not yet
# staged is exactly the one most likely to have a fresh path in it. Ignored paths stay out:
# .build and dist are generated, and nothing in them is ours to police.
DOCS="$(git ls-files --cached --others --exclude-standard -- '*.md' | grep -Ev '^([^/]+/)*\.' || true)"
DOC_COUNT="$(printf '%s' "$DOCS" | grep -c . || true)"

printf 'What is being scanned\n'

if [[ "$DOC_COUNT" -lt 20 ]]; then
    fail "only $DOC_COUNT Markdown files found — this is not the Uttrflow tree" \
        "Either this is not a git checkout, or it is a partial one. Every check below" \
        "would pass trivially on an empty file list, which is why this stops here."
    printf '\ndocs audit: could not run.\n\n' >&2
    exit 1
fi
pass "$DOC_COUNT Markdown files (tracked, plus written-but-not-yet-staged)"

# ---------------------------------------------------------------------------
# 1. Every backticked path that claims to be a file in this repository exists.
# ---------------------------------------------------------------------------
#
# The rule, in full, and why each half of it is there:
#
#   A token in backticks is a candidate only if it ends in one of the extensions this
#   repository actually contains — .swift .sh .py .md .toml .yml .yaml .json .plist .lock.
#   Prose is full of backticks that are not paths at all, and an extension is the cheapest
#   evidence that one was meant.
#
#   A candidate is skipped if it holds whitespace, a glob or a placeholder — `* ? [ ] < > {`
#   or `...`. `Catalogue*.swift` names a family of files and `prompts/<destination>.json`
#   names a shape; neither is wrong, and neither can be checked by asking the filesystem.
#   Tokens that begin `~`, `/` or a URL scheme are somebody's machine or the internet, and
#   `./` and `../` are relative to a document rather than to the root, which check 3 covers.
#
#   A candidate that exists relative to the root passes, and is the common case.
#
#   One that does not is looked for under Sources/ and Tests/. A unique hit there is the
#   #77 bug exactly — a real file written from the middle of the tree instead of the top —
#   and is reported with the path that would have worked.
#
#   Otherwise it is a failure only if it holds a `/` and its first segment is a real
#   top-level entry of this repository. That last clause is the whole false-positive
#   defence: `Contents/Resources/…gpt2_tokenizer_config.json` is the interior of a built
#   app bundle and `node_modules/x.json` would be a dependency's, and neither exists here
#   nor should. Requiring the first segment to be ours means a token is checked only when
#   the tree is genuinely the authority on whether it exists.
#
#   Bare filenames — no `/` at all — are not checked, because `Package.resolved` and
#   `bundle.sh` are used in sentences far more often than as paths, and guessing which was
#   meant produces noise. The exception is a short allowlist of root files the repository
#   cannot function without; those are named here and must exist.
printf '\nBackticked paths\n'

read -r -d '' PATH_PROGRAM <<'PYTHON' || true
import os
import re
import subprocess
import sys

# Root files that are load-bearing, so a bare mention of one is worth checking.
ROOT_ALLOWLIST = {
    "AGENTS.md", "CHANGELOG.md", "CLAUDE.md", "CODE_OF_CONDUCT.md", "CONTRIBUTING.md",
    "LICENSE.md", "PLAN.md", "Package.resolved", "Package.swift", "README.md",
    "RELEASING.md", "SECURITY.md", "TRADEMARK.md",
}
EXTENSIONS = (
    ".swift", ".sh", ".py", ".md", ".toml", ".yml", ".yaml", ".json", ".plist", ".lock",
)
UNCHECKABLE = re.compile(r"[\s*?\[\]<>{}|$]|\.\.\.")
ELSEWHERE = re.compile(r"^(~|/|\.{1,2}/|[a-z][a-z0-9+.-]*://)")

documents = sys.stdin.read().split("\n")
top_level = {name for name in os.listdir(".") if not name.startswith(".")}
searched = {}
for root in ("Sources", "Tests"):
    for directory, _, names in os.walk(root):
        for name in names:
            searched.setdefault(name, []).append(os.path.join(directory, name))

missing, misrooted = [], []
for document in documents:
    if not document:
        continue
    for number, line in enumerate(open(document, errors="ignore"), 1):
        for token in re.findall(r"`([^`\n]+)`", line):
            if not token.endswith(EXTENSIONS):
                continue
            if UNCHECKABLE.search(token) or ELSEWHERE.match(token):
                continue
            if os.path.exists(token):
                continue
            # A real file named from inside a module rather than from the root: #77.
            candidates = [
                path for path in searched.get(os.path.basename(token), [])
                if path.endswith("/" + token)
            ]
            if "/" in token and len(candidates) == 1:
                misrooted.append((document, number, token, candidates[0]))
            elif "/" in token:
                if token.split("/", 1)[0] in top_level:
                    missing.append((document, number, token))
            elif token in ROOT_ALLOWLIST:
                missing.append((document, number, token))

for document, number, token, actual in sorted(misrooted):
    print(f"MISROOTED\t{document}:{number}\t{token}\t{actual}")
for document, number, token in sorted(missing):
    print(f"MISSING\t{document}:{number}\t{token}")
PYTHON
path_report="$(python3 -c "$PATH_PROGRAM" <<<"$DOCS")"

misrooted="$(printf '%s\n' "$path_report" | grep '^MISROOTED' | cut -f2- | sed 's/\t/  →  /g' || true)"
missing="$(printf '%s\n' "$path_report" | grep '^MISSING' | cut -f2- | sed 's/\t/  /g' || true)"

if [[ -n "${misrooted//[[:space:]]/}" ]]; then
    fail "a documented path is written from inside a module, not from the repository root" \
        "The file is real, but the path as written does not resolve from where anybody" \
        "reading the document is standing. This is issue #77, and it came back." \
        "" \
        "Each line below is what was written, then the path that would have worked:" \
        "" $'\n'"$misrooted"
fi

if [[ -n "${missing//[[:space:]]/}" ]]; then
    fail "a documented path does not exist in this tree" \
        "Either the file moved and the document did not, or it was never written." \
        "A path that does not resolve sends the next reader looking for nothing." \
        "" $'\n'"$missing"
fi

if [[ -z "${misrooted//[[:space:]]/}" && -z "${missing//[[:space:]]/}" ]]; then
    pass "every backticked path that names a file in this tree resolves from the root"
fi

# ---------------------------------------------------------------------------
# 2. No stale hard-coded test count.
# ---------------------------------------------------------------------------
#
# The count of record is the number of `@Test` declarations under Tests/, which is what
# `swift test` reports and what every one of these sentences is trying to say.
#
# An exact figure — "2,640 tests", "~2,900 tests" — is allowed to drift by a tenth, because
# prose is written once and the suite grows every week, and a gate that fires on a single
# new test would be switched off within a month.
#
# A floor — "2,900+ tests", "over 4,000 tests" — fails when it is above the real count,
# which makes it false. It also fails when it is more than a quarter below, which does not
# make it false but does make it useless: "2,900+" for a suite of 4,038 understates the gate
# by a third, and a reader who acts on it is as misled as by a wrong exact number. "4,000+"
# stays true and stays useful, which is what a floor is for.
#
# Two things are skipped, both because they are records rather than claims. PLAN.md is an
# append-only phase log where each entry states the count on the day it was written, and
# rewriting those would be a lie. So is a line in Swift Testing's own summary format — `Test
# run with 579 tests in 83 suites` in `Docs/offline.md` is the transcript of one filtered
# run. Fenced code blocks as a whole are *not* skipped: three of the #76 claims lived in a
# `make verify` snippet inside one.
printf '\nThe test count\n'

REAL_TESTS="$(git grep --untracked -hoE '^[[:space:]]*@Test' -- 'Tests/**/*.swift' | wc -l | tr -d ' ')"

if [[ "$REAL_TESTS" -lt 100 ]]; then
    fail "only $REAL_TESTS @Test declarations found under Tests/" \
        "That is not this suite, so every comparison below would be meaningless."
else
    read -r -d '' COUNT_PROGRAM <<'PYTHON' || true
import re
import sys

real = int(sys.argv[1])
DRIFT = 0.10
UNDERSTATEMENT = 0.25
# "2,640 tests", "2,900+ tests", "~2,900 tests", "runs 2,922 tests", "4 038 tests". The gap
# before "tests" may hold a newline and a comment marker, because `.githooks/pre-push` wraps
# one of these mid-claim and a line-at-a-time reader walks straight past it.
CLAIM = re.compile(
    r"(~|about |roughly |over |at least )?"
    r"([0-9][0-9,_  ]*[0-9]|[0-9])(\+)?[\s#>*]{1,8}tests\b"
)
# Swift Testing's own summary line, which reports a run that happened, not the suite.
TRANSCRIPT = re.compile(r"Test run with [0-9,  ]+ tests")

for document in sys.stdin.read().split("\n"):
    if not document:
        continue
    text = open(document, errors="ignore").read()
    for match in CLAIM.finditer(text):
        approximate, digits, plus = match.groups()
        number = text.count("\n", 0, match.start()) + 1
        line = text.split("\n")[number - 1].strip()
        if TRANSCRIPT.search(line):
            continue
        stated = int(re.sub(r"[^0-9]", "", digits))
        floor = bool(plus) or (approximate or "").strip() in ("over", "at least")
        if floor:
            wrong = stated > real or stated < real * (1 - UNDERSTATEMENT)
        else:
            wrong = abs(stated - real) > real * DRIFT
        if wrong:
            print(f"{document}:{number}  {line}")
PYTHON
    claims="$(
        git ls-files --cached --others --exclude-standard \
            -- '*.md' 'Makefile' '.githooks/*' '.github/workflows/*' \
        | grep -v '^PLAN\.md$' \
        | python3 -c "$COUNT_PROGRAM" "$REAL_TESTS"
    )"

    if [[ -n "${claims//[[:space:]]/}" ]]; then
        fail "a documented test count no longer matches the suite" \
            "The suite currently holds $REAL_TESTS tests. Each line below states a figure" \
            "that is out by more than a tenth, or a floor that is false or so far under" \
            "the suite that it misleads. This is issue #76, and every one of these was" \
            "true on the day it was typed." \
            "" \
            "Write $REAL_TESTS, or write a floor that will still be worth reading when" \
            "the suite has grown past it." \
            "" $'\n'"$claims"
    else
        pass "$REAL_TESTS tests, and every documented count still says so"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Every relative Markdown link resolves.
# ---------------------------------------------------------------------------
#
# `[text](path)` and `[text](path#anchor)`, resolved against the directory of the document
# holding them, which is how a reader's browser and GitHub both resolve them. External URLs,
# `mailto:`, and bare `#anchor` links into the same page are somebody else's to check.
printf '\nRelative links\n'

read -r -d '' LINK_PROGRAM <<'PYTHON' || true
import os
import re
import sys

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
EXTERNAL = re.compile(r"^([a-z][a-z0-9+.-]*:|//|#)")

for document in sys.stdin.read().split("\n"):
    if not document:
        continue
    directory = os.path.dirname(document) or "."
    for number, line in enumerate(open(document, errors="ignore"), 1):
        for target in LINK.findall(line):
            if EXTERNAL.match(target):
                continue
            path = target.split("#", 1)[0]
            if not path:
                continue
            if not os.path.exists(os.path.join(directory, path)):
                print(f"{document}:{number}  [...]({target})")
PYTHON
broken_links="$(python3 -c "$LINK_PROGRAM" <<<"$DOCS")"

if [[ -n "${broken_links//[[:space:]]/}" ]]; then
    fail "a relative Markdown link points at a file that is not there" \
        "Resolved against the directory of the document holding it, which is how a" \
        "reader's browser resolves it. Either the target moved or the link was a guess." \
        "" $'\n'"$broken_links"
else
    pass "every relative link resolves from the document that holds it"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [[ "$failures" -gt 0 ]]; then
    printf 'docs audit: %s check(s) failed. The documentation contradicts the tree.\n\n' "$failures" >&2
    exit 1
fi

printf 'docs audit: the paths, links and test count in %s documents all check out.\n\n' "$DOC_COUNT"

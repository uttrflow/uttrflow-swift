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
# Usage:  ./Scripts/docs_audit.sh            (belongs in `make verify`, ahead of the build)
#         ./Scripts/docs_audit.sh --self-test   also runs the CLAUDE.md delegation fixture
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SELF_TEST=0
if [[ "${1:-}" == "--self-test" ]]; then
    SELF_TEST=1
    shift
fi
if [[ "$#" -ne 0 ]]; then
    printf 'usage: %s [--self-test]\n' "$0" >&2
    exit 2
fi

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

changelog_release_bullet_findings() {
    read -r -d '' CHANGELOG_PROGRAM <<'PYTHON' || true
import re
import sys

heading = re.compile(r"^## \[([^\]]+)\]")
current = None
for number, line in enumerate(open("CHANGELOG.md", errors="ignore"), 1):
    match = heading.match(line)
    if match:
        current = match.group(1)
        continue
    if current and current != "Unreleased" and line.startswith("- "):
        print(f"{current}\t{number}\t{line.rstrip()}")
PYTHON

    python3 -c "$CHANGELOG_PROGRAM" |
    while IFS=$'\t' read -r version line bullet; do
        [[ -n "$version" ]] || continue
        tag="v$version"
        tag_commit="$(git rev-parse --verify --quiet "$tag^{commit}" || true)"
        [[ -n "$tag_commit" ]] || continue

        origin="$(
            git blame --line-porcelain -L "$line,$line" -- CHANGELOG.md |
                sed -n '1s/ .*//p'
        )"
        [[ -n "$origin" && "$origin" != 00000000* ]] || continue

        if ! git merge-base --is-ancestor "$origin" "$tag_commit"; then
            printf '%s:%s  %s  (line added by %s after %s)\n' \
                "CHANGELOG.md" "$line" "$bullet" "$origin" "$tag"
        fi
    done
}

run_changelog_self_test() {
    printf 'CHANGELOG release-bullet fixture\n'

    local scratch
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' RETURN

    write_changelog() {
        local mode="$1"
        cat >CHANGELOG.md <<'EOF'
# Changelog

## [Unreleased]

### Fixed
EOF
        if [[ "$mode" == "unreleased" ]]; then
            cat >>CHANGELOG.md <<'EOF'
- **A post-tag fix waits here.** It belongs to the next release (#2).
EOF
        fi
        cat >>CHANGELOG.md <<'EOF'

## [2026.9.14] — 2026-09-14

### Fixed
- **The shipped fix.** It is part of the tagged build (#1).
EOF
        if [[ "$mode" == "released" ]]; then
            cat >>CHANGELOG.md <<'EOF'
- **A post-tag fix is misfiled here.** It is not part of the tagged build (#2).
EOF
        fi
    }

    (
        set -euo pipefail
        cd "$scratch"
        git init -q
        git config user.name "Docs Audit"
        git config user.email "docs-audit@example.invalid"

        write_changelog tagged
        git add CHANGELOG.md
        git commit -qm "Release notes"
        git tag v2026.9.14

        write_changelog unreleased
        git add CHANGELOG.md
        git commit -qm "Keep next fix unreleased"
        changelog_release_bullet_findings
    ) >"$scratch/unreleased.out"

    if [[ -s "$scratch/unreleased.out" ]]; then
        fail "an Unreleased post-tag bullet failed the fixture" \
            "The release-bullet check must allow fixes queued for the next release." \
            "" $'\n'"$(cat "$scratch/unreleased.out")"
    else
        pass "post-tag bullet under Unreleased passes"
    fi

    (
        set -euo pipefail
        cd "$scratch"
        git reset -q --hard v2026.9.14
        write_changelog released
        git add CHANGELOG.md
        git commit -qm "Misfile next fix under old release"
        changelog_release_bullet_findings
    ) >"$scratch/released.out"

    if [[ -s "$scratch/released.out" ]]; then
        pass "post-tag bullet under a tagged release fails"
    else
        fail "a released-section post-tag bullet passed the fixture" \
            "The fixture recreated issue #1123, but the audit did not report it."
    fi
}

if [[ "$SELF_TEST" -eq 1 ]]; then
    run_changelog_self_test
    printf '\n'
fi

# The CLAUDE.md delegation check, factored so `--self-test` can call it against fixtures.
# Sets `claude_md_problem` (the failure reason, empty on pass) and returns 0/1.
claude_md_problem=""
check_claude_md_delegation() {
    local root="$1"
    claude_md_problem=""
    if [[ ! -e "$root/CLAUDE.md" ]]; then
        return 0
    fi
    if [[ -L "$root/CLAUDE.md" ]]; then
        local target
        target="$(readlink "$root/CLAUDE.md")"
        if [[ "$target" != "AGENTS.md" ]]; then
            claude_md_problem="CLAUDE.md is a symlink, but to '$target', not AGENTS.md"
            return 1
        fi
        if [[ ! -e "$root/AGENTS.md" ]]; then
            claude_md_problem="CLAUDE.md is a symlink to AGENTS.md, but $root/AGENTS.md is not there"
            return 1
        fi
        return 0
    fi
    local first
    first="$(grep -vE '^[[:space:]]*(#|$)' "$root/CLAUDE.md" | head -n1 | tr -d '\r' || true)"
    if [[ "$first" != "@AGENTS.md" ]]; then
        if [[ -z "$first" ]]; then
            claude_md_problem="CLAUDE.md is empty; it should be an '@AGENTS.md' import or a real symlink"
        else
            claude_md_problem="CLAUDE.md is neither an '@AGENTS.md' import nor a symlink to AGENTS.md (first non-blank, non-comment line: '$first')"
        fi
        return 1
    fi
    if [[ ! -e "$root/AGENTS.md" ]]; then
        claude_md_problem="CLAUDE.md imports AGENTS.md, but $root/AGENTS.md is not there"
        return 1
    fi
    return 0
}

# Two argument rules `uttrflow-eval` enforces at runtime, re-derived statically so a
# documented example can be checked without a build. See RecordCorpus.swift and
# TranscribeCorpus.swift. Factored so `--self-test` can call it against fixtures.
read -r -d '' UTTRFLOW_EVAL_CONTRACT_PROGRAM <<'PYTHON' || true
import sys

documents = sys.stdin.read().split("\n")
findings = []
for document in documents:
    if not document:
        continue
    in_fence = False
    for number, line in enumerate(open(document, errors="ignore"), 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence or "uttrflow-eval" not in line:
            continue
        tokens = line.split()
        if "record" in tokens and "--sync" in tokens and (
            "--cohort" in tokens or "--speaker" in tokens or "--setting" in tokens
        ):
            findings.append((
                document, number, stripped,
                "record --sync exits before the recording queue exists — a recording "
                "flag (--cohort/--speaker/--setting) alongside it documents a command "
                "that records nothing",
            ))
        if "transcribe" in tokens and (
            "--save-baseline" in tokens or "--fail-on-regression" in tokens
        ) and "--baseline" not in tokens:
            findings.append((
                document, number, stripped,
                "transcribe --save-baseline/--fail-on-regression needs --baseline "
                "<path>, or TranscribeCorpus.validate() rejects it",
            ))

for document, number, line, reason in findings:
    print(f"{document}:{number}\t{line}\t{reason}")
PYTHON

uttrflow_eval_contract_findings() {
    python3 -c "$UTTRFLOW_EVAL_CONTRACT_PROGRAM"
}

run_uttrflow_eval_contract_self_test() {
    local work
    work="$(mktemp -d -t uttrflow-docs-audit-cli.XXXXXX)"

    cat >"$work/good.md" <<'DOC'
```bash
uttrflow-eval record --backend <url> --cohort <reader>-quiet --upload
uttrflow-eval record --backend <url> --sync
uttrflow-eval transcribe --from-catalogue --backend <url> --baseline ./b.json --save-baseline
```
DOC
    cat >"$work/bad.md" <<'DOC'
```bash
uttrflow-eval record --backend <url> --cohort <reader>-quiet --sync
uttrflow-eval transcribe --from-catalogue --save-baseline
```
DOC

    printf 'uttrflow-eval example self-test\n'

    local good_report
    good_report="$(printf '%s\n' "$work/good.md" | uttrflow_eval_contract_findings)"
    if [[ -z "${good_report//[[:space:]]/}" ]]; then
        pass "a compliant record/transcribe example passes"
    else
        fail "a compliant example was flagged" "$good_report"
    fi

    local bad_report
    bad_report="$(printf '%s\n' "$work/bad.md" | uttrflow_eval_contract_findings)"
    if [[ "$(printf '%s\n' "$bad_report" | grep -c .)" -eq 2 ]]; then
        pass "record --sync-as-recording and transcribe without --baseline both fail"
    else
        fail "the self-test's two known-bad lines were not both caught" "$bad_report"
    fi

    rm -rf "$work"
}

if [[ "$SELF_TEST" -eq 1 ]]; then
    run_uttrflow_eval_contract_self_test
    printf '\n'
fi

# `--self-test` runs the CLAUDE.md delegation fixture before the normal scan, so the
# audit's checks themselves fail noisily when they stop biting. Same pattern as
# log_privacy_audit.py and perf_budget_audit.py.
if [[ "$SELF_TEST" -eq 1 ]]; then
    work="$(mktemp -d -t uttrflow-docs-audit.XXXXXX)"
    trap 'rm -rf "$work"' EXIT

    declare -a cases=(
        "no-file:absent::0"
        "at-import:at-import:@AGENTS.md\\n:0"
        "symlink:symlink::0"
        "markdown-link:markdown-link:See [AGENTS.md](AGENTS.md).\\n:1"
        "prose-blurb:prose-blurb:Read AGENTS.md for the rules.\\n:1"
        "empty:empty::1"
        "hash-only:hash-only:# heading\\n:1"
        "missing-target:missing-target:@AGENTS.md\\n:1"
    )

    printf 'CLAUDE.md delegation fixture\n'

    for case in "${cases[@]}"; do
        IFS=':' read -r label slug body expect_fail <<<"$case"
        case_dir="$work/$slug"
        mkdir -p "$case_dir"
        case "$label" in
            no-file) ;;
            missing-target) printf '%b' "$body" > "$case_dir/CLAUDE.md" ;;
            symlink) : > "$case_dir/AGENTS.md"; ln -s AGENTS.md "$case_dir/CLAUDE.md" ;;
            *) : > "$case_dir/AGENTS.md"; printf '%b' "$body" > "$case_dir/CLAUDE.md" ;;
        esac

        if check_claude_md_delegation "$case_dir"; then
            actual="pass"
        else
            actual="fail"
        fi
        expected="pass"; [[ "$expect_fail" == "1" ]] && expected="fail"

        if [[ "$actual" == "$expected" ]]; then
            pass "$label ($body → $actual)"
        else
            fail "self-test case '$label' was expected to $expected but the audit said $actual" \
                "body written into CLAUDE.md: $body" \
                "claude_md_problem: ${claude_md_problem:-<none>}"
        fi
    done

    if [[ "$failures" -gt 0 ]]; then
        printf '\ndocs audit self-test: %s case(s) did not match.\n\n' "$failures" >&2
        exit 1
    fi
    printf '\ndocs audit self-test: every fixture case behaved as expected.\n\n'
    failures=0
fi

cd "$PACKAGE_ROOT"

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
# 0a. The documented pull-request lifecycle must match the live main ruleset.
# ---------------------------------------------------------------------------
#
# Issue #1120 was not a typo but a blocked lifecycle: AGENTS.md said a green PR could be
# self-merged while the live ruleset required independent review. The ruleset itself is
# outside this tree, so this check keeps the local policy on the review-required side of
# that boundary until the ruleset is deliberately changed.
printf '\nPull request lifecycle\n'

if grep -Fq "**An agent may merge its own pull request once it is green**" AGENTS.md; then
    fail "AGENTS.md still documents the removed self-merge rule" \
        "The live main ruleset requires an approving review, code-owner review and" \
        "last-pusher approval. A local policy that says agents may merge themselves" \
        "sends finished pull requests into a gate they cannot satisfy."
fi

missing_policy=()
for required in \
    "release-policy:v4" \
    "requires one approving review" \
    "code-owner review" \
    "approval by someone other than the last pusher" \
    "strict_required_status_checks_policy" \
    "Keep the worktree and branch while the PR is open"
do
    if ! grep -Fq "$required" AGENTS.md; then
        missing_policy+=("$required")
    fi
done

if ((${#missing_policy[@]})); then
    fail "AGENTS.md no longer records the review-required main ruleset" \
        "The policy must tell agents that implementation stops at a green pull request," \
        "and must name the live ruleset gates that enforce that boundary." \
        "" $'\n'"$(printf '    %s\n' "${missing_policy[@]}")"
else
    pass "AGENTS.md says agents stop at a green PR and names the review gates"
fi

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
# 4. The worktree cleanup recipe must wait for a merged pull request.
# ---------------------------------------------------------------------------
#
# The contributor recipe once opened a pull request and immediately deleted the worktree,
# local branch and remote branch. `git branch -d` does not prove the branch reached `main`;
# it can succeed when the local branch is merely merged to its upstream. The doc must keep
# every cleanup command below a GitHub merged-state check.
printf '\nWorktree cleanup order\n'

read -r -d '' CLEANUP_PROGRAM <<'PYTHON' || true
import re

text = open("AGENTS.md", errors="ignore").read()
start = text.find("**Every feature is built in a worktree")
end = text.find("`sasta-trader` is a different project", start)
if start == -1 or end == -1:
    print("AGENTS.md  cannot find the worktree recipe section")
    raise SystemExit

section = text[start:end]
required = [
    ("pull request creation", r"^gh pr create --base main"),
    ("GitHub merge-state check", r"^gh pr view [^\n]*--json mergedAt"),
    ("worktree removal", r"^git worktree remove"),
    ("local branch deletion", r"^git branch -[dD]"),
    ("remote branch deletion", r"^git push origin --delete"),
]

positions = {}
for name, pattern in required:
    match = re.search(pattern, section, re.MULTILINE)
    if not match:
        print(f"AGENTS.md  missing {name}: {pattern}")
    else:
        positions[name] = match.start()

merge = positions.get("GitHub merge-state check")
if merge is not None:
    for name in ("worktree removal", "local branch deletion", "remote branch deletion"):
        where = positions.get(name)
        if where is not None and where < merge:
            print(f"AGENTS.md  {name} appears before the GitHub merge-state check")

create = positions.get("pull request creation")
if create is not None and merge is not None and merge < create:
    print("AGENTS.md  merge-state check appears before pull request creation")
PYTHON
cleanup_order="$(python3 -c "$CLEANUP_PROGRAM")"

if [[ -n "${cleanup_order//[[:space:]]/}" ]]; then
    fail "the worktree cleanup recipe can delete a pull request branch before it is merged" \
        "Keep the worktree and both feature-branch refs while the pull request is open." \
        "Verify through GitHub that the pull request has merged before cleanup commands." \
        "" $'\n'"$cleanup_order"
else
    pass "branch cleanup follows GitHub merge verification in AGENTS.md"
fi

# ---------------------------------------------------------------------------
# 5. A tagged release's bullets must have existed by the tag.
# ---------------------------------------------------------------------------
#
# Calendar release sections are a promise about the build named by their tag. Corrections to
# prose or link definitions can happen later, but a new bullet under `Fixed`, `Added`, `Changed`
# or `Security` says that tagged build shipped work it did not contain. Issue #1123 was exactly
# that: post-tag fixes were moved out of `Unreleased` and into the previous release's section.
printf '\nCHANGELOG release bullets\n'

post_tag_bullets="$(changelog_release_bullet_findings)"
if [[ -n "${post_tag_bullets//[[:space:]]/}" ]]; then
    fail "a tagged release section contains a bullet added after its tag" \
        "Move the entry back under Unreleased, or cut a new release whose tag contains it." \
        "Typos and link corrections are still allowed; this check watches bullet claims." \
        "" $'\n'"$post_tag_bullets"
else
    pass "every bullet in a tagged release section existed by that tag"
fi

# ---------------------------------------------------------------------------
# 6. A performance headline stating a memory figure must name its suggestion mode.
# ---------------------------------------------------------------------------
#
# Issue #1240: the third headline in Docs/performance.md reported a dictation-only,
# suggestions-off memory reading as an unconditional whole-app claim, though the same
# document budgets a separate multi-gigabyte suggestions-on mode a few sections down.
# A headline that states a memory figure (MB or GB) must say which mode it was measured
# under, so a future edit cannot silently drop the other mode again.
printf '\nPerformance headline scope\n'

PERF_DOC="Docs/performance.md"
if [[ ! -f "$PERF_DOC" ]]; then
    fail "$PERF_DOC is missing" \
        "The performance headlines this check pins no longer exist to check."
else
    read -r -d '' HEADLINE_PROGRAM <<'PYTHON' || true
import re
import sys

text = open("Docs/performance.md", errors="ignore").read()
start = text.find("**Three headlines, in the order they matter.**")
end = text.find("\n## ", start)
if start == -1 or end == -1:
    print("Docs/performance.md  cannot find the headline section")
    sys.exit()

section = text[start:end]
# Each headline is a bold sentence followed by prose, up to the next bold sentence or the
# section's end.
headlines = re.split(r"\n\n(?=\*\*)", section)
for headline in headlines:
    if not re.search(r"\d[\d,]*\s*(?:MB|GB)\b", headline):
        continue
    if not re.search(r"suggestion", headline, re.IGNORECASE):
        first_line = headline.strip().splitlines()[0]
        print(f"Docs/performance.md  {first_line}")
PYTHON
    headline_issues="$(python3 -c "$HEADLINE_PROGRAM")"

    if [[ -n "${headline_issues//[[:space:]]/}" ]]; then
        fail "a performance headline states a memory figure without naming its suggestion mode" \
            "AI suggestions on is a separate, multi-gigabyte budget from dictation alone;" \
            "a headline that gives a memory number for one mode and says nothing about the" \
            "other reads as a whole-app claim. Name the mode the figure was measured under." \
            "" $'\n'"$headline_issues"
    else
        pass "every memory figure in the performance headlines names its suggestion mode"
    fi
fi

# ---------------------------------------------------------------------------
# 7. Every artboard text row clears WCAG AA contrast against its translucent backing.
# ---------------------------------------------------------------------------
#
# The artboard generators draw a translucent menu over a gradient, and a backdrop blur
# cannot lift the backing above the gradient's brightest source stop — so the contrast
# against the brightest stop is the best case anywhere on the surface, and the darkest
# stop is the worst. The audit script reads the gradient stops and menu fill from the
# generator, walks the inline text-color declarations, and fails any row that drops below
# 4.5:1 over any composited background.
printf '\nDesign artboard contrast\n'

if [[ ! -x "$PACKAGE_ROOT/Scripts/design_contrast_audit.py" ]]; then
    fail "Scripts/design_contrast_audit.py is missing or not executable" \
        "The audit pins the menu-bar artboard's text contrast; without it the generator" \
        "could regress to the colours that production already moved off."
else
    if "$PACKAGE_ROOT/Scripts/design_contrast_audit.py" --self-test; then
        if "$PACKAGE_ROOT/Scripts/design_contrast_audit.py" >&2; then
            pass "every attention text row clears 4.5:1 against its composited backgrounds"
        else
            fail "an artboard text row fails WCAG AA contrast against its composited backing" \
                "The audit prints which generator rule and which colour broke. The backing" \
                "is translucent over a gradient, so the worst case is the gradient's darkest" \
                "stop, not the average — backdrop blur cannot brighten past the brightest stop."
        fi
    else
        fail "Scripts/design_contrast_audit.py --self-test failed" \
            "The audit's own self-test (a known pass and a known fail) is no longer both" \
            "passing, so the ratio predicate is broken. Fix the audit, not the artboard."
    fi
fi

# ---------------------------------------------------------------------------
# 7b. Every shared artboard surface/text token matches BrandPalette.swift.
# ---------------------------------------------------------------------------
#
# `Design/_gen_common.py` and `Design/_gen_shell.py` declare the page, card, rail, control,
# separator and primary/muted/dim text colours every artboard inherits. Nothing tied those
# to `BrandPalette.swift`, the shipped app's single source of truth for the same roles, so
# #1162 found all 73 artboards still drawing system greys the product moved off years ago.
printf '\nDesign token parity\n'

if [[ ! -x "$PACKAGE_ROOT/Scripts/design_token_parity_audit.py" ]]; then
    fail "Scripts/design_token_parity_audit.py is missing or not executable" \
        "The audit pins the shared artboard tokens to BrandPalette.swift; without it either" \
        "side can drift and nothing notices."
else
    if "$PACKAGE_ROOT/Scripts/design_token_parity_audit.py" --self-test; then
        if "$PACKAGE_ROOT/Scripts/design_token_parity_audit.py" >&2; then
            pass "every shared artboard surface/text token matches BrandPalette.swift"
        else
            fail "a shared artboard token disagrees with BrandPalette.swift" \
                "The audit prints which role, which theme and which two hex values disagree." \
                "Update the generator token to match, then regenerate every artboard."
        fi
    else
        fail "Scripts/design_token_parity_audit.py --self-test failed" \
            "The audit's own self-test could not resolve a BrandPalette identifier reference," \
            "so the Swift parser is broken. Fix the audit, not the artboard."
    fi
fi

# ---------------------------------------------------------------------------
# 7c. The Dictation artboards match DictationPresenter's own figures.
# ---------------------------------------------------------------------------
#
# #153 renamed the populated rail's cleanup-ratio tile from "Accuracy" to
# `DictationPresenter.accuracyTitle`, said plainly that it does not say whether words were
# heard correctly, and dropped the baseline meter beside it. Nothing tied the design
# generator to that decision, so #1139 found `Design/_gen_app.py` had drifted back to a
# 97.2% "Accuracy" tile with a "Baseline" meter row.
printf '\nDictation artboard contract\n'

if [[ ! -x "$PACKAGE_ROOT/Scripts/design_dictation_contract_audit.py" ]]; then
    fail "Scripts/design_dictation_contract_audit.py is missing or not executable" \
        "The audit pins the Dictation rail to DictationPresenter's accuracyTitle and" \
        "accuracyCaption, and refuses a restored Accuracy label or baseline meter; without" \
        "it either side can drift and nothing notices."
else
    if "$PACKAGE_ROOT/Scripts/design_dictation_contract_audit.py" --self-test; then
        if "$PACKAGE_ROOT/Scripts/design_dictation_contract_audit.py" >&2; then
            pass "the Dictation rail matches DictationPresenter, with no Accuracy label or baseline meter"
        else
            fail "the Dictation rail disagrees with DictationPresenter" \
                "The audit prints which title, caption or retired label broke. Update" \
                "Design/_gen_app.py's Dictation section to match, then regenerate both" \
                "Main-Dictation artboards."
        fi
    else
        fail "Scripts/design_dictation_contract_audit.py --self-test failed" \
            "The audit's own self-test could not resolve a known-good fixture or catch a" \
            "known regression, so the parser is broken. Fix the audit, not the artboard."
    fi
fi

# ---------------------------------------------------------------------------
# 8. CLAUDE.md, if it exists, delegates to AGENTS.md by import or symlink.
# ---------------------------------------------------------------------------
#
# A tracked CLAUDE.md is a claim about what Claude Code will load as project memory: with
# default Project instructions, Claude Code reads CLAUDE.md before any tool call and does
# not consult AGENTS.md on its own. A CLAUDE.md that holds a prose pointer at AGENTS.md
# therefore loads the pointer sentence and stops — the 491 lines of operating rules in
# AGENTS.md are injected only if the model decides, on its own, to follow the link.
#
# Three contents pass, in this order:
#
#   1. CLAUDE.md is absent. There is no claim to police, and AGENTS.md loads directly.
#   2. CLAUDE.md is a real filesystem symlink whose resolved target is `AGENTS.md`. The
#      file Claude Code reads is AGENTS.md, full stop — the indirection is at the FS layer
#      rather than at the prose layer.
#   3. CLAUDE.md's first non-blank, non-comment line is `@AGENTS.md`. That is Claude
#      Code's import syntax; the file is read and its contents are merged into the
#      project memory for the session.
#
# Any other content is a failure. The Markdown-link pointer that lived here until #1125
# was the trap: the link rendered, the model received one sentence, and the rules were not
# injected without a separate Read-tool decision the model could equally skip.
printf '\nCLAUDE.md delegation\n'

if check_claude_md_delegation "$PACKAGE_ROOT"; then
    if [[ -e CLAUDE.md ]]; then
        pass "CLAUDE.md delegates to AGENTS.md"
    else
        pass "no CLAUDE.md to check"
    fi
else
    fail "$claude_md_problem" \
        "A tracked CLAUDE.md is loaded by Claude Code as project memory ahead of any tool." \
        "Prose that points at AGENTS.md — Markdown link or otherwise — is one sentence the" \
        "model receives, not an import; the 491 lines of operating rules in AGENTS.md are" \
        "not injected unless the model decides, on its own, to open the file." \
        "Replace the body with a single '@AGENTS.md' line, or delete CLAUDE.md and let" \
        "AGENTS.md load directly, or turn CLAUDE.md into a real symlink to AGENTS.md."
fi

# ---------------------------------------------------------------------------
# 8. Documented `uttrflow-eval` commands obey their own argument rules.
# ---------------------------------------------------------------------------
#
# Issue #1227 was two exit-early bugs wearing a code example: the runbook showed
# `record --sync` as the command that reads a passage aloud, but `RecordCorpus.run()`
# handles `sync` before the recording queue exists and returns immediately — and it
# showed `transcribe --from-catalogue --save-baseline` with no `--baseline <path>`,
# which `TranscribeCorpus.validate()` rejects outright (exit 64). Both read as working
# commands. This re-derives the two argument rules statically and checks every fenced
# `uttrflow-eval` invocation in the tree against them.
printf '\n`uttrflow-eval` examples\n'

cli_report="$(uttrflow_eval_contract_findings <<<"$DOCS")"

if [[ -n "${cli_report//[[:space:]]/}" ]]; then
    fail "a documented uttrflow-eval command violates its own argument rules" \
        "Each line: where, the command as written, and which rule it breaks." \
        "" $'\n'"$(printf '%s\n' "$cli_report" | sed 's/\t/  /g')"
else
    pass "every documented uttrflow-eval invocation satisfies its own argument rules"
fi

# ---------------------------------------------------------------------------
# 9. The disk table's total, and the prose that restates it, must add up.
# ---------------------------------------------------------------------------
#
# Issue #1239: the disk section's table gave a "total" row and the prose below it named
# a "fresh install" figure that neither matched the table's sum nor each other, and the
# prose also quoted a different speech-model size than the table's own row. Three numbers
# describing the same install, none of them arithmetically tied to another.
printf '\nPerformance disk table arithmetic\n'

PERF_DOC="Docs/performance.md"
if [[ ! -f "$PERF_DOC" ]]; then
    fail "$PERF_DOC is missing" \
        "The disk table this check reconciles no longer exists to check."
else
    read -r -d '' DISK_PROGRAM <<'PYTHON' || true
import re
import sys

text = open("Docs/performance.md", errors="ignore").read()
start = text.find("## Disk")
end = text.find("\n## ", start + 1)
if start == -1:
    print("Docs/performance.md  cannot find the '## Disk' section")
    sys.exit()
section = text[start:end if end != -1 else len(text)]

table = re.search(
    r"speech model\s+([\d.]+)\s*MB\n\s*application\s+([\d.]+)\s*MB\n\s*total\s+([\d.]+)\s*MB",
    section,
)
if not table:
    print("Docs/performance.md  cannot find the speech model / application / total rows")
    sys.exit()
model, application, total = (float(g) for g in table.groups())
if round(model + application, 1) != round(total, 1):
    print(
        f"Docs/performance.md  table rows {model} + {application} MB "
        f"= {model + application:.1f} MB, not the printed total {total} MB"
    )

prose_model = re.search(r"model is measured on disk \(([\d.]+)\s*MB", section)
if prose_model and float(prose_model.group(1)) != model:
    print(
        f"Docs/performance.md  prose gives the speech model as {prose_model.group(1)} MB, "
        f"the table gives {model} MB"
    )

prose_total = re.search(r"fresh install is therefore \*\*([\d.]+)\s*MB", section)
if prose_total and float(prose_total.group(1)) != total:
    print(
        f"Docs/performance.md  prose gives the fresh-install total as {prose_total.group(1)} MB, "
        f"the table gives {total} MB"
    )
PYTHON
    disk_issues="$(python3 -c "$DISK_PROGRAM")"

    if [[ -n "${disk_issues//[[:space:]]/}" ]]; then
        fail "the disk table and its prose do not agree with each other" \
            "The table's speech-model, application and total rows, and the prose figures" \
            "that restate them, must be one arithmetic story rather than three separately" \
            "rounded numbers." \
            "" $'\n'"$disk_issues"
    else
        pass "the disk table's rows and the prose that restates them add up"
    fi
fi

# ---------------------------------------------------------------------------
# 10. Docs/bakeoff.md's corpus inventory must match EvaluationCorpus.
# ---------------------------------------------------------------------------
#
# #236 corrected this once, from 36 cases to 84 by hand. #1191 caught the same drift a
# second time — the corpus had reached 174 cases while the "Still open" paragraph still
# said 105, and three of its six category counts were wrong too, because nothing tied
# that paragraph to the source it describes. The historical prompt-v2 and prompt-v3 table
# sizes earlier in the file are measurements from old runs and are deliberately left
# alone; this check reads only the present-tense inventory sentence.
printf '\nBake-off corpus inventory\n'

CORPUS_SOURCE="Sources/UttrflowEval/EvaluationCorpus.swift"
BAKEOFF_DOC="Docs/bakeoff.md"
if [[ ! -f "$CORPUS_SOURCE" || ! -f "$BAKEOFF_DOC" ]]; then
    fail "$CORPUS_SOURCE or $BAKEOFF_DOC is missing" \
        "The corpus inventory this check reconciles no longer exists to check."
else
    read -r -d '' CORPUS_PROGRAM <<'PYTHON' || true
import re

SOURCE = "Sources/UttrflowEval/EvaluationCorpus.swift"
DOC = "Docs/bakeoff.md"

real = {}
for match in re.finditer(r"category: \.([A-Za-z]+),", open(SOURCE, errors="ignore").read()):
    real[match.group(1)] = real.get(match.group(1), 0) + 1
real_total = sum(real.values())

text = open(DOC, errors="ignore").read()
sentence = re.search(
    r"The corpus is ([0-9,]+) cases in six categories\*\*.*?written by hand\.",
    text, re.DOTALL,
)
if sentence is None:
    print(f"{DOC}  cannot find the corpus-inventory sentence in ## Still open")
else:
    stated_total = int(sentence.group(1).replace(",", ""))
    stated = {
        category: int(count.replace(",", ""))
        for category, count in re.findall(r"`([a-zA-Z]+)`\s+([0-9,]+)", sentence.group(0))
    }

    if stated_total != real_total:
        print(f"{DOC}  total: doc says {stated_total}, EvaluationCorpus.all has {real_total}")
    if set(stated) != set(real):
        print(f"{DOC}  categories: doc names {sorted(stated)}, corpus has {sorted(real)}")
    else:
        for category in sorted(real):
            if stated[category] != real[category]:
                print(
                    f"{DOC}  {category}: doc says {stated[category]}, "
                    f"corpus has {real[category]}"
                )
PYTHON
    corpus_problems="$(python3 -c "$CORPUS_PROGRAM")"

    if [[ -n "${corpus_problems//[[:space:]]/}" ]]; then
        fail "Docs/bakeoff.md's corpus inventory no longer matches EvaluationCorpus" \
            "The 'Still open' paragraph's total and per-category breakdown must track" \
            "Sources/UttrflowEval/EvaluationCorpus.swift. This is the #1191 drift." \
            "" $'\n'"$corpus_problems"
    else
        pass "Docs/bakeoff.md's corpus inventory matches EvaluationCorpus"
    fi
fi

# ---------------------------------------------------------------------------
printf '\n'
if [[ "$failures" -gt 0 ]]; then
    printf 'docs audit: %s check(s) failed. The documentation contradicts the tree.\n\n' "$failures" >&2
    exit 1
fi

printf 'docs audit: the paths, links, test count, worktree cleanup order, release bullets, performance headline scope, CLAUDE.md delegation, uttrflow-eval examples, disk table arithmetic and bake-off corpus inventory in %s documents all check out.\n\n' "$DOC_COUNT"

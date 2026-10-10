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
#         ./Scripts/docs_audit.sh --self-test   also runs the contract and delegation fixtures
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

graphflow_guide_problem=""
check_graphflow_guide_reference() {
    local root="$1"
    graphflow_guide_problem=""
    if [[ ! -f "$root/graphflow.yaml" ]]; then
        graphflow_guide_problem="graphflow.yaml is missing"
        return 1
    fi
    if ! grep -Fq 'Docs/graphflow.md' "$root/graphflow.yaml"; then
        graphflow_guide_problem="graphflow.yaml does not point to Docs/graphflow.md"
        return 1
    fi
    if [[ ! -f "$root/Docs/graphflow.md" ]]; then
        graphflow_guide_problem="graphflow.yaml points to Docs/graphflow.md, but that file is missing"
        return 1
    fi
    return 0
}

run_graphflow_guide_self_test() {
    local work
    work="$(mktemp -d -t uttrflow-graphflow-guide.XXXXXX)"
    trap 'rm -rf "$work"' RETURN

    mkdir -p "$work/valid/Docs" "$work/missing/Docs" "$work/unreferenced/Docs"
    printf '# See `Docs/graphflow.md`.\n' > "$work/valid/graphflow.yaml"
    printf '# Guide\n' > "$work/valid/Docs/graphflow.md"
    printf '# See `Docs/graphflow.md`.\n' > "$work/missing/graphflow.yaml"
    printf '# Guide\n' > "$work/unreferenced/Docs/graphflow.md"
    printf '# Graphflow guide reference self-test\n'

    if check_graphflow_guide_reference "$work/valid"; then
        pass "existing Graphflow guide reference passes"
    else
        fail "a valid Graphflow guide reference failed" "$graphflow_guide_problem"
    fi
    if check_graphflow_guide_reference "$work/missing"; then
        fail "a missing Graphflow guide passed" \
            "The audit must catch the dead reference from issue #1286."
    else
        pass "missing Graphflow guide fails"
    fi
    if check_graphflow_guide_reference "$work/unreferenced"; then
        fail "an unreferenced Graphflow guide passed" \
            "The config must keep an explicit pointer to its guide."
    else
        pass "missing Graphflow guide reference fails"
    fi
}

# The PR template is contributor-facing guidance and must agree with AGENTS.md's
# present-tense comment rule without repeating the full policy. Keep this check narrow.
comment_checklist_findings() {
    local template="$1"
    python3 - "$template" <<'PYTHON'
import sys

path = sys.argv[1]
text = open(path, errors="ignore").read()
required = (
    "Comments are one line, present tense, and describe what the code does now",
    "A reason only when it changes what a reader should do",
    "durable measurements or",
    "development history",
)
stale = "Comments explain *why*, not what"
missing = [phrase for phrase in required if phrase not in text]
if stale in text:
    print(f"{path}: retains the obsolete 'why, not what' checklist instruction")
for phrase in missing:
    print(f"{path}: missing comment guidance: {phrase}")
PYTHON
}

run_comment_checklist_self_test() {
    local work
    work="$(mktemp -d -t uttrflow-docs-audit-comments.XXXXXX)"
    trap 'rm -rf "$work"' RETURN
    cat >"$work/current.md" <<'EOF'
- [ ] Comments are one line, present tense, and describe what the code does now

A reason only when it changes what a reader should do. Put durable measurements or
architectural rationale in `Docs/`; put development history in this description or the commit.
EOF
    cat >"$work/stale.md" <<'EOF'
- [ ] Comments explain *why*, not what
EOF

    printf 'PR comment checklist fixture\n'
    local current_report stale_report
    current_report="$(comment_checklist_findings "$work/current.md")"
    if [[ -z "${current_report//[[:space:]]/}" ]]; then
        pass "current comment checklist guidance passes"
    else
        fail "current comment checklist guidance was flagged" "$current_report"
    fi
    stale_report="$(comment_checklist_findings "$work/stale.md")"
    if [[ "$stale_report" == *"obsolete 'why, not what'"* && "$stale_report" == *"missing comment guidance"* ]]; then
        pass "the obsolete checklist wording fails"
    else
        fail "the obsolete comment checklist wording passed" "$stale_report"
    fi
}

if [[ "$SELF_TEST" -eq 1 ]]; then
    run_comment_checklist_self_test
    printf '\n'
fi

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

changelog_release_link_findings() {
    python3 - "$1" <<'PYTHON'
import re
import sys

path = sys.argv[1]
text = open(path, errors="ignore").read()
headings = re.findall(r"^## \[([^\]]+)\]", text, re.MULTILINE)
definitions = {
    " ".join(label.split()).casefold()
    for label in re.findall(r"^\[([^\]]+)\]:", text, re.MULTILINE)
}
for label in headings:
    if label.casefold() == "unreleased":
        continue
    if " ".join(label.split()).casefold() not in definitions:
        print(f"{path}: missing link definition for [{label}]")
PYTHON
}

run_changelog_release_link_self_test() {
    local work fixture findings
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' RETURN
    fixture="$work/CHANGELOG.md"
    cat >"$fixture" <<'EOF'
## [Unreleased]
## [2026.9.14] — 2026-09-14
EOF

    printf 'CHANGELOG release-link fixture\n'
    findings="$(changelog_release_link_findings "$fixture")"
    if [[ "$findings" == *"missing link definition for [2026.9.14]"* ]]; then
        pass "a release heading without a link definition fails"
    else
        fail "a release heading without a link definition passed" "$findings"
    fi

    printf '[2026.9.14]: https://example.com/release\n' >>"$fixture"
    findings="$(changelog_release_link_findings "$fixture")"
    if [[ -z "${findings//[[:space:]]/}" ]]; then
        pass "a release heading with a link definition passes"
    else
        fail "a release heading with a link definition was flagged" "$findings"
    fi
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
    run_graphflow_guide_self_test
    printf '\n'
fi

if [[ "$SELF_TEST" -eq 1 ]]; then
    run_changelog_release_link_self_test
    printf '\n'
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

# `make verify` intentionally stops before constructing the app bundle. CI's packaging
# gate is a separate contract, and the contributor guide must name the same shared target.
read -r -d '' PACKAGING_CONTRACT_PROGRAM <<'PYTHON' || true
import re
import sys

guide_path, workflow_path = sys.argv[1:]
guide = open(guide_path, errors="ignore").read()
workflow = open(workflow_path, errors="ignore").read()
findings = []
stale = re.compile(
    r"no class of failure that only CI can find|"
    r"make verify.{0,100}(?:same command CI runs|covers? every CI|all CI failures)",
    re.IGNORECASE | re.DOTALL,
)
for path, text in ((guide_path, guide), (workflow_path, workflow)):
    match = stale.search(text)
    if match:
        line = text.count("\n", 0, match.start()) + 1
        findings.append(f"{path}:{line}\tclaims make verify covers failures outside its gate")
if "make app-preflight" not in guide:
    findings.append(f"{guide_path}:1\tdoes not give the shared packaging preflight command")
if "run: make app-preflight" not in workflow:
    findings.append(f"{workflow_path}:1\tCI does not use the documented packaging preflight")
if guide.find("make verify") > guide.find("make app-preflight"):
    findings.append(f"{guide_path}:1\tdoes not put make verify before the packaging preflight")
verify_step = workflow.find("run: make --keep-going verify")
packaging_step = workflow.find("run: make app-preflight")
if verify_step < 0 or packaging_step < 0 or verify_step > packaging_step:
    findings.append(f"{workflow_path}:1\tCI does not run verify before the packaging preflight")
print("\n".join(findings))
PYTHON

packaging_contract_findings() {
    python3 -c "$PACKAGING_CONTRACT_PROGRAM" "$1" "$2"
}

run_packaging_contract_self_test() {
    local work
    work="$(mktemp -d -t uttrflow-docs-audit-packaging.XXXXXX)"
    trap 'rm -rf "$work"' RETURN
    printf '%s\n' 'Run `make verify`; there is no class of failure that only CI can find.' \
        'For packaging changes, run `make app-preflight`.' > "$work/stale.md"
    printf '%s\n' 'Run `make verify` for lint, audits, tests, and coverage.' \
        'For packaging changes, run `make app-preflight`.' > "$work/corrected.md"
    printf '%s\n' 'run: make --keep-going verify' 'run: make app-preflight' > "$work/ci.yml"

    printf 'packaging gate wording fixture\n'
    local stale_report corrected_report fail_fast_report
    stale_report="$(packaging_contract_findings "$work/stale.md" "$work/ci.yml")"
    if [[ "$stale_report" == *"covers failures outside its gate"* ]]; then
        pass "the stale make verify claim fails"
    else
        fail "the stale make verify claim passed" "$stale_report"
    fi
    corrected_report="$(packaging_contract_findings "$work/corrected.md" "$work/ci.yml")"
    if [[ -z "${corrected_report//[[:space:]]/}" ]]; then
        pass "the corrected gate wording and shared command pass"
    else
        fail "the corrected packaging guidance was flagged" "$corrected_report"
    fi
    printf '%s\n' 'run: make verify' 'run: make app-preflight' > "$work/ci.yml"
    fail_fast_report="$(packaging_contract_findings "$work/corrected.md" "$work/ci.yml")"
    if [[ "$fail_fast_report" == *"CI does not run verify before the packaging preflight"* ]]; then
        pass "the fail-fast CI command fails the shared gate contract"
    else
        fail "the fail-fast CI command passed the shared gate contract" "$fail_fast_report"
    fi
}

if [[ "$SELF_TEST" -eq 1 ]]; then
    run_packaging_contract_self_test
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

printf '\nPackaging gate guidance\n'
packaging_contract_report="$(packaging_contract_findings CONTRIBUTING.md .github/workflows/ci.yml)"
if [[ -n "${packaging_contract_report//[[:space:]]/}" ]]; then
    fail "the contributor guide and CI disagree about the packaging gate" \
        '`make verify` does not create or verify the app bundle. Keep the documented' \
        'sequence and CI aligned through `make app-preflight`.' \
        "" $'\n'"$packaging_contract_report"
else
    pass "the guide distinguishes make verify and CI uses its shared app-preflight command"
fi

cd "$PACKAGE_ROOT"

printf 'Graphflow operating guide\n'
if check_graphflow_guide_reference "$PACKAGE_ROOT"; then
    pass "graphflow.yaml points to the tracked Docs/graphflow.md guide"
else
    fail "the Graphflow operating guide reference is broken" "$graphflow_guide_problem"
fi
printf '\n'

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
# The ruleset lives on the server, outside this tree, so this check keeps the documented
# lifecycle on the review-required side of it: the workflow page must name every review gate
# and must never say a pull request may be merged by its own author.
printf '\nPull request lifecycle\n'

if grep -Fq "**An agent may merge its own pull request once it is green**" Docs/agents/workflow.md; then
    fail "Docs/agents/workflow.md still documents the removed self-merge rule" \
        "The live main ruleset requires an approving review, code-owner review and" \
        "last-pusher approval. A local policy that says agents may merge themselves" \
        "sends finished pull requests into a gate they cannot satisfy."
fi

missing_policy=()
for required in \
    "requires one approving review" \
    "code-owner review" \
    "approval by someone other than the last pusher" \
    "strict_required_status_checks_policy"
do
    if ! grep -Fq "$required" Docs/agents/workflow.md; then
        missing_policy+=("$required")
    fi
done

if ((${#missing_policy[@]})); then
    fail "Docs/agents/workflow.md no longer records the review-required main ruleset" \
        "The policy must tell agents that implementation stops at a green pull request," \
        "and must name the live ruleset gates that enforce that boundary." \
        "" $'\n'"$(printf '    %s\n' "${missing_policy[@]}")"
else
    pass "Docs/agents/workflow.md names the main ruleset's review gates"
fi

# ---------------------------------------------------------------------------
# 0b. The rule files carry rules, not history.
# ---------------------------------------------------------------------------
#
# A rule is stated in the present tense with a measure and a check. An issue or pull-request
# number, or a calendar date, is history: it goes stale and names a conversation a reader
# cannot see. Evidence belongs on a Docs/ page, linked from the rule in one line.
printf '\nRule files carry no history\n'

history_findings=$(grep -n -E '(^|[^A-Za-z0-9_&])#[0-9]{2,}|\b20[0-9]{2}-[0-9]{2}-[0-9]{2}\b' AGENTS.md Docs/agents/*.md || true)
if [[ -n "$history_findings" ]]; then
    fail "AGENTS.md or Docs/agents/ cites an issue number, pull-request number or date" \
        "State the rule in the present tense and move the evidence to a Docs/ page." \
        "" $'\n'"$(printf '    %s\n' "$history_findings")"
else
    pass "AGENTS.md and Docs/agents/ cite no issue, pull-request number or date"
fi

# ---------------------------------------------------------------------------
# 0c. No document shows a tag in the retired YEAR.MONTH.DAY scheme.
# ---------------------------------------------------------------------------
#
# Versions are YY.MMDD.REVISION (RELEASING.md). A `v2026.9.14` example teaches a tag the release
# workflow refuses. The changelog keeps its historical release links; the scheme explanations
# name the old version without the `v`, so they are not tags and are not matched.
printf '\nNo document shows a retired release tag\n'

retired_tag_findings=$(git grep -n -E '(^|[^A-Za-z0-9_])v20[0-9]{2}\.[0-9]+\.[0-9]+' -- '*.md' ':!CHANGELOG.md' || true)
if [[ -n "$retired_tag_findings" ]]; then
    fail "a document shows a release tag in the retired YEAR.MONTH.DAY scheme" \
        "Use the current YY.MMDD.REVISION form, such as v26.0926.0, as RELEASING.md states." \
        "" $'\n'"$(printf '    %s\n' "$retired_tag_findings")"
else
    pass "no document outside CHANGELOG.md shows a retired YEAR.MONTH.DAY tag"
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
    "LICENSE.md", "Package.resolved", "Package.swift", "README.md",
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
# One thing is skipped, because it is a record rather than a claim: a line in Swift Testing's
# own summary format — `Test run with 579 tests in 83 suites` in `Docs/offline.md` is the
# transcript of one filtered run. Fenced code blocks as a whole are *not* skipped: three of the #76 claims lived in a
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

printf '\nDocumentation index\n'
missing_index_pages=()
for page in soak.md ui-tests.md; do
    if ! grep -Fq "[$page]($page)" Docs/README.md; then
        missing_index_pages+=("$page")
    fi
done
if ((${#missing_index_pages[@]})); then
    for page in "${missing_index_pages[@]}"; do
        fail "Docs/README.md does not link to $page" \
            "The documentation index should keep the soak and UI test guides discoverable."
    done
else
    pass "the documentation index links to soak.md and ui-tests.md"
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

printf '\nCHANGELOG release links\n'
missing_release_links="$(changelog_release_link_findings CHANGELOG.md)"
if [[ -n "${missing_release_links//[[:space:]]/}" ]]; then
    fail "a release heading has no link definition" \
        "Every released version heading must link to its release page." \
        "" $'\n'"$missing_release_links"
else
    pass "every released version heading has a link definition"
fi

# ---------------------------------------------------------------------------
# 5b. Every command the measurement guide names exists in the Makefile, Scripts or the tools.
# ---------------------------------------------------------------------------
printf '\nMeasurement guide commands\n'
if [[ "$SELF_TEST" -eq 1 ]]; then
    measure_args=(--self-test)
else
    measure_args=()
fi
if measure_report="$(python3 "$PACKAGE_ROOT/Scripts/measure_commands_audit.py" "${measure_args[@]+"${measure_args[@]}"}" 2>&1)"; then
    pass "every command in Docs/measure-a-change.md exists in the tree"
else
    fail "Docs/measure-a-change.md names a command the tree does not have" \
        "A contributor following the guide would run something that is not there." \
        "" $'\n'"$measure_report"
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
# 7. The design gate stays in `make verify`.
# ---------------------------------------------------------------------------
#
# Every design check (palette, typeface, generator, canvas and contrast audits) runs under
# `make design-audit`, described in Docs/agents/design.md. A gate outside `verify` is a gate CI never runs.
printf '\nDesign gate in verify\n'

verify_prerequisites=$(grep -E '^verify:' "$PACKAGE_ROOT/Makefile" | sed -e 's/^verify://' -e 's/##.*//')
if grep -qw 'design-audit' <<<"$verify_prerequisites" \
    && grep -qE '^design-audit:' "$PACKAGE_ROOT/Makefile"; then
    pass "make verify runs make design-audit"
else
    fail "make verify no longer runs make design-audit" \
        "Docs/agents/design.md's rules are enforced only through design-audit, and CI runs only verify." \
        "Put design-audit back among verify's prerequisites."
fi

# ---------------------------------------------------------------------------
# 8. CLAUDE.md, if it exists, delegates to AGENTS.md by import or symlink.
# ---------------------------------------------------------------------------
#
# A tracked CLAUDE.md is a claim about what Claude Code will load as project memory: with
# default Project instructions, Claude Code reads CLAUDE.md before any tool call and does
# not consult AGENTS.md on its own. A CLAUDE.md that holds a prose pointer at AGENTS.md
# therefore loads the pointer sentence and stops — the operating rules in AGENTS.md
# are injected only if the model decides, on its own, to follow the link.
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
        "model receives, not an import; the operating rules in AGENTS.md are" \
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
# README clipboard privacy claims must keep the current protections visible.
# ---------------------------------------------------------------------------
# #2109/#3158: the README names concealed-copy handling, per-app exclusions, timed pause, secret storage and file permissions.
printf '\nREADME clipboard privacy claims\n'

read -r -d '' README_PRIVACY_PROGRAM <<'PYTHON' || true
from pathlib import Path

readme = Path("README.md").read_text(errors="ignore")
obsolete = (
    "Uttrflow does not honour the concealed-pasteboard convention",
    "Uttrflow does not read that mark yet",
    "The text is stored in the clear like every other clip",
    "ordinary file permissions",
)
missing = [claim for claim in obsolete if claim in readme]
if missing:
    print("obsolete README privacy claims remain:")
    for claim in missing:
        print(f"  {claim}")

required = (
    "Password managers' concealed mark is honoured",
    "not written to clipboard history or saved clips",
    "Clipboard capture can be excluded per app or paused for an hour",
    "owner-only",
    "[`Docs/clipboard-secrets.md`](Docs/clipboard-secrets.md)",
)
missing = [claim for claim in required if claim not in readme]
if missing:
    print("README clipboard privacy claims or their supporting link are missing:")
    for claim in missing:
        print(f"  {claim}")
PYTHON

privacy_problems="$(python3 -c "$README_PRIVACY_PROGRAM")"
if [[ -z "$privacy_problems" ]]; then
    pass "README clipboard privacy claims describe concealed copies, app exclusions, timed pause, storage and permissions"
else
    fail "README clipboard privacy claims have drifted" \
        "Keep the README aligned with the clipboard protections described in" \
        "Docs/clipboard-secrets.md and the Clipboard settings." \
        "" $'\n'"$privacy_problems"
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
import glob
import json
import os
import re

SOURCES = ["Sources/UttrflowEval/EvaluationCorpus.swift", "Sources/UttrflowEval/RequestCorpus.swift"]
DOC = "Docs/bakeoff.md"

real = {}
for source in SOURCES:
    for match in re.finditer(r"category: \.([A-Za-z]+),", open(source, errors="ignore").read()):
        real[match.group(1)] = real.get(match.group(1), 0) + 1
# Categories kept as data: <category>.json, or <category>.<set>.json for a named set; see
# Sources/UttrflowEval/CorpusFile.swift. A file read into a list that `all` does not add up is
# no part of the inventory.
corpus_source = open(SOURCES[0], errors="ignore").read()
all_expression = re.search(r"static let all: \[EvaluationCase\] =(.*?)\n\n", corpus_source, re.DOTALL)
in_all = set(re.findall(r"[A-Za-z]+", all_expression.group(1))) if all_expression else set()
outside_all = {
    ".".join(filter(None, (category, file_set)))
    for name, category, file_set in re.findall(
        r"static let ([A-Za-z]+): \[EvaluationCase\] = CorpusFile\.cases\(\s*in: \.([A-Za-z]+)(?:, set: \"([A-Za-z]+)\")?\)",
        corpus_source,
    )
    if name not in in_all
}
for path in sorted(glob.glob("Sources/UttrflowEval/Resources/Corpus/*.json")):
    if os.path.basename(path)[: -len(".json")] in outside_all:
        continue
    category = os.path.basename(path).split(".")[0]
    real[category] = real.get(category, 0) + len(json.load(open(path)))
real_total = sum(real.values())

text = open(DOC, errors="ignore").read()
sentence = re.search(
    r"The corpus is ([0-9,]+) cases in [a-z]+ categories\*\*.*?written by hand\.",
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
# 7g. Every insertion scenario has an entry for every application class.
# ---------------------------------------------------------------------------
printf '\nInsertion test matrix\n'

if python3 "$PACKAGE_ROOT/Scripts/insertion_matrix_audit.py" --self-test; then
    if python3 "$PACKAGE_ROOT/Scripts/insertion_matrix_audit.py"; then
        pass "every insertion scenario names its test and an entry per class"
    else
        fail "Docs/insertion-test-matrix.md has a scenario without an entry" \
            "Each scenario needs an existing test and, per class, a harness, a manual" \
            "procedure with its own section, or 'not applicable'."
    fi
else
    fail "Scripts/insertion_matrix_audit.py --self-test failed" \
        "The audit must catch an empty cell before it checks the matrix."
fi

# ---------------------------------------------------------------------------
# 12. Every number marked `<!-- count:Type.member -->` or `<!-- value:Type.member -->` matches the code.
# ---------------------------------------------------------------------------
printf '\nMarked numbers\n'

if python3 "$PACKAGE_ROOT/Scripts/docs_values_audit.py" --self-test; then
    if python3 "$PACKAGE_ROOT/Scripts/docs_values_audit.py"; then
        pass "every marked count and default agrees with Sources/"
    else
        fail "a marked number disagrees with the code" \
            "Each line above names the document, line, stated number and the real one." \
            "Correct the prose; mark any new number read from code the same way."
    fi
else
    fail "Scripts/docs_values_audit.py --self-test failed" \
        "The audit must name an off-by-one table before it checks the documents."
fi

# ---------------------------------------------------------------------------
printf '\n'
if [[ "$failures" -gt 0 ]]; then
    printf 'docs audit: %s check(s) failed. The documentation contradicts the tree.\n\n' "$failures" >&2
    exit 1
fi

printf 'docs audit: the paths, links, test count, worktree cleanup order, release bullets, performance headline scope, CLAUDE.md delegation, uttrflow-eval examples, disk table arithmetic and bake-off corpus inventory in %s documents all check out.\n\n' "$DOC_COUNT"

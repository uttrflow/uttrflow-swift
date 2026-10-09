# Workflow: from branch to merged pull request

`main` is the only long-lived branch and is always releasable; every change reaches it through a
pull request. The always, ask-first and never rules are in `AGENTS.md`, "Boundaries"; this page
holds the contribution contract around them.

## Before you start

1. **Look for existing work.** `gh issue list --search "<keyword>"` and
   `gh pr list --state open --search "<file or keyword>"` return nothing covering the same change,
   or you link what they return. `CONTRIBUTING.md` says how to claim an issue.
2. **One logical change per pull request**, at most 400 changed lines excluding generated files,
   baselines and `Docs/` (`git diff --shortstat origin/main`). A larger change is split into a
   series that each pass `make verify`.

## Plans and future work

A plan, a task list, a hand-off note or any other working artefact of a session is local to
the checkout that made it. Work that is found and not done in the current change is an issue.

| Rule | Check | Pass |
|---|---|---|
| A plan lives only at `/PLAN.md` or under `/.plans/`, both gitignored | `git ls-files PLAN.md .plans` | prints nothing |
| No other working artefact reaches the root | `python3 Scripts/root_layout_audit.py` | exits 0 |
| Future work, a deferred fix or a measurement still owed is an issue, not a line in a tracked file | `gh issue create`, linked from the pull request; the reviewer counts 0 "still owed", "not yet" or "later" lines added to `Docs/` without an issue link in the pull request | 0 |

A `Docs/` page records what is true and why; an issue records what is not done yet. When an
issue closes, the page changes in the same pull request.

## How a pull request lands

1. It targets `main`: `gh pr create --base main`.
2. CI runs `make verify` and builds the app bundle. 0 failing and 0 pending checks
   (`gh pr checks`); a running check is not a passed check.
3. The live `main` ruleset requires one approving review.
   It also requires code-owner review, resolution of review threads, dismissal of stale
   reviews after a push, and approval by someone other than the last pusher. The branch
   must be up to date with `main`, enforced by `strict_required_status_checks_policy`, so
   what merges is what was tested.
4. When `main` is red, the next merge is the repair. `gh run list --branch main --workflow ci.yml
   --status completed -L 1` shows `success` before any other pull request merges; while it shows
   `failure`, the only pull request that merges is one whose body names the failing step and
   whose own `make verify` passes on the current tip.

## Evidence each change type needs

| Type | Required evidence in the pull request |
|---|---|
| Bug fix | the root cause and the new test, which fails on the original code and passes on the fix, with both runs shown ([code-quality.md](code-quality.md#fixing-a-defect)) |
| Feature | tests for the behaviour, the `Docs/` page, and the measurement its area records |
| Refactor | 0 behaviour change: no existing assertion edited or removed, all existing tests unchanged and green |
| Recognition, correction or cleanup | the `make bakeoff` score before and after; a drop in any metric is named and justified |
| AI suggestions | precision and coverage before and after, from the loop in `Docs/predict-reliability.md` |
| Input, insertion, context reading or suggestions | evidence from a real application for each kind it affects ([product.md](product.md#applications)) |
| App shell, resources or entitlements (`Sources/Uttrflow/`, `Resources/`) | `make app-preflight` passes |
| Docs only | `make docs-audit` and `make disclosure-audit` pass |
| Dependency, workflow or minimum macOS or Xcode version | its own pull request, linking the issue that agreed it |

## Commits

1. Every commit builds; `git log origin/main..HEAD --format=%s | grep -c -E '^(fixup|squash)!'`
   prints 0.
2. Subject: imperative mood, at most 72 characters, no trailing period, no `fix:` or `feat:`
   prefix. A pull-request title follows the same rule.
3. Body: why, in 2 to 4 lines. A fix states the root cause and how the fix removes it.
4. No `Co-Authored-By:` trailer; `python3 Scripts/disclosure_audit.py --range origin/main..HEAD`
   exits 0, and the commit-msg hook refuses one.

## Pull request description

Use `.github/PULL_REQUEST_TEMPLATE.md`; `gh pr create --fill` skips it. "How you know it works"
names the commands and numbers, before and after where there is a measurement, and lists every
check that was not run.

## When something fails

1. **A test that fails after your change is yours** until it also fails on a clean checkout of
   `origin/main`. Check in a second checkout; never stash or revert your change to find out.
2. **A gate that fails is the gate working.** Fix the code or the text.

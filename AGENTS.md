# Working in this repository

<!-- release-policy:v1 -->
## Branching & Release Policy — NON-NEGOTIABLE

**Effective 2026-08-28. This supersedes anything elsewhere in this file, or in any agent's
memory, that says to commit or push directly to `main`.**

`beta` is the gatekeeper. Nothing reaches `main` except through it.

```
feature branch  ──PR──>  beta  ──batched release PR──>  main
   (no CI)               (no CI)                        (CI + CD, once)
```

1. **Cut every branch from `origin/beta`**, never from `main`, never from a stale local checkout:
   `git fetch origin && git worktree add ../worktrees/<slug> -b <branch> origin/beta`
2. **Every PR targets `beta`** — `gh pr create --base beta`. No size threshold, no "this one is
   trivial", no hotfix lane. An urgent fix still goes to `beta`; the operator decides whether it
   warrants an immediate release.
3. **No CI and no CD on `beta`, on feature branches, or on PRs into `beta`.** GitHub Actions
   minutes are the scarce resource — workflows fire on `main` only. The consequence is that
   **nothing verifies your branch for you**: run this repo's gates locally before every push.
4. **`beta → main` is operator-only.** Agents never open a release PR, never merge to `main`,
   never force-push. Sole exception: the user asks for a release in the current turn.

**Releases are batched and deliberately infrequent.** No minor feature is released on its own.
`beta` accumulates a meaningful body of change, then the operator cuts one release PR that fires
CI/CD once for the whole batch. So: **your task is done when it is merged to `beta` and your
branch and worktree are cleaned up — not when it reaches production.** Work sitting on `beta`
for days is the design, not a stall. Do not ask for a release and do not nudge one along.

After the merge, clean up from the default checkout (not the worktree) and verify nothing is left:

```bash
git worktree remove ../worktrees/<slug>
git branch -d <branch>
git push origin --delete <branch>            # if gh did not already
git worktree list                            # only the default checkout
git branch                                   # only main + beta
git ls-remote --heads origin <branch>        # zero lines
```

**Stop and ask** on any anomaly — an unexpected repo state, a branch or worktree you did not
create, a `beta → main` PR you did not open, a merge or cleanup you cannot complete cleanly.
Never force-fix, never delete state to make a command succeed.

The policy above is complete for this repository — everything a contributor needs is on
this page. It is one repository's copy of a rule that spans several, and the cross-repo
document that tracks the rest of them is the operator's own and is not published here.

Read this before doing anything. Most of it exists because the obvious path was tried,
cost something, and was abandoned — so an agent that reasons from first principles will
propose things that have already been rejected here for reasons the code does not show.

`PLAN.md` is the live phase tracker. Read it rather than reconstructing the state of the
project from `git log`.

## Where this sits

Four pieces: this app, `uttrflow-backend` (Go on ECS, the only thing that touches the
server's database), `uttrflow-fe` (Next.js on ECS, the site), and `uttrflow-panel` (design
source). Infrastructure is shared with the open-llm AWS account; the data is not.

**Two databases, and they hold different things.** The server's holds an account: who
somebody is, what they have paid for, which machines are signed in. This app's local store
— under Application Support — holds the clipboard, the dictation history, the personal
dictionary and the snippets, and **none of it is ever sent anywhere**. Transcriptions are
local, full stop: the product's whole claim is that dictation happens on this Mac and stays
here. If that ever changes it is a product decision with a privacy page attached, not a
refactor.

**This app talks to the backend's API and to nothing else on the network** — see
`UttrflowAccount`, which is deliberately the only module that can reach a server. That is
what makes "the offline promise" checkable rather than asserted: there is one place to look.

## Rules that are not preferences

**Never put a real email address or a real postal address in a fixture.** Use
`example.com` and an invented street; `Scripts/pii_audit.sh` fails the build on anything
else, and it runs first in `make verify` so you find out in two seconds rather than after
a build.

This is a rule because it has already happened twice. A stranger's real address — real
complex, real road, real pincode — was the sample expansion for the "my address" snippet
and had reached eleven files before anyone noticed; the owner's personal email was the
account fixture. Both looked exactly like the sample data around them, which is the whole
problem: fixture data has to look real to be useful, and the most available realistic
value is the one you can see from where you are sitting. **This repository is being
open-sourced, and a published address cannot be taken back by a later commit.**

**Never add a GitHub Actions workflow.** There is no CI and there will not be. macOS
runners bill at ten times Linux; this project cannot use Linux; fifty-one runs over two
days ate 97% of a month's included minutes and jobs then stopped starting silently for
days. The source is private, so free public-repo minutes are not available. The gate is
`.githooks/pre-push`. Full reasoning in `Docs/releasing.md`.

**Never run `git add -A`, `git add .`, or `git commit -a`.** More than one agent works in
this repository at once, and a blanket add sweeps another session's half-finished work
into your commit under your message. This has happened four times. Stage the paths you
touched, by name.

**Never rewrite pushed history, and never rebase while another session is committing.**
Check first: `ps aux | grep -c '[c]laude.*--add-dir'`.

**Every feature is built in a worktree cut from `origin/beta`, then merged into `beta` by
PR.** `beta` is the trunk agents write to; the feature branch exists only for the length of
the work, and `main` is reached only by the operator's batched release — see the release
policy at the top of this file.

```bash
git fetch origin
git worktree add .claude/worktrees/<name> -b <name> origin/beta   # from beta, not from HEAD
cd .claude/worktrees/<name>                                       # and stay there
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
… work, commit by name, `make verify` — no CI will run for you …
# the pre-push hook runs `make verify` again for beta itself, which is the only gate left
git push -u origin <name> && gh pr create --base beta
cd -                                                              # back to the main checkout
git worktree remove .claude/worktrees/<name> && git branch -d <name>
git push origin --delete <name>
```

The isolation is the point, and it is not bureaucracy: more than one agent works in this
repository at once and a shared `.build` corrupts under two concurrent builds, which is
why `swift build` in the main checkout while anyone else is working is separately
forbidden below. A worktree gives the work its own `.build`, its own index, and a `git
status` that shows only what this task changed — which is what makes staging paths by
name possible at all.

**Rebase onto `origin/beta` before opening the pull request, never onto `main`.** Beta
moves under you while you work — it is where every agent lands — so a branch cut this
morning is behind by lunchtime, and rebasing is what keeps the diff in the pull request
the change you actually made. Rebasing an unpushed branch is not rewriting pushed history,
so the rule above does not conflict with this one.

**Nothing an agent does touches `main`.** Not a merge, not a rebase onto it, not a release
pull request, not a docs commit that seems too small to matter. `main` is the operator's,
reached only by the batched `beta → main` release described at the top of this file. If
you find yourself with a commit on `main`, stop and say so rather than tidying it away.

**Clear the worktree the moment the work is merged.** `git worktree remove` and delete the
branch. Four stale worktrees once sat holding pre-rename copies of the whole tree, and an
abandoned one is indistinguishable from work in progress to the next session that finds
it. `.claude/worktrees/` is gitignored, so nothing warns you.

`sasta-trader` is a different project and does not follow any of this.

**Never run `swift build` or `swift test` in the main checkout while subagents are
working.** They share `.build` and corrupt each other. Give parallel agents
`isolation: "worktree"` — or, when the session's working directory is not itself a git
repository and that fails, cut the worktrees by hand with the recipe above and point each
agent at one by absolute path.

**`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`** before any swift
command, in every shell and in every agent prompt. A hook or a subagent does not inherit
it from an interactive profile.

## Building and releasing

`Docs/releasing.md` is the only correct description. In short:

```bash
make verify        # lint, build, 2,640 tests, coverage floor — what the gate runs
make hooks         # once per clone; hooks are not cloned
make app-hardened  # a build fit to test on another Mac
make dmg           # the disk image
make publish       # to the public downloads repository, using this Mac's gh login
```

Versioning is **semver**, hand-edited in `Resources/Uttrflow-Info.plist`. Calendar
versioning was built and reverted; do not propose it again.

Downloads go to the public **uttrflow/releases** repository. Source repositories stay
private. The published asset is `Uttrflow.dmg` with **no version in the name** — that is
what makes the `/releases/latest/download/` URL permanent.

**Every publish is a full release, signed or not**, so `/releases/latest/download/`
always resolves to the newest build and the download button never has to change. Unsigned
builds take a `-test.<sha>` tag so the bare `v<version>` tag stays free for the notarised
release of that version. `latest.json` records `gatekeeper`, and the site shows or hides
the `xattr` instruction from that field — publishing a notarised image is the whole
migration.

## Tooling traps, each of which cost real time

- **`swift-format` is not on `PATH`** — it is `xcrun swift-format`, via `make lint` /
  `make format`. Capture its exit code explicitly; reading the output through a pipe
  swallows the failure. zsh has `$pipestatus` (lowercase, 1-indexed), not `$PIPESTATUS`.
- **zsh does not word-split unquoted variables.** `kill -9 $PIDS` passes one newline-joined
  blob and fails with "illegal pid". Pipe to `xargs -n1`, or use `${=PIDS}`.
- **MLX targets cannot be built by `swift build`** — they need `xcodebuild` plus the Metal
  Toolchain (~690 MB). MLX is quarantined in `UttrflowLocalModel` and `uttrflow-bakeoff` so
  that nothing else ever needs it.
- **The app is built with `xcodebuild`, not `swift build`.** SwiftPM bakes an absolute path
  into the generated resource-bundle accessor and puts the bundles where a signed app
  cannot carry them. `Docs/packaging.md` has the measurements.
- **`git ls-files` and `git grep` only see tracked files.** A repo-wide rename using them
  silently skipped four new files and then reported "clean". Use `find` when the change
  must cover work in progress.
- **`secrets` is not available in a workflow step's `if:`** — the condition evaluates to
  nothing and every guarded step runs. (Kept here in case a workflow is ever written
  elsewhere; see the first rule.)

## The method that has repeatedly paid off

**Probe the real API before coding, and distrust an implausible number.** That is what
caught `AVAudioConverter` silently truncating 51% of audio, Apple's undocumented Hindi
ability, train-on-test contamination in the prompt examples, and the local models scoring
13% only because nobody was stripping their `Cleaned: "…"` wrapper.

**A CLI is not a representative test bed for the Accessibility API**, and a well-behaved
target never exercises the broken path. `Docs/` and the comments in
`Sources/UttrflowInput/` carry the specific traps.

## Quality bar

- 95% line coverage per module, enforced by `Scripts/coverage.sh`. Exclusions live in
  `Scripts/coverage_report.py` **with a stated reason each, printed on every run** — an
  exclusion is never silent.
- Swift 6 language mode, strict concurrency, warnings as errors.
- No force unwraps, no force try, no implicitly unwrapped optionals (lint-enforced).
- Nothing about the evaluation corpus may reach a shipped app; `Scripts/bundle.sh` checks
  the built artefact for it and refuses.

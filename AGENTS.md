# Working in this repository

<!-- release-policy:v3 -->
## Branching & Release Policy — NON-NEGOTIABLE

**Effective 2026-09-02. Supersedes release-policy:v2, which said agents never merge to
`main`; rule 5 below now says they may, once a pull request is green. Everything else
stands, including that this repository is the only home for the project and that the
`beta` branch in any agent's memory belonged to the private one and does not exist here.**

**One long-lived branch, `main`, always releasable. A release is a tag, not a branch.**

```
branch / fork  ──PR──>  main  ──tag v0.3.0-rc.1──>  prerelease  (soak)
   (CI runs)          (CI runs)  ──tag v0.3.0────>  release
```

1. **Cut every branch from `origin/main`.** Short-lived. A branch that lives for weeks is a
   merge conflict being written slowly.
2. **Every PR targets `main`** — `gh pr create --base main`. There is no second trunk to
   choose between any more.
3. **CI runs on every pull request and must be green.** `.github/workflows/ci.yml` runs
   `make verify` and builds the app bundle; CodeQL and dependency review run beside it.
   Run `make verify` locally anyway — it is the same command, and finding out here is
   faster than finding out in a queue.
4. **Nobody pushes to `main` directly.** A ruleset blocks force-pushes and deletions,
   and everything reaches `main` through a pull request. Never force-push `main`, and
   never tag: tagging is the release, and the release is the operator's.
5. **An agent may merge its own pull request once it is green** — every required check
   passed, and the branch up to date with `main` so what merges is what was tested. This
   reverses release-policy:v2, which said agents never merge. The gate was written for a
   team with reviewers in it; on a one-person org the review requirement could never be
   satisfied, so it was not a gate but a queue. What actually catches mistakes here is
   CI, and CI runs before the merge either way.
6. **Green means green, not nearly.** A check still running is not a passed check. If
   you merge past a failing or unfinished check, you are doing it because the operator
   said to, and you say so plainly when you report it — never silently with `--admin`.
7. **Your task is done when the work is merged and your branch is cleaned up.** Do not
   tag, and do not release.

**Releases stay batched and infrequent.** That has not changed; only the mechanism has.
`main` accumulates merged work, and the operator decides when a commit on it becomes
`v0.3.0`. See `RELEASING.md`.

**Why there is no staging branch, since an agent reasoning from first principles will
propose reinstating one.** The gate belongs on the pull request, not after it. A staging
branch tests code that has *already been merged* — the bad change is in a shared branch,
blocking everything else waiting there, and somebody has to notice and back it out. CI on a
PR tests the merge result *before* the merge is allowed, so it never lands. Same check,
earlier. What a staging branch additionally gave — a build real people run before it is the
default — is what `-rc` tags give, without a permanent branch to keep in sync.

Read this before doing anything. Most of it exists because the obvious path was tried,
cost something, and was abandoned — so an agent that reasons from first principles will
propose things that have already been rejected here for reasons the code does not show.

`PLAN.md` is the live phase tracker. Read it rather than reconstructing the state of the
project from `git log`.

## Comments: one line, present tense — NON-NEGOTIABLE

**A comment is one line. A doc comment is one line. Both say what the code does now.**

```swift
/// Refuses audio with no speech in it, so silence is not transcribed as words.
```

Not:

```swift
/// Refuses audio with no speech in it.
///
/// This used to return quietly to idle, which was indistinguishable from the app
/// being broken — the user held the key, spoke, let go, and nothing happened. It was
/// then changed to throw, but the error had no severity, so the menu bar showed it as
/// a fault. Three attempts later it became what it is now...
```

Both describe the same function. Only the first is still true in four months.

### The rule

1. **One line per comment block.** No `///` or `//` run longer than one line.
2. **Present tense, about the present code.** What this function does, what this line
   is for, what the value means. Not what it did before, not what somebody tried,
   not how many times something has gone wrong.
3. **A reason is allowed when it changes what a reader would do** — "kept under the
   lock because `deinit` can run on any thread" earns its place. A reason that is only
   a story does not.
4. **The trailing comment on a line of code is exempt from the length rule** and still
   bound by the rest.
5. **Document a parameter only where one line covers it.** `swift-format` rejects a
   singular `- Parameter` on a function that has more than one, and a plural
   `- Parameters:` block is multi-line by construction — so a function with several
   parameters documents all of them or none, and none is what this rule chooses. Say what
   is surprising about an argument in the summary line instead. Swift labels arguments at
   the call site, so the loss is smaller than it looks.

### Where the rest goes

Some of what these comments carry is genuinely worth keeping: a measured number, a
platform trap, an approach that was tried and does not work. That belongs in `Docs/`,
under a heading, where it can be read on purpose and revised as a piece —
`Docs/silence.md` and `Docs/stuck-recording.md` are what this looks like. Link to it in
the one line:

```swift
/// Judges the audio before it is decoded. See `Docs/silence.md`.
```

**Deleting a hard-won measurement is not the point of this rule.** Moving it somewhere
it stays true is.

### Why

The comments in this repository were written as a running account of how each decision
was reached, and there are 17,000 lines of them against 36,000 lines of code. After a
few months that account is a liability rather than an asset: it describes code that has
since moved, it buries the one sentence a reader needs under six they do not, and the
reader cannot tell which parts still hold. What a function *does* is checkable against
the code in front of you. What it *used to do* is not checkable at all.

### How it is enforced

`Scripts/comment_audit.py` counts multi-line comment blocks per file and fails when any
file gains one, against `Scripts/comment_baseline.json`. It runs in `make verify`.

The baseline only ever goes down — `--update` refuses to record a higher count for any
file, and shrinking one file does not pay for growing another. Bring a file you are
already editing down to the rule and re-record; do not rewrite the whole repository in
one pass.

```bash
python3 Scripts/comment_audit.py --report                 # what is left, worst first
python3 Scripts/comment_audit.py --update                 # re-record after improving a file
python3 Scripts/comment_audit.py --update --after-merge   # only when main moved under you
```

`--after-merge` is the one way a count may rise, and it exists because rebasing onto
`main` brings in files this rule has not reached yet — blocking a branch on those would
punish whoever rebased rather than whoever wrote them. It prints every rise and records
it, so the increase appears in `comment_baseline.json`'s diff where a reviewer can see
it. Do not reach for it to excuse your own comments.

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

**CI exists now, and it is `.github/workflows/`.** This reverses a rule that was absolute
in the private repository, so it is worth saying why rather than leaving two agents to
argue about it. The old rule was: never add a workflow, because macOS runners bill at ten
times Linux, this project cannot use Linux (it builds against macOS 26 frameworks and
drives the real Accessibility, clipboard and speech APIs), and fifty-one runs over two days
ate 97% of a month's included minutes — after which jobs stopped starting silently, for
days, while the repository went on looking green.

Every part of that is still true except the part that mattered: **a public repository does
not pay for standard runners.** The constraint was cost, the cost is gone, and the local
gate — `.githooks/pre-push`, installed with `make hooks` — is still worth having because it
is still the fastest answer.

There are five workflows and each earns its keep: CI, release, CodeQL, dependency review,
Scorecard. Do not add a sixth without asking.

**Never run `git add -A`, `git add .`, or `git commit -a`.** More than one agent works in
this repository at once, and a blanket add sweeps another session's half-finished work
into your commit under your message. This has happened four times. Stage the paths you
touched, by name.

**Never rewrite pushed history, and never rebase while another session is committing.**
Check first: `ps aux | grep -c '[c]laude.*--add-dir'`.

**Every feature is built in a worktree cut from `origin/main`, then merged into `main` by
PR.** The feature branch exists only for the length of the work, and nothing reaches `main`
except through a reviewed pull request — see the release policy at the top of this file.

```bash
git fetch origin
git worktree add .claude/worktrees/<name> -b <name> origin/main   # from main, not from HEAD
cd .claude/worktrees/<name>                                       # and stay there
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
… work, commit by name, `make verify` — no CI will run for you …
# the pre-push hook runs `make verify` for main; CI runs it once more on the PR
git push -u origin <name> && gh pr create --base main
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

**Rebase onto `origin/main` before opening the pull request.** `main` moves under you while
you work — it is where everything lands — so a branch cut this morning is behind by
lunchtime, and rebasing is what keeps the diff in the pull request the change you actually
made. Rebasing an unpushed branch is not rewriting pushed history,
so the rule above does not conflict with this one.

**Nothing an agent does touches `main` except through a pull request.** Not a direct
push, not a rebase onto it, not a tag, not a docs commit that seems too small to matter.
A ruleset blocks it at the server, so this is a description of what will happen rather
than a request. If you find yourself with a commit on `main`, stop and say so rather
than tidying it away.

**Merging is not reviewing.** Nobody else read the change, so the pull request is where
you write down what you would have wanted a reviewer to know: what was measured, what
was assumed, and what you are least sure of. A merge that ends the conversation is worse
than no merge at all.

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

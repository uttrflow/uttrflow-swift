# AGENTS.md

Uttrflow is dictation software for macOS with a clipboard and AI suggestions built in, entirely
on-device. This file is for everyone who works on it, by hand or with an agent. `CLAUDE.md`,
`.cursor/rules/` and `.github/copilot-instructions.md` only point here.

## Read first

1. This file.
2. Your `AGENTS.local.md`, if you keep one (see "Local rules").
3. The rule file for your work:

| You are... | Read |
|---|---|
| writing or changing code, tests or comments | [Docs/agents/code-quality.md](Docs/agents/code-quality.md) |
| changing anything a person sees: SwiftUI or AppKit views, colours, typefaces, layout, appearance, animation, components, `Design/` | [Docs/agents/design.md](Docs/agents/design.md) |
| changing what dictation, AI suggestions, the clipboard or the data stores do | [Docs/agents/product.md](Docs/agents/product.md) |
| changing how accurately dictation recognises, corrects or formats words | [Docs/dictation-quality.md](Docs/dictation-quality.md) |
| branching, committing or opening a pull request | [Docs/agents/workflow.md](Docs/agents/workflow.md) |
| writing any text that will be committed or posted | [Docs/agents/public-boundary.md](Docs/agents/public-boundary.md) |
| hitting a tooling failure | [Docs/tooling-traps.md](Docs/tooling-traps.md) |

4. [`Docs/README.md`](Docs/README.md), then the page for the module you change.
5. [`Docs/decisions.md`](Docs/decisions.md) before proposing an approach: what was rejected, and what reopens it.

## Commands

```bash
make verify                      # the whole gate: audits, lint, build, tests, coverage, offline audit
make lint                        # style and documentation violations
make format                      # rewrite sources in canonical style
make build                       # compile every module
make test                        # run the test suite
swift test --filter <TestCase>   # one test case or method, the fast loop
make coverage                    # tests plus the per-module coverage floor
make bakeoff                     # score every clean-up engine against the corpus
make app-preflight               # build the app bundle and verify its signature, as CI does
make hooks                       # install the commit-msg and pre-push gates, once per clone
```

`swift build` does not build the app bundle; `make app-preflight` does. Run `make verify` before
every push; CI runs the same command. Commands in these files write the base branch as
`origin/main`; in a fork, use the remote that points at this repository.

## Layout

- `Sources/`: one SwiftPM target per module (`Uttrflow*`) plus the `uttrflow-dev`, `uttrflow-eval`
  and `uttrflow-bakeoff` tools. `Tests/` mirrors it.
- `Docs/`: a page per subsystem, holding the measurements, platform traps and rejected approaches
  the code cannot say for itself.
- `Scripts/`: audits, release and packaging. `Design/`: design canvases. `Resources/`: bundle
  resources and `Uttrflow-Info.plist`.

## Non-negotiables

Each links to its one home, where the limit and the check live.

1. [Dictation is a transcript, not a rewrite.](Docs/agents/product.md#dictation-and-clean-up)
2. [Latin letters only; Hindi is romanised, never translated.](Docs/agents/product.md#dictation-and-clean-up)
3. [The user's data stays on this Mac.](Docs/agents/product.md#across-every-feature)
4. [Fix the root cause, with one implementation per capability.](Docs/agents/code-quality.md#fixing-a-defect)

## Gates

Each gate fails its command. Thresholds and the full list are in
[code-quality.md](Docs/agents/code-quality.md#gated-limits).

| Gate | Command |
|---|---|
| Multi-line comment blocks never rise per file | `make comment-audit` |
| 0 changed or removed evaluation cases not named in `Scripts/corpus_edits.txt` | `make corpus-edit-audit` |
| Colours, typefaces, canvases and contrast follow `Docs/agents/design.md` | `make design-audit` |
| Coverage at least 95% per module | `make coverage` |
| 0 force unwraps, `try!`, implicitly unwrapped optionals | `make lint` |
| 0 compiler warnings | `make build` |
| Spelling matches decided by shape never rise | `make match-audit` |
| Logic-module UI imports and platform dependencies never rise | `make layering-audit` |
| 0 real personal data in fixtures | `make pii-audit` |
| 0 privacy, accuracy or speed claims in user-facing text without registered evidence | `make claims-audit` |
| 0 connections on the dictation path | `make offline-audit` |
| 0 conversation or reference material in tracked text | `make disclosure-audit` |
| 0 contradictions between docs and tree; 0 dates or issue numbers in rule files | `make docs-audit` |
| 0 failing or pending checks on a pull request called ready | `gh pr checks` |

## Working agreement

1. **Surgical.** `git diff --stat origin/main` lists only files the task needs. 0 behaviour-neutral
   reformatting, renames or reflows outside the lines the task changes; anything else you notice
   becomes a separate issue.
2. **Check first.** Before coding, write the success check: one command and its expected result.
3. **No invention.** 0 invented APIs, defaults, UI strings or behaviours: read the code or run it
   before stating a fact about it.
4. **Honest reports.** Every "passes" or "works" names the command and its result. Every check
   you did not run is listed, with the reason.

## Boundaries

**Always**
- branch from freshly fetched `origin/main`, and read `git status -sb` before the first edit;
- commit only the files the change needs;
- run `make verify` before every push;
- give the evidence the change type needs ([workflow.md](Docs/agents/workflow.md#evidence-each-change-type-needs)).

**Ask first**, in an issue or in the pull request, before you:
- add a dependency or a workflow ([code-quality.md](Docs/agents/code-quality.md#dependencies));
- change a protected file ([code-quality.md](Docs/agents/code-quality.md#protected-files));
- change a promise in `Docs/definition-of-done.md`;
- change the minimum macOS or Xcode version;
- delete, skip or weaken an existing test assertion.

**Never**
- skip a hook or a check (`--no-verify`) or loosen a gate;
- raise a baseline, except through a script's reported `--after-merge` or `--absorb` path;
- commit a secret, personal data, or text from a private conversation;
- commit a plan or a session's working artefact; future work is an issue
  ([workflow.md](Docs/agents/workflow.md#plans-and-future-work));
- hand-edit a generated file;
- rebase, amend or force-push a branch after review: bring in `main` with a merge;
- describe a security vulnerability in public: report it as `SECURITY.md` says.

## Local rules

Anyone may keep rules for their own setup in **`AGENTS.local.md`** at the root of their checkout;
it is gitignored. A new worktree lacks the main checkout's untracked and ignored files, so read it
from a worktree with `cat "$(git rev-parse --git-common-dir)/../AGENTS.local.md"`. A missing file
is normal.

- It adds and tightens; it never loosens a rule here. One exception: the maintainer's own file
  may move `make verify` from every push to before each release tag. Where the two disagree, this
  file wins.
- Nothing from it is quoted, summarised or paraphrased into a tracked file, a commit message, a
  pull request, an issue or a comment.

## Changing these files

A rule belongs in a tracked rule file only if all three hold:

1. **It applies to anyone who clones the repository**, with nothing but this repository and their
   own fork. A rule about one person's machine, sessions, tools, labels, release duties or other
   repositories goes in their `AGENTS.local.md`.
2. **It prevents a mistake that is not obvious** to someone who knows Swift and macOS.
3. **It is checkable**: a limit and a command, or a review rule with the count the reviewer takes.

It is written in the present tense with 0 incidents, 0 dates, 0 issue or pull-request numbers and
0 anecdotes; `make docs-audit` fails on dates and issue numbers. Evidence goes on a `Docs/` page,
linked in one line. Each rule has one home; every other mention is a link to it. A rule that no
longer prevents a mistake is deleted.

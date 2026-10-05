# Contributing to Uttrflow

Thank you for looking. This is a small project, so the process is deliberately
short.

## You do not need anything of ours to work on this

**No account, no API key, no access to any server of ours.** The app runs entirely on your
Mac: dictation is on-device, and the clipboard, history, dictionary and snippets are in
Application Support and are never sent anywhere.

The one screen that would need a network — sign-in — offers **"continue on this Mac"**
beside the providers, which uses the name macOS already knows you by and needs nothing.
That is not a degraded mode built for contributors; it is a real product path for people
on a captive portal or a locked-down Mac, and it is on the same page as the providers
rather than appearing only after something fails.

So: clone, build, run. Everything works.

```bash
git clone https://github.com/uttrflow/uttrflow-swift.git
cd uttrflow-swift
make verify        # lint, PII audit, build, tests, coverage floor, offline audit
make app           # builds and ad-hoc signs dist/Uttrflow.app
open dist/Uttrflow.app
```

Requirements: an Apple Silicon Mac, macOS 26 or later, and Xcode 26.6 or later.
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any Swift command.

The test suites that check this app against fixtures emitted by the backend service, which
is not open source, are skipped for you and say so when they are. They are the only part of
the suite you cannot run, they are not required for any change, and their
absence is reported rather than silently passing.

## If the build or tests misbehave

An incremental test build can report an impossible mismatch after a type changes — for
example, `nil` not equalling `nil` after an enum case is added. Clear SwiftPM's build
products and run the full verification again:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift package clean
make verify
```

If the failure remains after a clean run, investigate it as a real failure.

## Randomised and property tests

Every randomised test draws from `Seeded` in `UttrflowTestSupport`; a test module never
declares its own generator. `make verify` runs fixed seeds, so it is the same on every
run. A property test takes its seeds from `Seeded.seeds(...)` and names the generator
(`seed=<n>`) in its failure message, so the failure can be replayed alone:

```bash
UTTRFLOW_SEED=<n> swift test --filter <TestCase>
```

A test that finds a bug adds the minimal failing case as a fixed example in the same pull
request.

## How a change gets in

1. **Fork, and branch from `main`.** Short-lived branches, please — a branch that lives for
   weeks is a merge conflict being written slowly.
2. **Run `make verify` yourself before pushing a branch.** The pre-push hook runs the
   disclosure check on every push, but runs `make verify` only when pushing to `main`;
   `make hooks` installs that hook. CI then builds and verifies the signed app bundle
   separately; those packaging, resource, entitlement, and signing checks are not part of
   `make verify`. When a change can affect them, run the same sequence CI uses:
   `make verify` followed by `make app-preflight`. A change to dictation, clean-up, latency or
   memory also needs a before-and-after measurement; [`Docs/measure-a-change.md`](Docs/measure-a-change.md)
   says which command, how long it takes and what it needs. A new cleaning or a new kind of
   place follows [`Docs/adding-a-pass.md`](Docs/adding-a-pass.md) or
   [`Docs/adding-a-destination.md`](Docs/adding-a-destination.md).
3. **Open a pull request against `main`.** CI runs on it. It must be green.
4. **A maintainer reviews and merges.** Nobody can push to `main` directly, including the
   maintainer.

Small PRs get reviewed. Large ones get reviewed eventually. If you are planning something
substantial, open an issue first so you do not build something that then gets declined for
a reason that could have been said in a paragraph.

## Claiming an issue, and what claiming it guarantees you

**Say on the issue that you are taking it, and it is yours.** One comment is enough — no
form, and you do not need to wait for an answer before you start.

What the claim buys you is specific, because a vaguer promise would be worth nothing:

- The issue gets the `claimed` label, and an assignee if GitHub will let us set one.
- **No maintainer works on it while it is claimed.** Not a smaller version of it, not "just
  the doc part", not as a side effect of a larger branch that happens to cross it.
- If a maintainer branch has to touch the same lines for an unrelated reason, we say so on
  the issue before pushing, not after.
- A claim lapses after two weeks of silence, and we ask on the issue before releasing it.

If we take a claimed issue anyway, that is a bug in how this project is run — please say so
on the issue, and it will be treated as one.

## What the code review is looking for

The rules are in [`AGENTS.md`](AGENTS.md) and the files it links, for people and agents alike.
The ones a first pull request most often misses:

- **Comments are one line, in the present tense**, and say what the code does now; history and
  measurements go on a `Docs/` page.
- **Tests assert behaviour somebody cares about**, and their names are sentences.
- **Test files and suites are named for the behaviour they pin, never for an issue.** A regression
  case lands beside the others for that behaviour, with the issue number as a `.bug(id:)` trait;
  `make test-name-audit` refuses a file named `Issue<number>`.
- **`make verify` is green**: it runs the coverage floor, the PII audit, the disclosure audit and
  the offline audit, among others.

## Releases, and how quality is kept without a staging branch

There is one long-lived branch: `main`. A release is a **tag**, not a branch.

The gate is on the pull request, not after it: CI builds and runs the full suite against the
merge result before the merge is allowed, so there is no staging branch. A release candidate is
a prerelease tag such as `v26.0926.0-rc.1`; `v26.0926.0` ships it.

Full detail in [`RELEASING.md`](RELEASING.md).

## Reporting a bug

Use the issue templates. The one thing that helps most is what you expected versus what
happened — a transcript of the steps beats a description of the conclusion.

**Do not open an issue for a security problem.** See [`SECURITY.md`](SECURITY.md).

### Labels for a wrong dictation

A dictation that came out wrong carries one class label and one layer label, so every issue of
one kind is a single label query.

| Label | Meaning |
|---|---|
| `quality:meaning` | the output says something the speaker did not say, or nothing was inserted |
| `quality:format` | the words are right; punctuation, casing, numbers or layout are wrong |
| `quality:cosmetic` | the meaning and format are right; a spacing or style detail is off |
| `layer:recogniser` | the speech model heard the wrong words |
| `layer:candidates` | the right word was among the alternatives and a different one was chosen |
| `layer:rules` | a deterministic clean-up rule changed the text |
| `layer:model` | the clean-up model changed the text |
| `layer:seam` | text was lost, doubled or joined wrongly between chunks or sessions |
| `layer:insertion` | the text was right but reached the target app wrong or not at all |

Priority follows the class: `quality:meaning` is P1, and P0 when nothing was inserted.

An accuracy fix names the corpus case it adds, failing before the fix and passing after, or says
why no case can exist.

## Licence

By contributing you agree that your contributions are licensed under the MIT Licence, as
in [`LICENSE`](LICENSE). See [`TRADEMARK.md`](TRADEMARK.md) for the one thing the licence
does not cover: the name and the mark.

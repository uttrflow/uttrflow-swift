# Contributing to Uttrflow

Thank you for looking. This is a small project with one maintainer, so the process is
deliberately short.

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

## You do not need a Mac for every contribution

Most of this tree needs Xcode and Apple Silicon, and CI proves that on every pull request
so you never have to. [`Scripts/pii_audit.sh`](Scripts/pii_audit.sh) and
[`Scripts/fetch-provider-marks.sh`](Scripts/fetch-provider-marks.sh) touch nothing
macOS-specific and run identically on Linux, so a documentation or wording fix can be
checked with those alone, with no Swift toolchain at all — push, and `ci.yml` builds and
tests the rest for you.

```bash
git clone https://github.com/uttrflow/uttrflow-swift.git
cd uttrflow-swift
make verify        # lint, PII audit, build, ~2,900 tests, coverage floor, offline audit
make app           # builds and ad-hoc signs dist/Uttrflow.app
open dist/Uttrflow.app
```

Requirements: an Apple Silicon Mac, macOS 26 or later, and Xcode 26.6 or later.
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any Swift command.

Four test suites are skipped for you, and say so when they are. They check this app
against fixtures emitted by the backend service, which is not open source. They are the
only part of the suite you cannot run, they are not required for any change, and their
absence is reported rather than silently passing.

## How a change gets in

1. **Fork, and branch from `main`.** Short-lived branches, please — a branch that lives for
   weeks is a merge conflict being written slowly.
2. **Run `make verify` before you push.** It is the same command CI runs, so there is no
   class of failure that only CI can find. `make hooks` installs a pre-push hook that runs
   it for you.
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

**This exists because it has already gone wrong.** The first outside pull request this
project ever received (#62) implemented a `good first issue` whose author had asked for it
on the issue thirty-two minutes earlier. Nobody answered them. Twelve minutes after they
asked, a maintainer branch opened doing the same work, and it merged and closed the issue
while their pull request sat open and unreviewed. They had done exactly what this file asks
for. A *good first issue* that a maintainer finishes underneath a newcomer is worse than
never having labelled one.

## What the code review is looking for

This codebase has a particular style, and matching it will save a round trip:

- **Comments explain why, not what.** The rule of thumb: if the code was tried a different
  way first and that way cost something, that is what the comment should say. A comment
  restating the line below it is noise.
- **Tests assert behaviour somebody cares about**, and their names are sentences. Look at
  any existing suite.
- **Coverage floor is 95% per module** and `make verify` enforces it. Exclusions live in
  `Scripts/coverage_report.py`, each with a written reason.
- **No personal data in fixtures.** `Scripts/pii_audit.sh` fails the build on a real email
  address or postal address. Use `example.com` and an invented street; this exists because
  a stranger's real address was once sample data here and reached eleven files.
- **The offline promise is structural, not a claim.** `Scripts/offline_audit.sh` asserts
  that no module on the dictation path can open a connection. If your change needs the
  network, it almost certainly belongs somewhere else.

## Releases, and how quality is kept without a staging branch

There is one long-lived branch: `main`. A release is a **tag**, not a branch.

The gate is on the pull request, not after it. CI builds and runs the full suite against
the merge result **before** the merge is allowed, so a change that breaks anything never
reaches `main`. A staging branch tests code that has already been merged — the bad change
is in a shared branch, blocking everyone, and somebody has to notice and back it out.
Testing earlier is strictly better, and a branch was only ever a proxy for "has this been
tested?"

When enough has accumulated, the maintainer tags a **release candidate** — `v0.3.0-rc.1` —
which publishes as a prerelease. GitHub's `/releases/latest/download/` skips prereleases,
so a candidate can be soaked by anyone who wants it without becoming what the download
button serves. When it holds up, `v0.3.0` ships it.

Full detail in [`RELEASING.md`](RELEASING.md).

## Reporting a bug

Use the issue templates. The one thing that helps most is what you expected versus what
happened — a transcript of the steps beats a description of the conclusion.

**Do not open an issue for a security problem.** See [`SECURITY.md`](SECURITY.md).

## Licence

By contributing you agree that your contributions are licensed under the MIT Licence, as
in [`LICENSE`](LICENSE). See [`TRADEMARK.md`](TRADEMARK.md) for the one thing the licence
does not cover: the name and the mark.

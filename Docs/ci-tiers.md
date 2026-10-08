# CI tiers

Which gate runs on every pull request, which runs nightly, and which runs weekly and before a
release. A new gate names its tier here in the pull request that adds it.

## What one run costs today

`ci.yml` is one `macos-26` job that runs `make verify` and then `make app-preflight` on every
pull request and every push to `main`. Step durations of the ten most recent successful runs,
read with `gh run view <id> --json jobs`:

| Run | Event | Cache SwiftPM (min) | Verify (min) | App bundle (min) |
|---|---|---|---|---|
| 36456093991 | pull_request | 1.7 | 13.3 | 7.3 |
| 36418137959 | pull_request | 1.3 | 13.9 | 6.5 |
| 36377526992 | push | 1.2 | 10.4 | 5.0 |
| 36374603796 | pull_request | 1.7 | 12.2 | 6.8 |
| 36367927656 | push | 1.1 | 13.4 | 7.2 |
| 36365827444 | push | 1.2 | 9.7 | 4.5 |
| 36365332733 | push | 1.4 | 13.6 | 7.0 |
| 36360872898 | pull_request | 1.6 | 13.7 | 6.5 |
| 36359332521 | pull_request | 1.4 | 12.1 | 7.2 |
| 36358541878 | pull_request | 1.4 | 11.1 | 5.5 |

Median: about 1.4 + 12.7 + 6.7, so roughly 21 macOS minutes per pull request, the same for a
docs-only change as for a change to the engine. `make verify` is not split into steps, so the
share of the 12.7 minutes spent in the audits is not visible in these logs.

## Tier assignment

**Tier 1, every pull request.**

- *Audits, on `ubuntu-latest`.* Every `Makefile` target marked "Needs no build" that runs on
  Python and shell alone: `pii-audit`, `root-audit`, `disclosure-audit`,
  `issue-template-audit`, `docs-audit`, `comment-audit`, `match-audit`, `layering-audit`,
  `type-name-audit`, `public-api-audit`,
  `python-imports-audit`, `ratchet-test`, `mutation-probe-test`, `range-test`, `hits-test`,
  `hook-test`, `pre-push-test`, `pre-push-lock-test`, `issue-template-test`, `flake-audit`,
  `log-audit`, `store-permissions`, `pasteboard-audit`, `context-reach-audit`,
  `exclusion-audit`, `offline-test`, `offline-audit-tokenizer-test`, `release-tag-test`,
  `release-notes-test`, `provider-mark-test`, `soak-test`, `e2e-predict-cleanup-test`,
  `publish-resume-test`, `publish-cleanup-test`, `bundle-test`, `bundle-requirement-test`.
  A target that turns out to call a macOS-only tool (`codesign`, `plutil`, `xcrun`) stays on
  macOS rather than gaining a Linux branch.
- *Build, tests and coverage, on `macos-26`.* `lint`, `build`, `coverage`, `offline-audit`.
- *App bundle, on `macos-26`.* `app-preflight`, only when `Sources/Uttrflow`, `Resources`,
  `Package.swift` or `Scripts/bundle.sh` change.
- *Documentation-only change.* The audits run; the macOS job does not.

**Tier 2, nightly.** The oracle sweep (already `oracle-sweep.yml`), property runs with a random
seed, and scaling tests at the larger sizes.

**Tier 3, weekly and before a release.** The mutation probe, `make bakeoff`, the transcription
gate and the soak.

## Required checks

The required status check names do not change when the job is split. The macOS job keeps the
name `make verify`; a documentation-only change satisfies it through a job of the same name
that skips the build, because a required check that never reports blocks the merge.

## Status

This page is the decision record and the measurement. The workflow edit that implements tier 1
and the documentation-only path changes `.github/workflows/ci.yml`, which needs owner approval;
until it lands every gate above still runs in the single macOS job.

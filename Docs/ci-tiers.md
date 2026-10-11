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

## Lanes

Each check runs in exactly one lane. The lanes are `Makefile` targets, so a run on a Mac and a run
in CI are the same command.

**`make verify`, every pull request (`ci.yml`, required).** Everything that needs no corpus, no
model and no clock: the audits (`pii-audit`, `root-audit`, `disclosure-audit`, `docs-audit`,
`design-audit`, `comment-audit`, `match-audit`, `closed-list-audit`, `duplicate-table-audit`,
`word-split-audit`, `layering-audit`, `public-api-audit` and every other prerequisite of `verify`),
`lint`, one coverage-instrumented `build`, the unit and edge-case tests with the per-module
`coverage` floor, and `offline-audit`. It runs its checks side by side.

**`make eval`, every pull request (`eval.yml`, required).** `uttrflow-eval rules-scorecard` scores
the rules alone over the whole corpus and `Scripts/rules_scorecard.py` compares the result with
`Scripts/rules_scorecard.json` on the base commit. It fails when a case that passed there fails,
unless the branch adds the case to `Scripts/scorecard_accepted.txt`, or when a category's pass rate
falls by more than one point; an improvement or a new case never fails it. A branch that changes
the scores records them with `make rules-scorecard rules-scorecard-update`. The lane also runs the
corpus suites (`UttrflowEvalTests`, and the corpus-wide sweeps in `EVAL_SUITES`: word survival through the pipeline, the loanword probe table, the homophone policy table and the simulated learning weeks) and `seam-audit`, posts the scorecard on the pull request, and
runs every night on `main`. It always starts, because a required check that never reports blocks
the merge, and succeeds in seconds when the change touches nothing under the sources, tests and
scripts it reads.

**`make bench`, nightly (`bench.yml`).** `perf-budget`, `offline-test`, `soak-test`, the scaling
suites (`HeavyClipScans`, `PromptSizeGuaranteeTests`, `BIP39RecoveryPhraseScalingTests`) and the
tests that hold a wall-clock budget (`BENCH_SUITES` in the `Makefile`): the clipboard store's first-list
benchmark, the 20,000-entry suggestion migration, doubt placement's p95, the deeply nested HTML
copy, the launch budget, the n-gram scorer's per-span probes, the SQL notation, field label,
adapter validator and panel grouping speed checks, the settle-delay bound on an unconfirmed write,
the formatter's TERM escalation and the huge-range correction count. Each one that has a logic
twin keeps the twin in `make verify`. A test with a wall-clock limit belongs here, since a parallel test run cannot keep one honest.
It never blocks a pull request; a failure opens an issue titled "Nightly bench failed on main", or
comments on the open one.

**By hand, weekly and before a release.** The oracle sweep (`oracle-sweep.yml`, also nightly),
the mutation probe, `make bakeoff`, the transcription gate and the soak.

Every job runs on the standard hosted `macos-26` runner, and each nightly job once a day.

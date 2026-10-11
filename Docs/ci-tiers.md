# CI tiers

Which gate runs on every pull request, which runs nightly, and which runs weekly and before a
release. A new gate names its tier here in the pull request that adds it.

## Timing probe before the lane split

The probe measured the `ci.yml` job, which runs `make verify` and then `make app-preflight` on
every pull request and every push to `main`. These ten successful runs precede the separate
evaluation and benchmark lanes below; their step durations were read with
`gh run view <id> --json jobs`:

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

The probe's median was about 1.4 + 12.7 + 6.7, roughly 21 macOS minutes per pull request.
It is a historical measurement, not a before/after timing for the current lanes. The verify job
still runs for documentation changes. `make verify` is not split into steps, so the share of the
12.7 minutes spent in the audits is not visible in these logs.

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

**Oracle sweep (`oracle-sweep.yml`).** The full clipboard-reader seed sweep runs nightly and on
pull requests that change its named reader sources, oracle tests or workflow. The fixed sample
stays in `make verify`.

**By hand, weekly and before a release.** The mutation probe, `make bakeoff`, the transcription
gate and the soak run on the Mac that supplies their models, corpus or permissions. Their
evidence belongs to the release checks in [dictation-quality.md](dictation-quality.md).

## Scheduled and manual runs

The checked-in workflows declare these schedules in UTC:

| Workflow | Command or suite | Nightly schedule | Pull requests |
|---|---|---|---|
| `ci.yml` | `make verify`, then `make app-preflight` | none; runs on pushes to `main` | every change, including documentation |
| `eval.yml` | `make eval` | 03:30 | every change; the scope check skips Swift work when no lane input changed |
| `bench.yml` | `make bench` | 02:00 | none |
| `oracle-sweep.yml` | the full clipboard oracle seed sweep | 04:00 | its declared reader, oracle-test and workflow paths |

`ci.yml` has no manual dispatch; its pull request, merge queue and main-push events run the
same gate. Every job uses the standard hosted `macos-26` runner. The evaluation, benchmark and
oracle workflows supply the manual dispatches; the weekly and release checks above are manual
commands. This tier catalogue follows the existing workflows and does not introduce Linux
jobs, a documentation-only runner bypass or a change to required checks.

## Structured quality grid reports

The voice-activity onset and condition grids, number round trips, inflected dictionary probe,
lexicon neighbour report and clipboard prefilter comparison can emit structured records with
`UTTRFLOW_QUALITY_REPORT=1`. This instrumentation leaves their assertions and lane ownership
unchanged. The JSON lines contain stable case IDs, outcomes and numeric measurements, without
recording the text or audio a case processes.

`Scripts/quality_grid_scorecard.py --measured <report> --base <report>` compares two complete
reports. Both inputs may be test logs containing `QUALITY_GRID` lines or JSON objects with a
`records` array. Missing groups, duplicate IDs, malformed records and removed cases fail.
A failing gated record is rejected, including a new case. Number round trips compare failure counts
by bucket, reject a rise against the measured base, and retain each bucket's failure allowance;
individual numbered-case outcomes remain diagnostic. Voice-activity recording-condition
measurements also remain diagnostic, preserving the grid's existing absence of a clipping/over-inclusion tradeoff gate.
The comparator does not treat an absent base as success. Its protocol and comparison checks run
with `python3 Scripts/quality_grid_scorecard.py --self-test`.

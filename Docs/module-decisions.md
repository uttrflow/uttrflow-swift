# Decompose or rewrite: the pipeline actor and the meaning guard

`DictationPipeline` and `MeaningPreservationGuard` carry most of the formatting and safety logic,
and most changes to dictation quality edit one of them. This page decides, from merged history,
whether either is rewritten, decomposed further or left as it is. No rewrite starts without a
decision here, and no split lands that this page does not order, unless it is a pure move.

## The criteria

Each is measured over the changes merged to `main` that touch a module's family of files: the
module's main file plus its extensions (`DictationPipeline+*.swift`; `Guard*.swift` and
`MeaningGuardReference.swift` beside the guard).

| Criterion | Measure | Rewrite when | Decompose when |
|---|---|---|---|
| Change failure | share of those changes whose subject marks a repair of a broken `main` (a revert, "Restore main", "Repair the build", a lint wrap on main) | above 10% | — |
| Seam fit | share of those changes that edit one file of the family | below 50% | — |
| Coupling | median count of other `Sources/` files each change edits | above 5 | — |
| Test cost | median count of `Tests/` files each change edits | above 5 | — |
| Size | lines in the main file | — | over 1,000, where [code-quality.md](agents/code-quality.md#design-limits-for-code-you-add-or-touch) allows 0 new members |
| Hot spot | one member's share of the changes that edit the main file | — | above a third, and the member over the 40-line function limit |

A rewrite needs the change-failure or seam-fit criterion to fail, because only those say the
structure itself causes defects or blocks a change; coupling and test cost alone are met by
narrower seams, not a new design. A decomposition is a sequence of pure moves (below).

## The measurements

```bash
python3 Scripts/module_change_measure.py --since 2026-09-01 --until e500535ad1
python3 Scripts/module_change_measure.py --since "2026-10-07 00:36 +0530" --until e500535ad1
python3 Scripts/module_change_measure.py --since "2026-10-07 02:34 +0530" --until e500535ad1
```

The first window is every merge since the start of September; the second starts after the guard's
verdict became an ordered list of named checks; the third after `process` was split into
take-over, recognise and deliver stages. Each family is read in the window after its own last
seam.

| Module | Window | Changes | Lines per change, median / p90 | One file | Other sources, median | Test files, median | Repairs |
|---|---|---|---|---|---|---|---|
| Pipeline | whole | 171 | 9 / 61 | 90% | 3 | 2 | 3 (2%) |
| Pipeline | after its seam | 30 | 5 / 28 | 80% | 4.5 | 2.5 | 2 (7%) |
| Guard | whole | 103 | 23 / 95 | 86% | 1 | 2 | 2 (2%) |
| Guard | after its seam | 28 | 17 / 73 | 75% | 1 | 2 | 1 (4%) |

Both pipeline repairs after its seam fixed `main` as a whole after crossed merges and lint, not a
defect of the pipeline; the guard's one repair is the same lint wrap.

| Main file | Lines | Hottest member after its seam | Its share | Its length |
|---|---|---|---|---|
| `DictationPipeline.swift` | 1,553 | `deliver` | 11 of 25 (44%) | 126 lines |
| `MeaningPreservationGuard.swift` | 443 | `confidentHomophoneVerdict` | 5 of 11 (45%) | 36 lines |

Test cost is the same per change for both, 2 to 2.5 test files, but differs in kind: 44 test
files build the pipeline actor with fakes for its dependencies, while 19 call the guard's static
checks with no set-up. A pure move changes neither, because the actor's initialiser and the
guard's entry points stay where callers reach them.

## Decisions

| Module | Decision | Because |
|---|---|---|
| `MeaningPreservationGuard` | Neither rewritten nor decomposed further | Every criterion passes: 75% of changes edit one file, a median change edits one other source file, repairs are 4% and not the guard's. The main file is under 1,000 lines and its hottest member is under the function limit. A new check is a row in `GuardChecks.swift`, which is the seam a new guard check needs. |
| `DictationPipeline` | Not rewritten; decomposed by three pure moves, in the order below | Seam fit (80%) and change failure (7%, none the pipeline's own) pass, so the structure does not cause defects. It fails size (1,553 lines, so every new member breaks the file limit) and hot spot (`deliver` takes 44% of the changes at 126 lines), and its coupling, 4.5 other source files per change, is the highest of the two. |

## The pipeline's order

Each step is one pull request, keeps `make verify` green, and is a pure move: `git diff
--color-moved=dimmed-zebra origin/main` shows only moved lines, plus `private` widened to the
module's default access where an extension in another file reads the member, which is how
`DictationPipeline+Cleaning.swift` already reads the actor's state. No behaviour, test or
initialiser changes.

1. **Delivery** into `DictationPipeline+Delivery.swift`: `deliver`, `insert`, `runCommand`,
   `landedIn`, `count`, `learnWords`, about 240 lines. First, because `deliver` and `insert`
   take most of the changes.
2. **Screen reads** into `DictationPipeline+ScreenReads.swift`: `resolveDictationContext`,
   `vocabulary`, `earlyContextRead`, `contextAfterPendingInsertion`, `readContext`, `timed`,
   `insertionContextForWrite`, `contextFor`, about 220 lines.
3. **Recognition** into `DictationPipeline+Recognition.swift`: `recognise`, `transcribe`,
   `decode`, `failure`, `silence`, `timeWait`, about 200 lines.

That leaves the actor's file near 900 lines of state, gestures and lifecycle, under the
1,000-line limit. Only then is `deliver` itself cut, in its new file, along the two steps that
change most: re-casing tidied words whose caret or destination moved, and the learning and
counting that run after the words land. Each comes out under 40 lines.

## Reopen when

- `python3 Scripts/module_change_measure.py --since <the last seam's merge>` puts either module
  over a rewrite threshold in the table above, measured over at least 20 changes.
- The guard's main file passes 1,000 lines, or one guard member takes more than a third of the
  changes at more than 40 lines.
- The pipeline's file is still over 1,000 lines after the three moves, or a member of one of the
  new files takes more than a third of that file's changes at more than 40 lines.

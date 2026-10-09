# What "Copy diagnostics" may carry

Settings > Diagnostics has a "Copy diagnostics" button whose caption says the copy contains no
transcripts. The text it copies is built by one function, `DiagnosticsPresenter.report(for:)` in
`Sources/UttrflowUX/DiagnosticsPresentation.swift`, from a `DiagnosticsSnapshot`. The copy is
pasted into bug reports, so it leaves this Mac by hand.

## The rule

**The copied report carries no word the person said, kept or was offered.** It carries counts,
durations, states, engine and step names, version strings and the closed-enum summary of a
refusal. The page on screen may quote words; the copy never does.

## What each snapshot field contributes

| Snapshot field | In the copied report as |
|---|---|
| `version`, `machine` | the build and this Mac's macOS, chip and memory |
| `measurements` | per-stage typical, slowest and sample count; stages never run are named |
| `decoding` | counts of extra decodes and retries, and the mean recognition split in seconds |
| `waits` | the wait after key-up at p50 and p95 in seconds, how many ran past the target, and a count per closed-enum cause |
| `speechModelLoads` | per kept load: date, seconds, macOS build, short model revision and the closed-enum reason |
| `cleaning` | per offered step: counts removed, rewritten and added; steps switched off; refusal kind summary; engine skipped or failed reason |
| `tidyTally` | per engine over the last 200 pieces: accepted, refused by refusal kind, failed by failure class, skipped by closed reason; pieces no engine finished. Held in memory and emptied by Reset |
| `engines`, `speechInUse`, `transformerAvailability`, `lastCleanedBy` | engine names and states |
| `speechModel`, `speechReadiness`, `speechLoadFailure`, `suggestionModel` | model card status lines; a failed load names its class |
| `permissions` | one granted or not-granted line per permission |
| `dictationShortcutArmed`, `hasDefaultInputDevice` | availability lines |
| `arrivals` | a count of kept dictations per arrival kind |
| `qualityLayers` | nothing: shown on the page only |
| `learnedState` | a line under On disk when the learned-state file is set aside: newer than this build, unreadable, or kept aside and rebuilt from History |
| `vocabularyPrompt` | nothing: dictionary words are absent |

`cleaning` holds the dictated words a step removed or rewrote and the free-text reason a model
answer was refused. The report counts the former and prints only the `RefusalKind` summary of the
latter.

## The check

`Tests/UttrflowUXTests/DiagnosticsReportRedactionTests.swift` fills every text-bearing snapshot
field with invented words and fails if any of them appears in the report:

```bash
swift test --filter DiagnosticsReportRedactionTests
```

`Tests/UttrflowUXTests/DiagnosticsExportContractTests.swift` holds the rest of the contract. It
fails when a `DiagnosticsSnapshot` field is missing from the table above, and when a filled
snapshot holds text at a path it has not classified as a version string, an engine or step name or words
that are never printed:

```bash
swift test --filter DiagnosticsExportContractTests
```

A new field that can hold text is added to both tests' snapshots, to that classification and to
the table above.

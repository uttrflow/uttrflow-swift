# Mutation probe for the meaning guard

## False refusals over the corpus

Every case's expected text is a correct rewrite of its own spoken draft, so the guard must
accept it. `MeaningGuardRefusalRateTests` runs each through the guard, against the cleaned
draft and under the case's own formatter, and prints the count and every refusal. A refusal
fails the test unless it is in `acknowledged` with the issue that owns it, and an
acknowledged case the guard now accepts fails it too, so the list only falls.

```bash
swift test --filter MeaningGuardRefusalRateTests
```

Every failure of `MeaningPreservationGuard` is an acceptance, and an acceptance leaves no
trace. Line coverage says which checks ran; it does not say whether any test would fail if
a check were wrong. `Scripts/mutation_probe.py` answers the second question.

## What the probe does

It cuts a throwaway detached worktree from a revision (`--ref`, default `HEAD`), proves the
unmutated tree builds and passes the selected tests, then applies one mutation at a time to
the named file, rebuilds, and runs `swift test --skip-build --filter <filter>`:

| Operator | Mutation |
|---|---|
| comparison | a spaced `<`, `<=`, `>`, `>=`, `==`, `!=` becomes its opposite |
| logical | `&&` and `\|\|` swap |
| literal | a numeric literal moves up and down by one, never below zero |
| rejection | a one-line `return .rejected(...)` becomes `return .accepted` |

Each mutant is `killed` (a test failed), `survived` (every test passed) or `unviable`
(it does not compile). The score is killed over killed plus survived. Text inside string
literals and comments is never mutated, and a rejection spread over several lines is not
applied, because it cannot be replaced on one line.

The probe refuses to run from the main checkout, and removes its worktree when it ends.
It is not part of `make verify`: one mutant costs an incremental build and a module test
run, so a whole file takes hours. `make mutation-probe-test` checks the probe itself.

```bash
python3 Scripts/mutation_probe.py Sources/UttrflowAI/MeaningPreservationGuard.swift --list
python3 Scripts/mutation_probe.py Sources/UttrflowAI/MeaningPreservationGuard.swift \
    --filter UttrflowAITests --report "$TMPDIR/guard-mutants.json"
python3 Scripts/mutation_probe.py ... --update-baseline   # record the floor; it refuses to lower one
```

The first `--update-baseline` writes the score per file to `mutation_baseline.json` under
`Scripts/`. A later run that scores below that floor exits 1.

## The guard

`MeaningPreservationGuard.swift` yields 547 applicable mutants: 155 comparison, 278
literal, 79 logical and 35 rejection (`--list`, Apple M5 Pro, 48 GB).

**Survivor list: not yet measured.** The probe's first step, building the unmutated test
bundle, fails on `main` because test targets outside `UttrflowAITests` do not compile
(`swift build --build-tests`, exit 1; errors in `UttrflowPipelineTests`,
`UttrflowAccountTests` and `UttrflowCoreTests`). SwiftPM links every test target into one
bundle, so the guard's tests cannot run until the whole bundle compiles. Once it does, the
run above produces the survivor list; each survivor then gets a test that kills it or a
line here saying why the mutation is equivalent, and the score is recorded as the floor.

The override gate is added to this page when it exists.

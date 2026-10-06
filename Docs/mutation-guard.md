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

## One Muter run over the guards

Muter 16, installed with Homebrew outside the repository, was run once over four guards. It is
not a dependency and not part of `make verify`. Operators: relational replacement, logical
connector and side-effect removal; ternary swapping was left out because Muter writes
`hasPrefix("sig")? a : b` with no space, which parses as optional chaining and fails to build.

Muter needs a test set that passes before mutation, so each run filtered to the suites that
test the file and skipped the test functions already failing on `main`. A survivor counts only
against those suites. Times are wall clock on an Apple M5 Pro, 48 GB, with one relink and test
run per mutant.

| File | Test set | Killed / mutants | Score | Time |
|---|---|---|---|---|
| `Sources/UttrflowCore/Secrets/SecretShapes.swift` | `SecretDetectionTests`, `VendorKeyBoundaryTests`, `CardNumberDetectionTests`, `CommandCredentialTests`, `SecretShapesOracleTests` | 43 / 90 | 47% | 74 min |
| `Sources/UttrflowAI/MeaningPreservationGuard.swift` | `MeaningPreservationGuard*`, `GuardHomophoneRepairTests`, `GuardMirrorTests`, `GuardNumberWordsTests`, `MeaningGuardCorpusTests` | 12 / 30 | 40% | 53 min |
| `Sources/UttrflowPredict/DestructiveCommand.swift` | `DestructiveCommandTests`, `TerminalLineCheckTests`, `TerminalPathGateTests` | 108 / 191 | 56% | 66 min |
| `Sources/UttrflowInput/PasteConfirmation.swift`, `Sources/UttrflowInput/Pasteboard.swift` | not measured | - | - | - |

The paste guards were not measured. Muter wraps each mutated function body in a branch, and
in `PasteConfirmation.waitFor` that stops Swift opening the `any Clock<Duration>` existential,
so the mutated copy does not compile; in `Pasteboard.swift` Muter finds no mutable code. The
meaning guard's em dashes were replaced in the copy Muter mutated, because Muter places
mutants by byte offset and multibyte characters shift them into the wrong place.

**SecretShapes.** `SecretShapesSurvivorTests` kills the survivors that let a credential through:
a generated token as a URL's username, the hexadecimal and randomness rules, the low-entropy
username a loosened `&&` would mask, and a non-hexadecimal token cut into UUID group lengths.
Each was checked by flipping that comparison by hand and watching the suite fail. Equivalent:
`makeContiguousUTF8()` removed (speed only); the `opens(...)` path and URI exemptions in the
byte rule, because `isEntropyExemption` repeats them before a token is called generated; the
`hooks.slack.com` literal check, most likely because a scheme-less webhook the rule masks is
also one high-entropy word (argued, not proved). Still open: the `data:` URI exemption parsing, `isWordLike`,
`isQuotedPath` and the byte `hasKnownURIScheme` bound.

**Meaning guard.** Eleven of its tests fail on `main`, so the run skipped them, and most
survivors are in the checks those tests own: spoken punctuation, the confident-homophone
check, the removal verdict's negation count and the function-word churn count. The survivor
list is re-run once those tests pass.

**DestructiveCommand.** The survivors sit in the `/dev/` substring checks, `cp` flag parsing,
`aws s3`, `gh api` DELETE, `find -exec`, and git push and branch flags. Several are beside
cases the suite already lists, so a second rule likely decides the same line.

# Mutation probe for the meaning guard

## False refusals over the corpus

Every case's expected text is a correct rewrite of its own spoken draft, so the guard must
accept it. `MeaningGuardRefusalRateTests` runs each through the guard, against the draft and
the doubtful runs' readings the engine hands the model, under the case's own formatter, and
prints the count and every refusal. A refusal
fails the test unless it is in `acknowledged` with the issue that owns it, and an
acknowledged case the guard now accepts fails it too, so the list only falls.

```bash
swift test --filter MeaningGuardRefusalRateTests
```

## False accepts over a model-error set

The mirror question is how many wrong rewrites the guard lets through. `ModelErrorClass`
(`Sources/UttrflowEval/ModelErrors.swift`) turns every expected text the guard accepts into
wrong ones, one class of model error each: a dropped content word, an added negation, two
swapped words, a changed number, an appended clause, an answer in place of the tidy-up, a
translation, a label wrapped round the text, and a word moved across a sentence. Each should
be refused. `MeaningGuardFalseAcceptTests` judges `perClass` mutations of each class, spread
evenly over the corpus, prints how many of each class the guard accepts,
names every one, and fails when a class's count differs from its `baseline`, so a fix lowers
the baseline in the same change and a regression cannot raise it. `make bakeoff` prints the
same counts beside the false refusals.

```bash
swift test --filter MeaningGuardFalseAcceptTests
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

`MeaningPreservationGuard.swift` holds the guard's entry point and the checks that live beside
it; the other checks are extensions in `Guard*.swift`, `RomanisedWords.swift` and
`ScriptGuard.swift`, which are not yet probed. The file yields 91 mutants, 88 of them
applicable on one line: 58 killed, 12 survived and 18 unviable, a score of 0.829
(Apple M5 Pro, 48 GB). The run's test set was the 39 `UttrflowAITests` suites whose files
call the guard or its helpers, named in the `--filter` regex
`UttrflowAITests\.(<suite>|<suite>|...)/`. Three tests failing on `main` at the time were left
out with a negative lookahead after the slash. The unviable mutants were the literal operator
reading a closure's `$0` as a number; the probe now leaves `$0` alone, so the file lists 70
mutants.

Every survivor now has a test in `MeaningPreservationGuardSurvivorTests` that fails with it
applied. Each was checked by applying the mutant by hand and running that suite:

| Survivor | What no test pinned | Killing test |
|---|---|---|
| `maximumGrowthFactor` 2.0 to 3.0 | the growth limit's exact boundary | `growthLimitIsExact` |
| `shortUtteranceWords` 3 to 2 and to 4 | where the retention floor starts | `retentionFloorStartsAfterThreeWords` |
| `inheritedMarks` `$0 == mark` to `!=` | a hyphenated word answering for a spoken comma | `inheritedMarksCountOnlyTheirOwnMark` |
| `restored` `isPlain &&` to `\|\|` | a removed function word asked back | `restoredKeepsContentAndNegationsOnly` |
| `closedUpEdges` `ends = [0]` to `[1]` | a one-letter reading inside a longer word | `oneLetterReadingIsAWholeWord` |
| `wordsPerSentenceEnd` 40 to 39 and to 41; the round-up `- 1` to `- 0` and `- 2` | the churn allowance per unpunctuated forty words | `churnSentencesRoundUpPerFortyWords` |
| `wordsPerLine` `append(0)` to `append(1)`; `+= 1` to `+= 2` | the per-line word count | `wordsPerLineCountsEachWordOnce` |

No survivor is argued equivalent. The score floor is not yet recorded: a full re-run with
`--update-baseline` writes it.

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
`SecretShapesMutationTests` adds boundary assertions for invalid `data:` URI MIME components
and parameters, mismatched quotes in `src=` and CSS `url(...)`, an overlong numeric suffix, and
quoted paths and their trimming bounds. Each named survivor was checked by flipping its
comparison by hand and watching the focused suite fail. Equivalent: `makeContiguousUTF8()`
removed (speed only); the `opens(...)` path and URI exemptions in the byte rule, including its
prefix-length guard, because `isEntropyExemption` repeats them before a token is called generated;
the byte `hasKnownURIScheme` bound, because the later string-based exemption preserves the mask
decision (the byte check only avoids calculating entropy for known schemes); the
`hooks.slack.com` literal check, most likely because a scheme-less webhook the rule masks is also
one high-entropy word (argued, not proved).

**Meaning guard.** The run skipped the guard's tests that were failing, and most survivors
were in the checks those tests own: spoken punctuation, the confident-homophone check, the
removal verdict's negation count and the function-word churn count. Muter is not re-run for
them: its line numbers no longer match the file, so each survivor is re-derived against the
current guard and flipped by hand against `UttrflowAITests`. The confident-homophone check
no longer reads a kept word's score by its place in a filtered word list; it finds the word
that wrote each kept token through the shared word alignment (`WordErrorRate.matchedColumns`),
so a word a pass inserted, a layout mark or a removed word cannot move a score onto its
neighbour. `MeaningPreservationGuardTests` pins this with a word `SpacingPass` splits.

**DestructiveCommand.** The survivors sit in the `/dev/` substring checks, `cp` flag parsing,
`aws s3`, `gh api` DELETE, `find -exec`, and git push and branch flags. Several are beside
cases the suite already lists, so a second rule likely decides the same line.

For `dd if=disk.img of=/dev/nvme0n1`, removing the `/dev/` fast path does not change the result:
`dd` is itself in `DestructiveCommand.destroyers`, and `destroys` returns true before considering
its arguments. The reciprocal removal of `dd` from `destroyers` also leaves the case matched by
the `/dev/` fast path, so those rules overlap on that direct invocation. The same is true of
`busybox dd if=disk.img of=/dev/nvme0n1`: the unknown-carrier fallback sees `dd` among its
arguments and classifies the command before testing the destination. Neither case isolates
`of=/dev/`. Separate `cp disk.img` cases targeting `/dev/sdb`, `/dev/disk4` and `/dev/rdisk4`
do isolate the three device-path alternatives: the `cp` fallback does not treat these block-device
destinations as destructive on its own.

# Format adapters: one registry that grows out of the destination formatter

How cleaning learns the grammar of what is being written (a SQL statement, a shell command
line, a source line, a formula, a JSON fragment) without a second registry beside
`DestinationFormatter` and without another `if destination ==` branch in the pipeline. This
page fixes the interface, the one table, where each stage runs, the boundary an adapter may
not cross, and how today's technical special cases are absorbed. Every adapter issue in the
dictation-quality programme (the `AD.` series) implements one section of it and cites that
section. The low-level design it extends is [cleanup-design.md](cleanup-design.md); the
promise it serves is [cleanup.md](cleanup.md): an accurate transcript, never a rewrite.

**Status: proposed design.** `FormatAdapter`, `AdapterRegistry`, and the other adapter types
described below are not implemented yet, except `Applicability` and its `AdapterCue` values
(`Sources/UttrflowCore/Adapters/Applicability.swift`) and the one evidence rule for spoken code
symbols, `NotationEvidence` (`Sources/UttrflowAI/NotationEvidence.swift`). SQL notation is rows of
`spoken-commands.json` enabled in `sqlEditor` (operators as `codeSymbol` rows, keywords as
`keyword` rows), written by `CodeEditorCommandsPass` only when the speech opens a statement outside
a comment or string; `SQLNotationTests` holds its corpus cases to their exact statement. The “Today” columns and
references to existing source files describe current behavior; the “With the adapter” columns
describe the planned design.

## 0. Why the current seam cannot carry this

`Destination` (eight cases, `Sources/UttrflowCore/Models/Destination.swift`) answers which
kind of app is in front. Each case maps to one `DestinationFormatter` value of seven
decisions (first word, terminal stop, layout, grammar, numbers, digit grouping, prompt
block) in `Sources/UttrflowCore/Models/DestinationFormatter.swift`. That is the right shape
for prose-level decisions, and it stays.

It has no place for a decision that needs the grammar of the text being written. So those
decisions became passes switched on by tests of the destination:

| Where | What is keyed to the destination |
|---|---|
| `Sources/UttrflowAI/Passes/CleaningPipeline+Standard.swift` | `CodeEditorCommandsPass` inserted when `NotationEvidence` reads a command line or a code caret, and run only while the speech holds no prose word |
| the same file, `terminalStop(_:in:)` | a code editor's stop policy swapped to `.always` inside a comment |
| the same file and `Sources/UttrflowPipeline/DictationPipeline.swift` | `capitaliseCalendarWords` is enabled only for `.fromInsertionPoint` destinations other than `.codeEditor`; the condition is written twice |
| `Sources/UttrflowAI/Passes/SpokenPunctuationPass.swift` | the `flag` rows of `spoken-commands.json` (enabled in terminal, code, SQL) plus the lexicon's `command` terms decide literal hyphens and flags; a comment or prose body, which `NotationEvidence` rules out, reads every dash as prose |
| `Sources/UttrflowAI/Passes/TerminalStopPass.swift` | an email greeting or sign-off keeps its own stop rule |
| `Sources/UttrflowAI/PromptBlocks.swift` | the `sqlEditor` block says prose stays prose, includes additional SQL guidance, and has no examples |

Each new family (SQL, shell, JSON, formula) would add another branch of this kind, or a
parallel system. The root cause is that the seam is a table of decisions keyed by **app
kind**, where the decisions that matter here are keyed by **what the person is writing**.

## 1. The interface: `FormatAdapter`

An adapter is the finer answer to "where are the words going"; `Destination` stays the
coarse one. One protocol, at most five requirements (the limit in
[agents/code-quality.md](agents/code-quality.md)), with everything that is a fact rather than
behaviour held as data in a descriptor:

```swift
/// What one kind of writing wants done to dictated words; data in the descriptor, behaviour in three calls.
public protocol FormatAdapter: Sendable {
    var descriptor: AdapterDescriptor { get }
    func applies(to situation: Situation) -> Applicability
    func passes(for situation: Situation) -> [any CleaningPass]
    func validate(_ output: String, in situation: Situation) -> AdapterVerdict
}

/// The facts an adapter declares, read by the registry, the pipeline, the prompt and the safety contract.
public struct AdapterDescriptor: Sendable, Equatable {
    public let id: AdapterID              // "prose.document", "sql", "shell", "source.swift", "json"
    public let family: AdapterFamily      // .prose, .sql, .shell, .source, .json, .config, .formula, ...
    public let policy: DestinationFormatter  // today's seven decisions, the adapter's prose-level policy
    public let consequence: Consequence   // what the destination does with the text (section 7)
    public let budget: LatencyBudget      // the declared cost of passes plus validate (section 8)
}
```

What each part carries:

| Concern | Carried by | Notes |
|---|---|---|
| Identity and family | `descriptor.id`, `descriptor.family` | the id is what history, diagnostics and the override store record |
| Prose-level policy | `descriptor.policy` | the existing `DestinationFormatter` value, unchanged in type |
| Prompt block | `descriptor.policy.promptBlock` | already on the formatter; an adapter's rules and examples are generated from its notation rows (AD.7) |
| Selection evidence and abstention | `applies(to:)` returning `Applicability` | section 2 |
| Notation | the `NotationTable` rows of `descriptor.family`; the prose family has none | data, never a literal table in a pass (AD.7) |
| Layout and indentation | the adapter's passes, reading the caret's own whitespace from `CaretStructure` | never a constant indent (AD.23) |
| Quoting | one `Quoting` module shared by SQL, shell, JSON and source strings | no adapter writes its own escaper (AD.19) |
| Number style | `descriptor.policy.numbers` and `.digits` | the locale seam extends `DestinationFormatter`, not the adapter |
| Output validation | `validate(_:in:)` returning `AdapterVerdict` | section 5 |
| Latency | `descriptor.budget` | section 8 |

`AdapterVerdict` is named so because `Verdict` is already a public type in `UttrflowPredict`.
`Applicability` is never a bare number: missing evidence is its own value, never defaulted to
the strongest one.

```swift
/// Whether an adapter fits a situation, and on what evidence; abstaining is the ordinary answer.
public enum Applicability: Sendable, Equatable {
    case noEvidence                                          // the screen said nothing either way
    case ruledOut(by: AdapterCue)                            // a cue says this is not the family
    case evidenced(confidence: Double, by: [AdapterCue])     // the cues that produced the confidence
}
```

## 2. The registry: `AdapterRegistry`, the one table

There is one table. `DestinationFormatter.registry` does not get a sibling: its eight values
**become the registry's prose entries**, one prose adapter per destination, and every notation
adapter names the prose adapter it degrades to. A policy is therefore written once, in
`DestinationFormatter.swift`, and an adapter that needs a different stop or layout states the
difference as data in its registry row rather than as a guard in a pass.

```swift
/// Every adapter this build has, and the one rule that picks among them.
public enum AdapterRegistry {
    static let adapters: [any FormatAdapter]               // prose entries first, built from DestinationFormatter.registry
    static func select(for situation: Situation, overrides: DestinationOverrides) -> AdapterSelection
}

public struct AdapterSelection: Sendable {
    public let adapter: any FormatAdapter
    public let applicability: Applicability                // kept for diagnostics and history (AD.37)
    public let fallback: any FormatAdapter                 // the prose adapter for situation.destination
}
```

`select(for:)` is the only place that turns evidence into a choice, in this order:

1. **The user's override** for this app (section 6): `prose` returns the prose adapter,
   `forced(id)` returns that adapter, `auto` continues.
2. **The writing intent** on the situation (language, field role, region; AD.2) narrows the
   candidates to the families it allows. With no intent, the destination's families are the
   candidates; an unknown language is `nil`, never a guess.
3. **Each candidate's `applies(to:)`.** The highest `.evidenced` confidence at or above the
   registry's single activation threshold wins. Its value is a named constant,
   `NotationEvidence.activationThreshold`, and nowhere else. It is 1: a command line, a caret
   in code or a statement opened in a query editor reaches it, a cue against (a comment, a prose body, an article in the speech) rules
   the notation out, and no speech cue alone reaches it. Measured under the rules: 0 misfires on
   the abstention corpus, and the code-symbol cases `NotationRecallTests` counts are written
   exactly 3 of 3 in a code editor and 1 of 2 at a command line, which are its floors.
4. **Otherwise the prose adapter for `situation.destination`**, which is today's behaviour
   exactly. Abstention is the default; a weak signal degrades to prose, never to a different
   notation adapter.

The classifier stays the only place that turns an app into a `Destination`
(`Sources/UttrflowCore/Models/DestinationClassifier.swift`); the registry never reads a
bundle identifier.

**What selection may read.** The choice reads the caret situation and the utterance, nothing
else. The persona, the evidence ledger, the dictionary, dictation history and settings bias
words (the decode prompt, the candidates, the override gate); they never select a formatter
or an adapter, so a month of SQL dictations does not turn a prose sentence in an empty editor
into SQL. Each layer reads:

| Layer | May read | Never reads |
|---|---|---|
| Selection (`DestinationFormatter.standard(for:)` today, `AdapterRegistry.select` later) | `Situation`, the utterance | persona, ledger, dictionary, history, `UserProfile` |
| Prompt | the destination's block, at most `PromptBuilder.caretLimit` characters before the caret, the previous piece of this dictation | any summary or list of earlier dictations |
| Vocabulary and candidates | the persona and dictionary, through `WorkingSet` | |

`AdapterChoiceInputsTests` holds it: one utterance at one caret under an empty, a SQL-heavy
and a prose-only persona, each with fifty dictations of ledger, gets the same formatter,
output and prompt; `Situation` carries no field beyond what the screen said and the number
style; and no file that chooses names a learned type. `UttrflowCore`, where the choice lives,
may import no other module (`make layering-audit`). The registry, which will sit in
`UttrflowAI` beside `UttrflowDictionary`, keeps the same inputs: `applies(to:)` takes the
situation, and the utterance where it needs one, and nothing else.

**Region selects a prose adapter.** A caret inside a comment, a string or fenced prose is
prose. The registry holds that as a prose row whose policy is its destination's with the
stop `.always`, which is what the code editor does inside a comment today. The guard in
`terminalStop(_:in:)` and the comment check before `CodeEditorCommandsPass` are then deleted,
not kept beside it.

## 3. Where each stage runs in `CleaningPipeline.standard`

The pipeline's order does not change shape. The adapter contributes at three fixed points
and adds no stage of its own:

| Stage | Today | With the adapter |
|---|---|---|
| Selection | `DestinationFormatter.standard(for: situation)` | `AdapterRegistry.select(for:)`, once per dictation, beside the situation read |
| Piece passes | fillers, repeats, stammers, self-correction, spoken punctuation, layout words, numbers, contractions, spacing | the same list, with the adapter's `passes(for:)` in one **notation slot** directly after `SelfCorrectionPass` |
| Model | one call, prompt from the formatter's block | one call, prompt from `descriptor.policy.promptBlock`; **no adapter makes a second model call or a second round trip** ([cleanup-design.md](cleanup-design.md), section 8) |
| Guard | `MeaningPreservationGuard` | the same guard, which accepts a difference only when it is a `NotationTable` row (section 4) |
| Validation | none | `validate(_:in:)` on the guarded output, then the registry's safety contract (section 7) |
| Message passes | spelled initialisms, first word and terminal stop from the formatter | the same passes, reading `descriptor.policy` |

The notation slot sits after self-correction so a retracted span is never converted, and
before spoken punctuation so prose punctuation sees only what notation did not claim. A
spoken name that is both an everyday word and a mark ("comma", "colon", "period") has one
home: the prose punctuation table, with its mention guard. A notation row for it is marked
ambiguous and is converted only on positive evidence (AD.7).

The prose rows return exactly the passes their destination runs today; the code editor's
keeps `CodeEditorCommandsPass` outside comments until the source adapter absorbs it
(section 9). So the pull request that lands the protocol and the prose rows changes no
output, and its check is the bake-off on every existing case, unchanged. Moving
`CodeEditorCommandsPass` from its current place, just before `LayoutWordsPass`, into the
notation slot is measured by the bake-off in the pull request that does it.

## 4. The boundary: notation, never rewriting

**An adapter converts notation and never adds words.** The output must be derivable from the
input by:

1. replacing a spoken span with the written form its `NotationTable` row lists for that span;
2. deleting nothing the speaker meant (fillers, stammers and retractions are the prose passes'
   work, under their `RemovalGrant`);
3. adding no token without a spoken source, other than the layout and spacing its policy
   allows.

A clause, keyword, column, `LIMIT`, semicolon, quote or bracket with no spoken source is a
violation, however helpful. So is reordering, completing a statement, or choosing an
identifier the screen does not show. This is AD.6, and it is what keeps every adapter
inside the promise in `AGENTS.md`, "What dictation is for".

**How the guard checks it today.** Until `NotationTable` exists, the notation rows are the
`mark`, `codeSymbol` and `flag` rows of `spoken-commands.json`, plus the guard's own
`symbolNames`. `NotationAlignment` (`Sources/UttrflowAI/NotationAlignment.swift`) reads both
texts as words and marks, reads each run of words a row names as that row's mark, and aligns
the two in order with `WordErrorRate.measure`. Names and marks are joined into classes
through the rows, so "dot", "period" and `.` are one token. The guard uses it three ways:

| Check | What it refuses or excuses |
|---|---|
| `notation` symbol row | a mark only a code or flag row writes (`=`, `\|`, `>`, `->`, `{`, `}`, `_`, `--`) that no spoken name or draft mark stands behind, as `inventedSymbol` |
| `notationDropped` symbol row | such a mark the draft held and the rewrite left out, as `lostWord` |
| survival and length | a name written as its mark is not a lost word: "open paren" as `(`, "greater than" as `>`, "dash dash" as `--` |

A prose mark (a stop, a comma, a hyphen, a bracket) is never counted as added or dropped
here; the prose checks judge it. It stands for its name only when it is written against
the words its side asks for, from the row's `placement` (`example.com`, `foo(bar)`), since a
stop spaced as prose may be the rewrite's own. Words are not judged here: an invented
keyword or clause is the invention, order and survival checks' to refuse.
`NotationAlignmentTests` holds every notation row written as its mark to zero unsourced
marks, and refuses an inserted clause, a dropped word and swapped clauses.

## 5. Validation and the fallback ladder

`validate(_:in:)` judges only the part the dictation added, in the context of the caret text,
so a half-finished clause is valid input. It returns `wellFormed`, `notApplicable` or
`malformed(reason)`. A malformed result falls back to the rules output, then to the untidied
text, through `TransformerRouter`; no validator blocks insertion by itself. The tokenisers
(bracket and quote balance for every code family, a SQL tokeniser, a JSON tokeniser, a shell
quoting scan) live in one `AdapterValidator` and are shared by family. This is AD.8.

## 6. Overrides: one store, migrated

There is no second store. `DestinationOverrides`
(`Sources/UttrflowCore/Models/DestinationOverrides.swift`) gains a mode per app, `auto`,
`prose` or `forced(AdapterID)`, decoded with `auto` for entries written before it, and keeps
`destination` (AD.36.a). A one-shot "as typed" control applies to the next dictation only and
is never persisted (AD.36.c).

## 7. Consequence: what the destination does with the text

Each registry row declares a `Consequence`, as data, not as a second table:

| Consequence | Meaning | Prose rows today |
|---|---|---|
| `stores` | the text sits in a field until the person acts | document, spreadsheet, sqlEditor, codeEditor, email, plain |
| `sends` | a typed Return can send it | messaging (per app, from the probe in AD.18) |
| `executes` | a typed Return can run it | terminal |
| `navigates` | a typed Return can open it | address and search fields (AD.30) |

The value lives on `DestinationFormatter` (`consequence`, typed by `Consequence` in
`Sources/UttrflowCore/Adapters/Consequence.swift`); a search field's row is `navigates`.
Capture's `CommitPolicy` reads it to decide where Return finishes a field, in place of its
own terminal and messaging test. An `executes` row never lays out paragraphs or lists, so
the only line break that reaches it is one the speaker asked for.

It is the single input to three later decisions, so none of them keeps its own list of apps:

- **the newline rule**: no unspoken line feed, control character or execution trigger reaches
  a `sends` or `executes` destination; the safety contract checks the final output once, in
  the registry, not in each adapter (AD.17);
- **the override margin and the flag budget**, scaled by consequence; the multipliers are set
  by measurement in the issue that owns them, and until then every consequence scales by one,
  which is today's behaviour;
- **whether a review aid shows by default** (AD.37); until that is decided, none does.

## 8. Latency

An adapter's passes and its validator are pure, deterministic and local, in the same class as
the passes in [cleanup-design.md](cleanup-design.md), section 8. Each adapter declares its
`LatencyBudget` as a named constant on its descriptor, and the per-layer budget check owned by
the latency-budget issue (3.10) measures it. Selection runs once per dictation beside the
situation read, never per piece.

## 9. What is absorbed, and what is deleted with it

One path per capability: each item below moves into the adapter structure and the original is
deleted in the same pull request.

| Today | Becomes | Deleted with it |
|---|---|---|
| `CodeEditorCommandsPass`, its symbol table and its casing commands | the source adapter's notation pass reading `NotationTable` rows (AD.20.a, AD.21) | the pass's literal tables, and its copies of "comma", "colon" and "semicolon" that prose punctuation already owns |
| `SpokenPunctuationPass`'s technical branch: the `flag` rows' destinations, the lexicon's command terms, long and short flags, literal hyphens | shell rows in `NotationTable`, and shell cues returned by the shell adapter's `applies(to:)` (AD.16, AD.3) | the `destination` parameter of `SpokenPunctuationPass` |
| `CaretStructure.region` read in `terminalStop(_:in:)` | the region selecting a prose row (section 2) | `terminalStop(_:in:)` in `CleaningPipeline+Standard.swift` |
| `capitaliseCalendarWords` withheld for code, in two files | a decision on the policy | both `!= .codeEditor` tests |
| the email greeting rule in `TerminalStopPass` | a `TerminalStopPolicy` value on the email prose row | the `destination == .email` tests |

After these, no pass reads `Destination`. A pass that needs to know where the words are going
reads its adapter's policy or notation rows.

## 10. One file and one type for each part

| Part | Type | Module and directory | File |
|---|---|---|---|
| Adapter interface | `FormatAdapter` (and `AdapterDescriptor`, `Applicability`, `Consequence`, each in its own file beside it) | `UttrflowCore`, `Sources/UttrflowCore/Adapters/` | `FormatAdapter.swift` |
| Registry | `AdapterRegistry` | `UttrflowAI`, `Sources/UttrflowAI/Adapters/` (it builds passes, which live there) | `AdapterRegistry.swift` |
| Notation table | `NotationTable` | `UttrflowCore`, `Sources/UttrflowCore/Adapters/` | `NotationTable.swift` |
| Region classifier | `CaretStructure` | `UttrflowCore`, `Sources/UttrflowCore/Models/` | `CaretStructure.swift` |
| Validator | `AdapterValidator`, returning `AdapterVerdict` | `UttrflowAI`, `Sources/UttrflowAI/Adapters/` | `AdapterValidator.swift` |
| Override store | `DestinationOverrides`, migrated in place | `UttrflowCore`, `Sources/UttrflowCore/Models/` | `DestinationOverrides.swift` |

## 11. Which issue implements which section

| Section | Issues |
|---|---|
| 1, 2: interface, registry, prose rows | AD.1 (this page); the first adapter pull request lands the protocol and the prose rows with no behaviour change |
| 1, 2: intent and selection | AD.2 (intent on `Situation`), AD.3 (evidence and abstention), AD.4 (one code-language detector), AD.5 (field label and role), AD.31 (a language prompt inside a terminal) |
| 1: notation | AD.7 (`NotationTable`), AD.19 (`Quoting`), AD.23 (indentation from the caret) |
| 3: pipeline placement | AD.40 (notation across the early-transcription seam) |
| 4: boundary | AD.6 |
| 5: validation | AD.8 |
| 6: overrides | AD.36.a, AD.36.b, AD.36.c |
| 7: consequence | AD.17 (safety contract), AD.18 (does a paragraph break send), AD.37 (which adapter formatted a dictation) |
| 8: latency | 3.10 |
| 9: absorption | AD.16 (shell), AD.20.a and AD.20.b (source), AD.21 (naming), CX.15.b (`CaretStructure`) |
| Families | AD.9 to AD.15 (SQL), AD.22 (editor newline probe), AD.24 (JSON), AD.25 (config), AD.26 (Markdown), AD.27 (commit message), AD.28 and AD.29 (spreadsheet), AD.30 (address and search), AD.32 (email header fields), AD.33 to AD.35 (decisions on mathematics, regex, markup) |
| Measurement | AD.38.a and AD.38.b (per-adapter cases and metrics), AD.39 (zero false activation on prose in technical apps) |
| User-facing description | AD.41 |

A family gets an adapter only when it has corpus cases and a measured demand; until then its
destination keeps its prose row, and nothing is built for it.

## 12. Decided: spoken mathematics gets no adapter

Spoken mathematics is prose. Arithmetic inside a sentence is the numbers pass's work (2.28);
there is no `formula` notation adapter and no LaTeX adapter, active in `.tex` documents or
anywhere else. Nothing is built for it.

Measured on this tree, not on users' dictations:

| Question | Measurement | Result |
|---|---|---|
| Demand in the evaluation corpus | spoken strings in `Sources/UttrflowEval/*Corpus*.swift` (886) matched against powers, roots, fractions, Greek letter names, sums, integrals, derivatives, `frac`, `backslash`, and the words plus, minus, times, divided by and equals | 0 dictate mathematics; the 5 matches are a SQL join, a regex, a phone number and two code assignments |
| Demand in the scored cases | `Tests/UttrflowEvalTests/Golden/rules.golden` (654 cases) | 0 mathematical cases |
| Bounded subset reaching exact match | needs cases to score | not measurable: 0 cases exist, and building them first would be building demand |
| Destination distinguishable | `FocusedFieldReader+Snapshot.swift` reads `AXDocument` | a `.tex` file is identifiable where the editor exposes its document URL; not probed in real editors |

**Why (a).** A family gets an adapter only on corpus cases and measured demand (section 11);
mathematics has neither. A LaTeX grammar is a second, large notation table whose output
(`\frac`, `^`, braces) is mostly tokens with no spoken source, which section 4 forbids unless
each is a `NotationTable` row; and a plain-math adapter would duplicate 2.28's arithmetic.

**Deleted.** Option (b), a LaTeX adapter for `.tex` documents, is not built and has no
follow-up issue.

**What reopens it.** Mathematical dictations appearing in the evaluation corpus as real
cases, enough to score a bounded subset against exact match with section 4 holding.

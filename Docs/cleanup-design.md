# Clean-up: the low-level design

How dictated words become the text the speaker would have typed, in the place they are
typing it. Four small, separately testable ideas carry it, so that a new cleaning is a new
value in a table or a new pass in a list, never a new branch in the pipeline. The types live
in `Sources/UttrflowCore/Models/` (`Situation`, `InsertionPoint`, `Destination`,
`DestinationRules`, `DestinationClassifier`, `DestinationFormatter`) and
`Sources/UttrflowCore/Cleaning/` (`Draft`, `CleaningPass`, `PassID`, `Restatement`); the
passes are in `Sources/UttrflowAI/Passes/`, the prompt in `Sources/UttrflowAI/PromptBuilder.swift`,
the candidate sources in `Sources/UttrflowAI/Candidates/`, and the join in
`Sources/UttrflowPipeline/PieceJoiner.swift`. What each cleaning does, case by case, is
`Docs/cleanup.md`.

The goal it serves is fixed (`Docs/agents/product.md`, "Dictation and clean-up"): **an accurate
transcript, cleaned of the noise of speaking and laid out as the speaker would have
typed it. Never a rewrite.**

## The shape in one picture

```
 audio piece ──▶ recognise ──▶ Draft(words, confidence)
                                     │
   screen ──▶ Situation ─────────────┤   (read once per dictation, ≤100 ms, in parallel)
   (app, field, text before caret)   │
                                     ▼
                  DestinationFormatter(for: situation)
                                     │
            ┌────────────────────────┼─────────────────────────┐
            ▼                        ▼                         ▼
   deterministic passes     doubtful-word candidates      prompt = contract
   (fillers, stammers,      (dictionary, screen,            + formatter block
    self-corrections,        ordinary words,                + situation block
    spoken punctuation,      homophones)                    + doubtful words
    layout words, numbers)
            └────────────────────────┴──────────────┬──────────┘
                                                    ▼
                                      one language-model call
                                      (the only slow step,
                                       hidden by working ahead)
                                                    │
                                                    ▼
                               MeaningPreservationGuard(draft, output, layout)
                                    accepts only what the passes and the
                                    candidates allowed; else the rules
                                                    │
                                pieces joined ──▶ join-level layout ──▶ message passes ──▶ insert
                                (lists, paragraphs, restatements)   (first word, final stop)
```

Four ideas, each one type: **Situation** (where the words are going), **DestinationFormatter**
(what that place wants), **CleaningPass** (one deterministic cleaning), **Draft** (the words
with a record of what was done to them). The language model is the last formatter, and
the guard holds it to the record.

## 1. Situation — where the words are going

```swift
/// What the screen said at the moment the key went down, read once and handed to every stage.
public struct Situation: Sendable, Equatable {
    public let app: AppContext            // name, bundle id, window title, selection, field role
    public let insertion: InsertionPoint
    public let destination: Destination
}

/// What sits at the caret, so the first word can match what came before it.
public struct InsertionPoint: Sendable, Equatable, Codable {
    public let precedingText: String?     // up to precedingLimit (300) before the caret; nil when the field will not say
    public let followingText: String?     // up to followingLimit (100) after
    public var sentenceState: SentenceState { … }   // derived, never read from the field

    public enum SentenceState { case startOfText, startOfSentence, midSentence, unknown }
}

/// The kind of place, which decides the formatter.
public enum Destination: String, Sendable, Equatable, CaseIterable, Codable {
    case document, spreadsheet, sqlEditor, codeEditor, terminal, messaging, email, plain
}
```

**Where it comes from.** `MacContextEngine` reads the frontmost app, window title, selection
and the focused field's value and selected range within its `budget` (100 ms), and
`SituationResolver` turns that read into a `Situation`. `sentenceState` is derived from the
line the caret is on: empty → `startOfText`; text ending in `. ! ?` or `…` (closing quotes,
brackets and emoji aside, and not on an abbreviation in `sentenceAbbreviations`) →
`startOfSentence`; a list, heading or quote marker alone → the start of a sentence or text;
otherwise `midSentence`; a field that will not report its value → `unknown`, which every
formatter treats as the start of a sentence.

**How the destination is decided.** `DestinationClassifier` reads the user's
`DestinationOverrides` first and then one table, `DestinationRules.standard`:

```swift
public struct DestinationRule: Sendable, Equatable, Codable {
    public let bundlePrefixes: [String]   // matched as case-insensitive prefixes
    public let titleContains: [String]    // whole words of the window title, for apps in a browser tab
    public let nameWords: [String]        // whole words of the application name
    public let kind: AppKind?             // the sort of app, which the "Typed into:" caption names
    public let destination: Destination
    public let terminalStop: TerminalStopPolicy?   // an app's own exception to its destination's stop
}
```

The most specific bundle prefix wins, then the first row whose title fragment matches, then
the first row whose name word matches; no match is `.plain`. The table is one Swift array
literal in one file (`Sources/UttrflowCore/Models/DestinationRules.swift`): data, not logic.
It is not a JSON resource because a resource bundle is a known packaging trap in this
repository (`Docs/packaging.md`); the user changes a destination through an override, never
by editing the table. Adding an app is a row, and the classifier has no `if` on a bundle id
anywhere in code.

The focused field's Accessibility role and multiline capability travel with the situation.
`DestinationFormatter.standard(for: Situation)` reads them: an `AXSearchField`, or any field of
an app whose row says `field: .search` (the launcher panels), keeps the first word's heard casing, takes no terminal stop and turns line breaks into spaces; an
`AXTextField`, or any field Accessibility reports as single-line, also turns line breaks into
spaces. Multiline fields keep the destination's layout.

## 2. DestinationFormatter — what that place wants

One value per destination, in a registry. A formatter does not contain code; it contains
decisions, and every stage reads the decision it needs.

```swift
public struct DestinationFormatter: Sendable, Equatable {
    public let destination: Destination
    public let firstWord: FirstWordPolicy        // .fromInsertionPoint | .alwaysCapital | .asSpoken
    public let terminalStop: TerminalStopPolicy  // .always | .never | .offForShortMessages(sentences:)
    public let layout: LayoutPolicy              // paragraphs, lists, preserveNewlines, singleLine
    public let grammar: GrammarPolicy            // .repair | .asSpoken
    public let numbers: NumberPolicy             // .always | .fromTen
    public let digits: DigitGrouping             // .thousands | .none
    public let promptBlock: PromptBlockID        // the style rules and examples the model is shown
}
```

The eight shipped values (`DestinationFormatter.registry`):

| Destination | First word | Terminal stop | Layout | Grammar | Numbers | Digits |
|---|---|---|---|---|---|---|
| document | from caret | always | paragraphs, lists | repair | numerals ≥10 | 12,000 |
| spreadsheet | as spoken | never | single line | as spoken | always numerals | 12,000 |
| sqlEditor | from caret | always | preserve newlines | as spoken | always numerals | 12000 |
| codeEditor | from caret | never in code, always in a comment | preserve newlines | as spoken | always numerals | 12000 |
| terminal | as spoken | never | single line | as spoken | always numerals | 12000 |
| messaging | from caret | off for ≤2 sentences | paragraphs | as spoken | numerals ≥10 | 12,000 |
| email | from caret | always | paragraphs, lists | repair | numerals ≥10 | 12,000 |
| plain | from caret | always | paragraphs, lists | repair | numerals ≥10 | 12,000 |

Everything a formatter decides is a policy value with two to four cases, so a change is a
value change and a test change, never a new branch. Whether the caret sits in a code comment
is read by `CaretStructure.region`, which is what switches the code editor's stop to `.always`.

A decision that needs the grammar of what is being written (a SQL statement, a shell
command, a formula) is not a destination decision. It belongs to a format adapter, whose
prose-level policy is this formatter and whose registry holds these values as its prose
entries: [adapters.md](adapters.md).

## 3. CleaningPass — one deterministic cleaning

```swift
/// One cleaning that needs no model: a pure function over a draft that records every word it touches.
public protocol CleaningPass: Sendable {
    static var id: PassID { get }
    static var removes: RemovalGrant { get }     // .sound | .repetition | .retraction | .conversion (the default)
    func apply(_ draft: Draft) -> Draft
}
```

A pass is constructed with whatever it reads — a policy, the insertion point, the
destination — so `apply` sees only the draft. The passes, in the order they run:

| Pass | Removes or adds | Signal it needs | Scope |
|---|---|---|---|
| `FillersPass` | um, uh, hmm, aah… | word list | piece |
| `RepeatedPhrasePass` | a 2–4 word run said twice in a row, a restarted incomplete clause | adjacency | piece |
| `StammersPass` | the same function word twice | adjacency | piece |
| `SelfCorrectionPass` | the half before a trigger phrase, a bare-hyphen cut-off | trigger between two candidates of the same shape | piece |
| `SpokenPunctuationPass` | "comma", "full stop", "question mark", "open quote…close quote", a spoken email address → marks | the word stands at a seam, not "put a comma there" | piece |
| `SpokenCasingPass` | casing rows of `spoken-commands.json`: an identifier style in code; "all caps" (next word) and "all caps on … all caps off" (span) in prose | the row's destinations; in prose, not after a determiner, a preposition or a naming verb, nor before a form of "be" | piece |
| `CodeEditorCommandsPass` | spoken symbol commands | a code editor, outside a comment | piece |
| `LayoutWordsPass` | "new line", "new paragraph", "bullet point", "number one" → layout | same | piece |
| `NumberFormsPass` | fifteen → 15, sixteen point two → 16.2, two thirty pm → 2:30 pm | number-word grammar, `NumberPolicy`, `DigitGrouping` | piece |
| `ContractionsPass` | dont → don't | word list | piece |
| `SpelledInitialismPass` | a p i → API | adjacent letter names | piece, and again after the model |
| `SpacingPass` | no space before `, . ? ! : ;`, one after; collapse runs | none | piece |
| `PauseStopPass` | a full stop where the speaker paused a piece boundary's length inside one piece | recogniser word timing, then `SentenceBoundaryEvidence`; prose destinations only | piece |
| `SentenceBoundaryPass` | takes back a stop where the sentence runs on | `SentenceBoundaryEvidence` | message |
| `FirstWordPass` | capitalise, or lower-case after a mid-sentence caret | `sentenceState` + `FirstWordPolicy` | message |
| `TerminalStopPass` | add or withhold the final mark | `TerminalStopPolicy`, `LayoutPolicy` | message |

`SpokenPunctuationPass` runs before `LayoutWordsPass` because a spoken stop must become
punctuation before a following layout phrase can be recognised as a break: "question mark new
line" must become `?` followed by a line break.

Every pass records what it did in the draft, which is what makes the guard able to tell
"the pass removed *no sorry at four*" from "the model dropped half the sentence".

```swift
public struct Draft: Sendable, Equatable {
    public var words: [Word]
    public struct Word: Sendable, Equatable {
        public var text: String           // as it reads now, or a layout mark beginning with a newline
        public let heard: String          // what the recogniser said, never changed
        public let confidence: Double     // from the recogniser, 0…1
        public var state: State           // .kept, .removed(by:), .replaced(by:from:), .inserted(by:)
        public private(set) var edits: [Edit]   // every pass's change, oldest first
    }
}
```

A pass is a pure function over a value; each is tested on its own with the corpus cases
that belong to it, with the model switched off, so a pass that works keeps working when the
model changes.

**Sentence locality.** Every pass that cleans a piece is held to one property by
`SentenceLocalityTests`: a sentence is cleaned the same whether or not another sentence
precedes it. The test is a cross product of prefixes whose last word is bait for some
lookback against bodies each rule acts on, so a new pass is one line. The one exemption is a
sentence that opens on a spoken mark name, which the pass writes onto the word before it on
purpose.

A sentence-local pass reads no further back than the sentence it is cleaning. A rule
that gathers context by walking outwards from a word is bounded at the sentence end as
well as by a word count: `WordShape.key` drops a trailing stop, so without that bound a
two-word phrase, a number anchor or a determiner can be matched across a boundary the
speaker set. `Draft.sentenceRun` is the bound, and `SentenceLocalityTests` holds every
such pass to it.

## 4. The language model, as the last formatter

The model sees a prompt built from three layers by `PromptBuilder`, each layer a
separate, testable piece of data:

1. **The contract** — `PromptContract`, fixed for every destination: the goal, the output
   shape, the restraints, and twelve worked examples.
2. **The formatter block** — one `PromptBlock` per `PromptBlockID` in `PromptBlocks.swift`:
   the style rules and up to two worked examples *for that destination*. A message example
   teaches "no trailing stop"; a code example teaches line breaks; a sheet example teaches one
   line. Examples are Swift literals, and `ScorerTests` keeps them disjoint from the corpus.
   `PromptBuilder.instructions(for:)` assembles contract and block.
3. **The situation block** — built per dictation by `PromptBuilder.userPrompt`: the "Typed
   into:" line, "Text before the caret: …" when the caret is mid-sentence, the
   doubtful-words line from §5, and the clean-up steps the user switched off.

`PromptBuilderTests.instructionBudget` holds every destination's instructions within a fifth
over the 2,889-character single prompt the layers replaced, because the bake-off shows
examples matter and size costs tenths of a second.

**What the model is for, exactly.** It does the cleanings that need judgement — sentence
boundaries, commas, question marks, casing of names, the choice among doubtful words,
and the grammar slips below — and it applies the formatter's layout. It is handed the draft
*after* the passes, so the fillers and self-corrections are already gone and it cannot
"help" by rewriting around them. Its output is then held to the draft by the guard.

**Grammar slips, bounded.** Speech leaves grammar that the speaker would never type:
"there is three of them", "he don't know", "I have went", "a apple", a tense that
changes mid-sentence. The model may repair these, under a rule that keeps it a cleaning
rather than a rewrite: **a grammatical fix changes the form of a word the speaker said,
or adds or removes an article or a preposition; it never changes which content words
are present or their order.** The guard enforces exactly that: every content word in the
draft must survive in the output, in order, and the function words changed are capped per
sentence. Dialect and deliberate informality are not slips — "gonna", "ain't", "me and him
went" stay — and the formatter's `GrammarPolicy` decides how much grammar a place wants: a
document gets the repair, a message keeps "he don't" if that is how the speaker talks.
Grammar has its own corpus category (`grammar`), so the bake-off shows per destination
whether the repair helped or overreached.

## 5. Doubtful words — the "Apple or apples" problem

The recogniser reports a probability for every word (`wordTimestamps: true`), and the
correction engine acts only on words under `WordCorrectionEngine.certaintyThreshold` (0.5).
The doubtful-word design generalises that into candidates and a chooser:

```swift
/// Where another reading of a doubtful word can come from.
public protocol CandidateSource: Sendable {
    func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading]
    func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]]
}
```

Four sources ship, asked at once by `DoubtfulWords` and merged in this order, the first to
offer a spelling keeping it: the **personal dictionary** (`DictionaryCandidates`, the
correction engine's own lookup, carrying the entry on the `Reading` so a reading the model
takes is counted as a use), **screen vocabulary** (`ScreenCandidates`: words in the window
title, the selection and the text around the caret), **ordinary words** (`PhoneticCandidates`,
the Double Metaphone neighbours in `GeneralVocabulary`), and **homophones**
(`HomophoneCandidates`, a word's partner in the hand-kept `Homophones` table).

The **chooser is the same model call**: the situation block lists each doubtful word
with its candidates —

```
Doubtful words: "apple" (heard at 0.31) — could be: Apple, apples
```

— and the contract says to pick the reading that fits the sentence and the place, or keep
the heard word. That is the sentence-level judgement at zero extra latency and with no
second model. The guard then checks that every changed run is the run as heard or one of
the readings offered for that run, at that position (§6); a word changed to anything else is
an invention and the output is refused.

A word the recogniser was **sure** of but wrong about ("by" for "buy") is not caught this
way: every source, the homophone table included, is asked only about runs scored under the
threshold.

## 6. The guard

`MeaningPreservationGuard` compares provenance, not only counts:

- every word the model dropped must be `.removed(by:)` a pass, or a doubtful run replaced
  by a candidate;
- every word the model added must be punctuation, layout, or a candidate;
- the formatter's layout must hold (no list where the layout has no `.lists`, no added
  paragraph break where it has no `.paragraphs`);
- the base checks stay: no preamble, no invented number, no growth beyond a ratio;
- a pass's removal is provenance only within the `RemovalGrant` the pass declares, and a
  content word or negation removed beyond it is judged as if still in the draft
  (`RemovalAudit`, `Docs/cleanup.md`).

A doubtful run is judged where it stands. `RewriteAlignment` pairs each run of the kept draft
with the run of the rewrite in its place, and `readingVerdict` requires a changed run to be
that span's own heard text or one of that span's own readings; the details are in
`Docs/ai-model-output.md`.

A refusal falls back to the rules' answer — the draft after the passes, which is a good
result on its own, because the passes did the Tier 1 work.

## 7. Join-level layout

The pieces cut while the key is held (`Docs/early-transcription.md`) are each cleaned
alone. Some cleanings only make sense over the whole:

- **Lists** from sequence words ("first… second… third", "one… two…") across pieces:
  two or more items, each a clause, become a list if the formatter's layout allows it.
- **Paragraphs**: a piece boundary is a pause the speaker made; when the next piece
  opens with a topic word ("second thing", "also", "next", "okay so") and the formatter
  allows paragraphs, the join is a blank line rather than a space.
- **Restatement corrections** that straddle a boundary. `PieceJoiner` strips the previous
  piece's trailing stop before asking `Restatement.discardedStart` and restores it if nothing
  matched, so the callee keeps its sentence-end rule and the stop the cut introduced is
  removed by the code that created it.
- **The seam's stop.** A piece ends at a pause of <!-- value:SpeechWindowing.sentencePause -->0.8 s; past
  <!-- value:SpeechWindowing.comfortableLength -->15 s the pause needed shrinks evenly to
  <!-- value:SpeechWindowing.anyPause -->0.4 s at <!-- value:SpeechWindowing.maximumLength -->30 s (`SpeechWindowing`), which reads as a sentence ending, so a seam
  ends as a sentence the way the place ends one: a full stop unless the place's stop policy
  is `.never`, in which case a stop the recogniser wrote comes off. A pause is not always a
  sentence end, so a seam takes no stop where a list item or a code line ends the piece, or
  where the words on either side of the cut show the sentence ran through it: the piece ends
  on a word no sentence ends on ("we moved the review to"), or the next piece opens on a
  preposition a speaker never fronts followed by a name or a determiner ("to Thursday"). A
  seam with no evidence either way keeps its stop.
- **Spoken groups across a seam.** A digit group or a run of capital letters on both sides of
  the cut, at most `PieceJoiner.longestSpokenGroup` long, is one number or code said in groups
  ("555" | "0142", "AB" | "123"), and the groups are joined with a space. Where the evidence says
  the sentence ran through, a full stop the recogniser wrote at the cut comes off too; a question
  or exclamation mark stays, and the group row abstains on it. The cost is a sentence that ends
  on a number before one that opens on a number ("It costs 12." | "13 people came."), which it
  joins; the measurement is in `PieceJoinerTests`.

Some passes are only correct over the whole message, and their scope is in the type.
`CleaningPipeline.piece(numbers:digits:…)` is what a piece gets — it takes no
`FirstWordPolicy` and no `TerminalStopPolicy`, so it cannot decide the first word or the
final stop — and a `TransformationRequest` says `scope: .piece` to ask for it. After the
join, `TranscriptCleaning.finishMessage` runs `CleaningPipeline.message(for:situation:heard:)`
(`SentenceBoundaryPass`, `FirstWordPass`, `TerminalStopPass`) once over the joined text. That
is where the caret's lower-case start is applied to the message's first word only, and where
`.offForShortMessages` counts the message's sentences rather than a piece's. The model is
still called once per piece; the message stage is deterministic and calls nothing.

`PieceJoiner` is one pure function over `[Draft]` and a formatter, tested on its own.

## 8. Latency: where the time goes and what runs beside what

| Stage | Budget | Runs beside |
|---|---|---|
| Situation read (app, field, caret text) | `MacContextEngine.budget`, 100 ms, once per dictation | the recording itself |
| Destination + formatter lookup | microseconds | — |
| Deterministic passes | under a millisecond per piece | — |
| Candidate sources | single-digit milliseconds per piece, the sources in parallel | — |
| Model call | the one slow step, per piece | recognition of the next piece (different hardware) |
| Guard | under a millisecond | — |
| Join-level layout | under a millisecond | — |

A source is asked for a whole piece's runs at once, not run by run, which keeps its cost a
per-piece cost rather than a per-run one. `ScreenCandidates` is why that matters: everything
it derives — the join of title, selection and caret text, the split, the 512-word cut
(`maximumWordsOnScreen`), the dedupe, and a Double Metaphone code for every word that
survives — depends on the screen and not on the run being asked about, so asking run by run
would redo it for every run, and a noisy recognition with many doubted runs would cost the
most. The default implementation asks one run at a time, which is right for a source whose
index does not depend on the screen.

Working ahead hides the model call for every piece but the last, so the wait after the key
comes up is the last piece's cost. Nothing on that path is longer than the situation read,
which runs while the user is still speaking. **Rule: one model call per piece, never a
second model, never a second round trip.** A cleaning that cannot be done in a pass or in
that one call is not done.

## 9. What makes it editable

- A new app: a row in `DestinationRules.swift`.
- A new formatter decision: a case on a policy enum and a value in the registry.
- A new kind of structured writing: a format adapter and its notation rows, never a
  `destination ==` branch ([adapters.md](adapters.md)).
- A new cleaning: a `CleaningPass`, a place in `CleaningPipeline.piece` or `message`, and a
  corpus case.
- A new style rule for one place: a line in that destination's prompt block and an
  example beside it; the bake-off for that destination says whether it paid.
- A new source of readings for doubtful words: a `CandidateSource` added to `DoubtfulWords`.
- Nothing above touches `DictationPipeline`, which only orders the stages.

Each idea has one reason to change (single responsibility); the pipeline depends on the
protocols, not the values (dependency inversion); a formatter is closed to modification
and open to a new value (open/closed). Nothing is built for a destination that has no
corpus cases (YAGNI); the passes are the one tokenising of the transcript (DRY); and the
whole thing is four types and a table (KISS).

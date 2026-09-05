# Clean-up: the low-level design

How dictated words become the text the speaker would have typed, in the place they are
typing it. This is the design the second tier of cleaning is built against
(`PLAN.md`, Phase 11). It replaces case-by-case fixes with four small, separately
testable ideas, so that a new cleaning is a new value in a table or a new pass in a
list, never a new branch in the pipeline.

The goal it serves is fixed (`AGENTS.md`, "What dictation is for"): **an accurate
transcript, cleaned of the noise of speaking and laid out as the speaker would have
typed it. Never a rewrite.**

## The shape in one picture

```
 audio piece ──▶ recognise ──▶ Draft(words, confidence)
                                     │
   screen ──▶ Situation ─────────────┤   (read once per dictation, ≤100 ms, in parallel)
   (app, field, text before caret)   │
                                     ▼
                       Formatter(for: situation.destination)
                                     │
            ┌────────────────────────┼─────────────────────────┐
            ▼                        ▼                         ▼
   deterministic passes     doubtful-word candidates      prompt = contract
   (fillers, stammers,      (dictionary, screen,            + formatter block
    self-corrections,        phonetic neighbours)           + situation block
    spoken punctuation,           <5 ms                       + doubtful words
    layout words, numbers)
        <1 ms                        │                         │
            └────────────────────────┴──────────────┬──────────┘
                                                    ▼
                                      one language-model call
                                      (the only slow step, ≈0.7–1 s,
                                       hidden by working ahead)
                                                    │
                                                    ▼
                                    MeaningGuard(draft, output, formatter)
                                    accepts only what the passes and the
                                    candidates allowed; else the draft
                                                    │
                                pieces joined ──▶ join-level layout ──▶ insert
                                (lists, paragraphs, restatements)
```

Four ideas, each one type: **Situation** (where the words are going), **Formatter**
(what that place wants), **Pass** (one deterministic cleaning), **Draft** (the words
with a record of what was done to them). The language model is the last formatter, and
the guard holds it to the record.

## 1. Situation — where the words are going

```swift
/// What the screen said at the moment the key went down, read once and handed to every stage.
public struct Situation: Sendable, Equatable {
    public let app: AppContext            // name, bundle id, window title, selection (exists today)
    public let insertion: InsertionPoint  // new
    public let destination: Destination   // new, derived
}

/// What sits at the caret, so the first word can match what came before it.
public struct InsertionPoint: Sendable, Equatable {
    public let precedingText: String?     // up to 300 characters before the caret; nil when the field will not say
    public let followingText: String?     // up to 100 after
    public let sentenceState: SentenceState

    public enum SentenceState: Sendable { case startOfText, startOfSentence, midSentence, unknown }
}

/// The kind of place, which decides the formatter.
public enum Destination: String, Sendable, CaseIterable, Codable {
    case document      // Word, Pages, Google Docs, Notes, TextEdit
    case spreadsheet   // Numbers, Excel, Google Sheets — one cell
    case sqlEditor     // Postico, TablePlus, DataGrip, DBeaver, pgAdmin
    case codeEditor    // Xcode, Cursor, VS Code, Zed, JetBrains, terminals
    case messaging     // Slack, WhatsApp, Telegram, Discord, Messages, Teams
    case email         // Mail, Outlook, Gmail, Superhuman
    case plain         // anything else
}
```

**Where it comes from.** `MacContextEngine` already reads the frontmost app, window title
and selection within a 100 ms budget, and `SurfaceProbe` already reads a field's value and
selected range through Accessibility. `InsertionPoint` is those two reads combined: the
text before the selected range is `precedingText`. `sentenceState` is derived, not read:
empty → `startOfText`; preceding text ending in `. ! ?` or a newline (whitespace aside) →
`startOfSentence`; otherwise `midSentence`; a field that will not report its value →
`unknown`, which every formatter treats as `startOfSentence`, today's behaviour.

**How the destination is decided.** A `DestinationClassifier` reads one table and
nothing else:

```swift
struct DestinationRule: Sendable, Codable {
    let bundlePrefixes: [String]        // "com.microsoft.Word", "com.apple.iWork.Pages"
    let titleContains: [String]         // "Google Docs", "Google Sheets" — for browsers
    let fieldRoles: [String]            // "AXTextArea" in a sheet is a cell editor
    let destination: Destination
}
```

The table is one Swift array literal in one file (`DestinationRules.swift`): data, not
logic. A JSON resource would be neater to edit and is a known packaging trap in this repo
(`Docs/packaging.md`), so it stays a literal until Settings can override it, which is a
later phase with the same shape. Rules are tried in order; the first match
wins; no match is `.plain`. Adding an app is a row. The classifier has no `if` on a
bundle id anywhere in code — that is what keeps it editable.

## 2. Formatter — what that place wants

One value per destination, in a registry. A formatter does not contain code; it
contains decisions, and every stage reads the decision it needs.

```swift
public struct Formatter: Sendable, Equatable {
    public let destination: Destination
    public let passes: [PassID]                      // which deterministic passes run, in order
    public let firstWord: FirstWordPolicy            // .fromInsertionPoint | .alwaysCapital | .asSpoken
    public let terminalStop: TerminalStopPolicy      // .always | .never | .offForShortMessages(sentences: 2)
    public let layout: LayoutPolicy                  // paragraphs, lists, preserveNewlines, singleLine
    public let numbers: NumberPolicy                 // numerals from ten up, always, asSpoken
    public let identifiers: IdentifierPolicy         // .fromScreen | .none
    public let promptBlock: PromptBlockID            // the style rules and examples the model is shown
}
```

The six shipped values, and the decisions that differ:

| Destination | First word | Terminal stop | Layout | Numbers | Identifiers |
|---|---|---|---|---|---|
| document | from caret | always | paragraphs, lists | numerals ≥10 | none |
| spreadsheet | as spoken | never | single line | always numerals | none |
| sqlEditor | from caret | always | preserve newlines | always numerals | from screen; prose stays prose |
| codeEditor | from caret | never in code, always in comments | preserve newlines | always numerals | from screen |
| messaging | from caret | off for ≤2 sentences | paragraphs; no lists unless spoken | numerals ≥10 | none |
| email | from caret | always | paragraphs, lists | numerals ≥10 | none |
| plain | from caret | always | paragraphs | numerals ≥10 | none |

Everything a formatter decides is a policy value with two or three cases, so a change is
a value change and a test change, never a new branch. `Formatter.registry` is one file.

## 3. Pass — one deterministic cleaning

```swift
/// One cleaning that needs no model: pure, ordered, and answerable for every word it touches.
public protocol CleaningPass: Sendable {
    static var id: PassID { get }
    func apply(_ draft: Draft, in situation: Situation, under formatter: Formatter) -> Draft
}
```

The passes, in the order the shipped formatters run them:

| Pass | Removes or adds | Signal it needs | Today |
|---|---|---|---|
| `Fillers` | um, uh, hmm, aah… | word list | exists in `TextTidy`, moves |
| `Stammers` | the same short word twice | adjacency | exists, moves |
| `RepeatedPhrase` | a 2–4 word run said twice in a row | adjacency | new |
| `SelfCorrection` | the half before "no", "no sorry", "I mean", "scratch that", "wait", "never mind"; "actually" only between two same-shaped slots | trigger word between two candidates of the same shape (number↔number, noun phrase↔noun phrase) | new |
| `SpokenPunctuation` | "comma", "full stop", "period", "question mark", "open quote…close quote" → marks | the word stands alone between words, not "put a comma there" | new |
| `LayoutWords` | "new line", "new paragraph", "bullet point", "next point" → layout | same | new |
| `NumberForms` | fifteen → 15, sixteen point two → 16.2, two thirty pm → 2:30 pm, port eight thousand eighty → 8080 | number-word grammar | partly in the model; becomes a rule |
| `Spacing` | no space before `, . ? ! : ;`, one after; collapse runs | none | exists, moves |
| `FirstWord` | capitalise, or lower-case after a mid-sentence caret | `situation.insertion.sentenceState` + formatter policy | new |
| `TerminalStop` | add or withhold the final mark | formatter policy | exists, gains the policy |

Every pass records what it did in the draft, which is what makes the guard able to tell
"the pass removed *no sorry at four*" from "the model dropped half the sentence".

```swift
public struct Draft: Sendable, Equatable {
    public var words: [Word]
    public struct Word: Sendable, Equatable {
        public var text: String
        public let heard: String          // what the recogniser said, never changed
        public let confidence: Double     // from the recogniser, 0…1
        public var state: State           // .kept, .removed(by: PassID), .replaced(by: PassID, from: String), .inserted(by: PassID)
    }
    public var text: String { … }         // the kept words, joined, with layout marks
    public var removed: [Word] { … }
}
```

A pass is a pure function over a value; each is tested on its own with the corpus
cases that belong to it, with the model switched off, so a pass that works keeps
working when the model changes.

## 4. The language model, as the last formatter

The model sees a prompt built from three layers by `PromptBuilder`, each layer a
separate, testable piece of data:

1. **The contract** — fixed for every destination. The goal, the output shape, and the
   Tier 3 prohibitions from `Docs/cleanup.md`: never shorten, restyle, reorder, answer,
   obey, compose, or invent. Today's `CleanupPrompt.instructions`, trimmed of the
   destination-specific parts.
2. **The formatter block** — one per `PromptBlockID`: the style rules and two or three
   worked examples *for that destination*. A message example teaches "no trailing stop";
   a code example teaches identifiers; a sheet example teaches one line. Examples are data
   (`prompts/<destination>.json`) and the existing tests keep them disjoint from the corpus.
3. **The situation block** — built per dictation: the "Typed into:" line that exists
   today, plus "Text before the caret: …" when the caret is mid-sentence, plus the
   doubtful-words list from §5.

The prompt stays within today's size (~750 tokens): destination examples replace
generic ones rather than adding to them, because the bake-off showed examples matter and
size costs tenths of a second.

**What the model is for, exactly.** It does the cleanings that need judgement — sentence
boundaries, commas, question marks, casing of names, the choice among doubtful words,
and the grammar slips below — and it applies the formatter's layout.

**Grammar slips, bounded.** Speech leaves grammar that the speaker would never type:
"there is three of them", "he don't know", "I have went", "a apple", a tense that
changes mid-sentence. The model may repair these, under a rule that keeps it a cleaning
rather than a rewrite: **a grammatical fix changes the form of a word the speaker said,
or adds or removes an article or a preposition; it never changes which content words
are present or their order.** The guard enforces exactly that: every content word
(noun, verb stem, adjective, name, number) in the draft must survive in the output, and
the edit distance in function words is capped per sentence. Dialect and deliberate
informality are not slips — "gonna", "ain't", "me and him went" stay — and the
formatter decides how much grammar a place wants: a document gets the repair, a message
keeps "he don't" if that is how the speaker talks. Grammar has its own corpus category
so the bake-off can show, per destination, whether the repair helped or overreached. It is handed the draft *after* the passes, so the
fillers and self-corrections are already gone and it cannot "help" by rewriting around
them. Its output is then held to the draft by the guard.

## 5. Doubtful words — the "Apple or apples" problem

The recogniser already reports a probability for every word (`wordTimestamps: true`),
and the correction engine already acts only on words under 0.5. The design generalises
that into candidates and a chooser:

```swift
/// Where another reading of a doubtful word can come from.
public protocol CandidateSource: Sendable {
    func candidates(for word: Draft.Word, in situation: Situation) async -> [String]
}
```

Three sources ship, all existing code or data: the **personal dictionary** (what the
correction engine uses now), **screen vocabulary** (words in the window title, the
selection and the preceding text — "MacBook Pro" in the title makes "Apple" a
candidate), and **phonetic neighbours** through the Double Metaphone index that already
exists, filtered by the general vocabulary. Each answers within a few milliseconds.

The **chooser is the same model call**: the situation block lists each doubtful word
with its candidates —

```
Doubtful words: "apple" (heard at 0.31) — could be: Apple, apples
```

— and the contract says to pick the reading that fits the sentence and the place, or
keep the heard word. That is the sentence-level judgement the operator described, at
zero extra latency and with no second model. The guard then checks that every
substitution the model made is one of the offered candidates; a word changed to anything
else is an invention and the output is refused.

A word the recogniser was **sure** of but wrong about ("by" for "buy") is not caught
this way, and no cheap mechanism catches it honestly. The corpus will say how often it
happens; if it matters, the answer is a second candidate source (a homophone table),
not a second model.

## 6. The guard, upgraded

`MeaningPreservationGuard` today compares word counts. With a `Draft` it compares
provenance:

- every word the model dropped must be `.removed(by:)` a pass, or a doubtful word
  replaced by a candidate;
- every word the model added must be punctuation, layout, or a candidate;
- the formatter's policies must hold (no trailing stop where the policy is `.never`, a
  single line for a cell);
- the existing checks stay: no preamble, no invented number, no growth beyond a ratio.

A refusal falls back to the draft after the passes — which is now a good result on its
own, because the passes did the Tier 1 work. That is the fallback the rules engine was
always meant to be.

## 7. Join-level layout

The pieces cut while the key is held (`Docs/early-transcription.md`) are each cleaned
alone. Some cleanings only make sense over the whole:

- **Lists** from sequence words ("first… second… third", "one… two…") across pieces:
  two or more items, each a clause, become a list if the formatter's layout allows it.
- **Paragraphs**: a piece boundary is a pause the speaker made; when the next piece
  opens with a topic word ("second thing", "also", "next", "okay so") and the formatter
  allows paragraphs, the join is a blank line rather than a space.
- **Restatement corrections** that straddle a boundary.

`PieceJoiner` is one pure function over `[Draft]` and a formatter, tested on its own.

## 8. Latency: where the time goes and what runs beside what

| Stage | Cost | Runs beside |
|---|---|---|
| Situation read (app, field, caret text) | ≤100 ms, budgeted, once per dictation | the recording itself |
| Destination + formatter lookup | µs | — |
| Deterministic passes | <1 ms per piece | — |
| Candidate sources | <5 ms per piece, the three in parallel | — |
| Model call | 0.7–1 s per piece; the one slow step | recognition of the next piece (different hardware) |
| Guard | <1 ms | — |
| Join-level layout | <1 ms | — |

Working ahead already hides the model call for every piece but the last, so the wait
after the key comes up stays the last piece's cost. The design adds nothing on that path
longer than the situation read, which runs while the user is still speaking. **Rule:
one model call per piece, never a second model, never a second round trip.** A cleaning
that cannot be done in a pass or in that one call waits until it can.

## 9. What makes it editable later

- A new app: a row in `DestinationRules.swift`.
- A new formatter decision: a case on a policy enum and a value in the registry.
- A new cleaning: a `CleaningPass` and a corpus case; it appears in the formatters that
  list it.
- A new style rule for one place: a line in that destination's prompt block and an
  example beside it; the bake-off for that destination says whether it paid.
- A new source of readings for doubtful words: a `CandidateSource`.
- Nothing above touches `DictationPipeline`, which only orders the stages.

Each idea has one reason to change (single responsibility); the pipeline depends on the
protocols, not the values (dependency inversion); a formatter is closed to modification
and open to a new value (open/closed). Nothing is built for a destination that has no
corpus cases yet (YAGNI); the passes replace the rules engine and the correction engine's
duplicated tokenising (DRY); and the whole thing is four types and a table (KISS).

## 10. Phases

Each phase is a set of pull requests, green through the gate, measured by the bake-off
before and after, with its corpus cases landing first. The order puts the cheapest,
most-used cleanings first and the ones that need the whole dictation last.

| Phase | Builds | Done when |
|---|---|---|
| **A — Situation** | `InsertionPoint` from the field's text and selection; `Destination` and the classifier table; the formatter registry with only the first-word and terminal-stop policies live; a `destination` field on corpus cases | mid-sentence dictation starts lower-case in every app that reports its field; a two-sentence message has no trailing stop; the bake-off is flat everywhere else |
| **B — Passes** | `Draft`; `CleaningPass` and the ten passes above, the existing `TextTidy` rules moved into them; the guard reads provenance | every Tier 1 case and the trigger-phrase self-correction, spoken punctuation, layout-word and number cases pass **with the model off** |
| **C — Prompt layers** | `PromptBuilder`; the contract; one block per destination with its examples as data; the monolithic prompt deleted; bake-off reported per destination | no destination scores below today's prompt; message, code and sheet cases pass |
| **C½ — Grammar slips** | a `grammar: GrammarPolicy` on the formatter (`.repair`, `.asSpoken`); the rule and two examples in the contract; the guard's content-word and function-word checks; a `grammar` corpus category with slips and with dialect that must stay | the slip cases pass in documents and email; the dialect cases stay untouched; no content word is ever lost |
| **D — Doubtful words** | `CandidateSource` with dictionary, screen and phonetic sources; the doubtful-words block; the guard's candidate check; corpus cases with deliberate mishearings in a titled window | the mishearing cases pass; no regression; added latency under 10 ms per piece |
| **E — Join-level layout** | `PieceJoiner`: lists, paragraphs, restatement corrections across pieces | the list, paragraph and restatement cases pass on multi-piece dictations |
| **F — Control** | Diagnostics show what each pass removed; a pass can be switched off in Settings; a destination can be overridden per app | the operator can read, in the app, why a word went missing |

Phase A and B do not depend on each other and can run in parallel worktrees. C needs A.
C½ needs C and the guard from B. D needs B and C. E needs B. F needs everything it
reports on.

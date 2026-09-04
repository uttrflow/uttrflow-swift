# Tab-to-complete, and the rules that keep it quiet

The user is typing into a field in another application. Uttrflow has seen what they type
into *that* field, so it can finish the line: the rest of the text appears ahead of the
caret, Tab takes it, typing on ignores it. A candidate comes from one of three places,
asked in this order: what this Mac has entered in that field before, what is on this Mac
right now — a branch name, a program on `PATH` — and, when neither has anything, a line
the local model writes for the situation (`Sources/UttrflowPredict/CandidateGeneration.swift`,
`SuggestionCoordinator.generate`).

It shares the product's one claim: the corpus is a SQLite file under Application Support,
it is never uploaded, and the network is still reachable from `UttrflowAccount` alone.

## The pieces

| Piece | Where | What it owns |
|---|---|---|
| Engine | `Sources/UttrflowPredict` | Whether to speak, about one candidate or several, and about which |
| Store | `Sources/UttrflowPredictStore` | The corpus on disk, the range scan, fuzzy fallback, forgetting |
| Capture | `Sources/UttrflowPredictCapture` | Noticing that a field was committed, and recording what went into it |
| Accept | `Sources/UttrflowInput` | Swallowing Tab, inserting the completion, recording that it was taken |
| Surface | `Sources/Uttrflow/Suggestion` | Drawing the inline ghost at the caret, and drawing nothing |
| Verify | `Sources/UttrflowPredict` | Whether a candidate is *correct*, which is not what the ranking measures |
| Generate | `CandidateGeneration.swift` in `UttrflowPredict`, `MLXCandidateScorer` in `UttrflowLocalModel` | Inventing a continuation when the corpus and the machine have none, from the field, the screen and the person's own lines |
| Loop | `SuggestionSession`, `SuggestionCoordinator` | Sequencing all of the above, once per keystroke |

The path through them is one direction per keystroke. Capture writes what the user
finished entering into the store, keyed by `Surface` — bundle identifier, Accessibility
role, whatever locator the field publishes, and the page host or containing directory.
Retrieval asks the store for candidates matching what has been typed on the current line,
and the store answers from every document of the same field in the same application: the
same text learned in two folders is one candidate with its counts summed
(`PredictStore.candidates`). When the corpus has nothing, the machine is asked
(`EnvironmentSource`); when the machine has nothing either, the model generates. The engine
scores remembered candidates against the moment and answers with one `Suggestion` —
`.silent`, `.certain`, `.choice` or `.minimised`; generated lines are drawn in the model's
own order. The surface draws that and nothing else; it is handed text, not a decision.
Accept turns Tab into an insertion and tells the store, which counts the use at a discount.

`PredictionStore` is a protocol in the pure module, so the engine is tested against
candidates in an array rather than a database.

## The unit of a completion is the line

**A completion continues the line the caret is on — not the field, not the sentence, not
the word.** `FocusedFieldSnapshot.currentLine` derives it: the text from the newline before
the caret up to the caret, with the caret offset read as UTF-16 (which is what
Accessibility publishes) and moved back onto a character boundary so a split emoji or a
combining mark cannot be cut in half. `caretAtLineEnd` asks the matching question — is the
caret at the end of *that* line — so text on the lines below does not silence the feature.

This was found by running the app rather than by reading it. `PredictionContext.typed` was
the whole field value, so in a three-line TextEdit document the prefix query looked for
entries beginning with the entire document; nothing could ever match, and no suggestion was
ever drawn in any text area. Capture had the same root, and after two commits the corpus
held one entry containing the whole document — unretrievable, and unbounded in size.

**Both ends must use the same unit or the corpus fills with values nothing can find.**
`SuggestionCoordinator` derives the line once and hands it to prediction and to capture, so
`CaptureEvent.keystroke` carries the line and `CommitDetector` commits the line.
`Acceptance.edit(accepting:after:)` is given the same string, so what a replacement can
destroy is bounded by the current line by construction.

**What is drawn is the tail, not the whole candidate.** `SuggestionCoordinator` hands the
line to the surface as well as to the engine, so the ghost shows only what Tab will add.
Without it the surface drew the entire candidate over the text already typed — the
acceptance was still correct, because `Acceptance` was given the line either way, but what
the user saw repeated what they had written.

**A terminal publishes the prose role and is not prose.** `AXTextArea` is what a document
and a shell both publish, so the 400 ms hesitation gate was quieting terminals — the case
where an instant answer matters most. `TerminalApplications` in `UttrflowPredict` names the
shells by bundle identifier, which is the only signal that separates them; a fuller dialect
registry will own that question later. An editor's terminal pane cannot be told from its
editor by bundle identifier, so those are still read as prose.

**A document's scope is the folder it sits in.** Scoping a document to its own file path
gave every file its own corpus, so nothing learned in one document helped in another. A
path that names a file is scoped to the directory containing it; a path that is already a
directory — a terminal's working directory — is scoped to itself, which is the same idea.

**Status.** Every piece exists and the app runs them: `SuggestionCoordinator` owns the
loop, verification sits between ranking and drawing, one `MLXCandidateScorer` is wired in as
both scorer and generator, and `AppDelegate` builds it. `PLAN.md` tracks the phases.

## Turning it on

Settings → Suggestions → **Finish what I am typing**. Off for everybody who has not asked
for it, and on from the moment the switch is thrown — the app builds the loop there and
then rather than at the next launch. The same switch takes it away again.

The defaults key this used to read, `com.uttrflow.predict.enabled`, is gone. The switch
writes `suggestions.isEnabled` inside the settings blob, which is the same value the rest
of that screen edits, so there is one answer to "is this on" rather than two that can
disagree.

Grant Accessibility — the loop needs it three times over, to read the focused field, to
watch the keyboard, and to put the completion into the field.

The rest of the screen follows from the master switch: **Only suggest when it is sure**
draws a completion and never a list, **Pause everywhere** stops for half an hour, and the
**Applications** list carries the four editors that ship switched off, everything the user
has switched off since, and everything the corpus has learned from — so a switch that is
off can always be found and turned back on.

The first time a value is committed in an application, Uttrflow asks once whether it may
learn from that application, and remembers the answer in
`~/Library/Application Support/Uttrflow/predict-consent.v1.json`. Until that question is
answered nothing is recorded, so the corpus has nothing to offer in that application. The
machine and the model still answer, so the first field is not necessarily silent — what it
cannot do yet is remember. To see a remembered line: type something, press Return, answer
the question, then type it again.

`Uttrflow` in that path is the folder this build writes under, and a development build
writes under its own — see [development-build.md](development-build.md).

## The loop, once per keystroke

`SuggestionSession` in `UttrflowPredict` is the whole sequence as pure code: it holds the
field, what is drawn, where the highlight sits, how many suggestions have been typed past
and how far the escape ladder has been walked. It answers a moment with either what to
draw or a question for the store, and it stamps every question with a generation so an
answer that arrives after the user has typed on is dropped rather than drawn.

The store's answer is not drawn directly. `resolve` ranks it, and a turn with anything on
offer comes back as `.verify`, carrying the head of the ranking —
`SuggestionSession.verifiedDepth` candidates, which is every one that could be drawn and
no more. Those go through `Verifier`, and the second `resolve` draws whatever the gates
left. A turn with nothing on offer settles without the gates being troubled, because a
candidate that is not going to be shown has nothing to be wrong about. Both halves carry
the same generation, so a verdict reached after the user typed on is dropped, and both
are measured against `turnBudgetInMilliseconds` — 8 000 ms, wide enough for the model to
answer — timed from the moment after the field was read, so the cross-process read is not
charged against it.

`SuggestionCoordinator` in the app is the part that cannot be tested headlessly: a global
key monitor, a one-second tick, the Accessibility read on a queue of its own, the event
tap, the panel, and the corpus. It reads the field off the main thread, and a turn that
takes longer than `SuggestionSession.turnBudgetInMilliseconds` draws nothing at all —
answering a moment that has passed is worse than answering nothing.

One turn runs at a time. `TurnGate` admits a turn, holds the next while it runs, and after
10 s (`TurnGate.stallSeconds`) leaves the running one behind and admits the next in its
place; a turn left behind asks `isCurrent` before it touches anything, so a read into an
unresponsive application cannot end the loop. A Return or an application switch that
arrives while a turn runs is kept and run afterwards, never overwritten by the tick that
follows it.

### The model path

When the corpus and the machine both have nothing for the line and the generator reports
`isReady`, the turn takes the model path in `SuggestionCoordinator.generate` instead of
`resolve`:

- **Reuse first.** The model's last answer for this field is kept, and while the line still
  begins one of its lines — typing on, or backspacing — that answer is drawn again and no
  pass runs. An empty answer is remembered against the exact line it was given for, so a
  tick does not ask the same question again; the next keystroke asks afresh.
- **120 ms debounce.** A pass sleeps `generationDebounceInMilliseconds` first and the next
  keystroke cancels it, so a burst costs one pass for its last prefix rather than one per
  key.
- **Context is read once a pass is certain.** Only after the debounce does the turn read the
  situation — window title and surrounding text under a 200 ms `Deadline`, the person's six
  most recent lines in this field, the 400 characters before the caret's line — so a
  cancelled burst never pays for it. `Docs/predict-context.md` has what is read and why.
- **One line first.** The pass asks for the single most likely completion and stops at its
  newline; `resolveGenerated` draws it as `.certain`. The alternatives are fetched in a
  second pass once that line is on screen and `expandGenerated` turns it into a `.choice`,
  so ↓ still opens a list and nobody waited for it. Quiet mode never expands.
- **Drawn against the field as it is now.** A late answer is drawn only after a fresh read
  finds the same field and the same line (`drawFresh`), so a scrolled caret is followed and
  a changed line is not written over.

Generated lines do not pass through `Verifier`: they are the model's own, and a generated
line typed past does not count towards the field's three rejections.

## Correctness above habit

Frequency says what the user does, not what is right. Somebody who has typed `git comit` a
hundred times has an entry with a hundred uses behind it, and `Ranking` — which measures
evidence and nothing else — will put it first. The verification tier is what stops that
entry ever being offered, and it runs before anything is drawn.

`Verifier` runs four gates in order and `Verification` holds the rules they apply.

**1. Existence, first and unconditionally.** If the machine itself says the word exists —
a program on `PATH`, a subcommand this machine's `git` accepts, a name the user's shell or
git configuration binds — the verdict is `.attested` and nothing below may touch it. This
is the gate that matters, because half of what looks like a typo is a real alias:
somebody who has bound `cm` to `commit` gets `git cm` offered, and a tier that "helpfully"
corrected it would be arguing with the user about their own configuration. The model is
not even asked.

**2. Plausibility.** The local model scores the candidate's mean log-likelihood per token
in context — one forward pass, no generation — against `plausibilityFloor`. A model with
no opinion, and a model that is not loaded, are both *no objection*: the statistical tiers
answer alone and the feature is less clever rather than slower.

**3. The nearest correct neighbour.** A word the machine has *denied* — it answered, and
this word is not in its answer — is looked up against everything it does know. The match
is `TypoModel`'s own channel rather than a new distance: a neighbour is offered only when
one slip no dearer than `TypoModel.indelCost` explains the difference, which admits a
transposition, a doubled letter and a neighbouring key, and excludes a distant
substitution and anything in the first character. `FuzzyMatch`'s character mask is the
prefilter, and `FuzzyMatch.budget(forQueryOfLength:)` is why nothing under three
characters is ever corrected. The corrected form is what gets offered, silently.

**Silence is not a denial.** A machine that has not answered yet — a cold
`EnvironmentIndex`, or a field with no working directory at all — knows nothing, so
nothing is corrected and nothing is rejected. Getting this wrong would correct a
legitimate alias during the five seconds before the first read lands.

**4. Superseding.** A candidate the gates corrected or refused is passed to
`SupersessionRecording`, which `PredictStore` implements with the `supersede` it already
had — a correction names its replacement, and a refusal names itself, since nothing on
this machine replaces it. Either way the entry stops accruing weight and is never proposed
again, even if the user types it a hundred more times. An over-budget verdict is not
reported: that is the clock failing, not the candidate.

### The budget, and what a missed one is allowed to show

Seven seconds — 7 000 ms, in `Verification.budgetInMilliseconds`, inside the turn's own
8 000. Only the model can spend it, so it is raced against a sleep: if the sleep wins, the
verdict is `.rejected` and the candidate is not shown. **A verification over budget shows only what the environment had
already attested** — and since gate 1 returns before the model is asked at all, an
attested candidate never reaches the race. An over-budget verdict is deliberately *not*
cached, so the next keystroke may ask again.

The budget belongs to the keystroke rather than to the candidate. `Verifier.verified` takes
one deadline and shares it across the whole set, and a candidate reached after it has passed
is not scored at all — sixteen candidates cannot cost sixteen budgets.

### The cache

`VerdictCache` is keyed by `(candidate, context)` and is a plain value type, so what it
does is testable without a model or a machine. Sixty-four verdicts, oldest dropped first,
each believed for five seconds — the same lifetime `EnvironmentIndex` gives an answer,
because an alias defined a moment ago has to be able to win.

### What a correction does, from the keystroke to the field

The user has typed `git comi`. The store offers `git comit`, which they have entered a
hundred times, and the ranking puts it first. `resolve` asks the gates about it; the
machine's `git` denies `comit` and knows `commit`, so the verdict is
`.corrected("git commit")` and `git comit` is superseded in the corpus on the way past.
The engine runs again over what survived and draws `.certain("git commit")` — the user is
handed the right command with nothing said about the wrong one. Tab then asks
`Acceptance.edit(accepting:after:)` what that costs: `git comi` and `git commit` agree on
`git com`, so the edit replaces `i` and inserts `mit`, and `CompletionRoute` writes it
with one backspace before the insertion.

### The scorer, and what is still open

**The scorer is wired.** `UttrflowApp` builds one `MLXCandidateScorer(model: .gemma3)` and
hands it to `AppDelegate` as both `scoring` and `generating`, so the same loaded model
judges remembered lines and writes generated ones. Gate 2 runs once the model reports
`isReady`; until then `Verifier` reads its plausibility as *silent*, which is no objection,
and the statistical tiers answer alone — a keystroke never waits on a model that is
loading.

**`plausibilityFloor` is -6.0, measured with `uttrflow-bakeoff score`** on
gemma-3-4b-it-qat-4bit (mean log-probability per judged token, Float32 softmax). Real
lines the user had typed scored -0.18 (`ls` → `ls -l`), -1.24 (`ls -la`), -0.35
(`git c` → `git commit -m`), -1.64 (`SELECT * FROM u` → `… users`), -3.26
(`Deploy the re` → `Deploy the release candidate to production`) and -4.65 (`git c` →
`git checkout main`); nonsense scored -9.15 (`ls --zzqx-bogus`), -13.60 (`git cxq`),
-10.62 (`Deploy the rezzq flombat`), -11.77 (`SELECT * FROM uzqx WHERE`) and -7.29
(`gizmo --frobnicate`). The gap is [-9.15, -4.65]; -6.0 leaves 1.35 above the weakest
real line and 1.3 below the nearest nonsense. A plain typo (`git comit -m`, -5.76) passes
this gate and is left to the nearest-neighbour tier, which is where a typo belongs.

**`MLXCandidateScorer` scores the candidate as the whole line it is.** `Verifier` hands it
the stored line (`ls -l`) and what is typed (`ls`); the scorer tokenises the line itself,
takes the typed opening from the line's own spelling, and judges only the tokens past
where the two token streams diverge. It used to tokenise `context + candidate` — `lsls -l`
— which is why every remembered line scored below the floor, was recorded as rejected
(`superseded_by = text`) and never appeared again. Two measured traps remain:

- Gemma 3 4B predicts nonsense from the first two positions after `<bos>` (`" git"` after
  `<bos>$` scored -27; `" -"` after `<bos>$ ls` scored -0.06), so the scorer puts a
  two-token lead-in (`"...\n"`) before every line. `"\n\n\n"` is one token and does not
  help; a chat-template frame puts the instruction-tuned model into peaked answer mode
  (`" commit"` -0.00, `" checkout"` -19.5) and is worse.
- When the typed text ends inside a token (`gi` → `git status`), the divergence rule judges
  `"git"` without knowing `gi` was typed — the cold prior for a line's first word, about
  -10 — so such a line scores around -8 and is rejected. The correct score is
  P(token | typed prefix) = P(token) / Σ P(tokens starting with the typed remainder), which
  needs the vocabulary table; not built yet. Attested candidates (executables, subcommands)
  never reach the model, which is why `lsof` and `lsbom` are unaffected in practice.

Per-call cost is 80–115 ms warm and ~250–340 ms cold on the 4B model, so the four
sequential passes `verifiedDepth` allows — `PredictionEngine.maximumChoices`, every
candidate that could be drawn — fit in well under a second of the 7 000 ms budget.

## The engine decides three things

**Whether to speak at all** is `Ranking.support`, the leader's raw score, against
`PredictionEngine.supportFloor`. Score is evidence, never correctness: log of the use
count, halved every 21 days since the last use, lifted by up to 0.6 for a candidate that
has been offered and taken, divided by `1 + 2 × editDistance` so a fuzzy match is worth
less than an exact one.

**Whether to speak of one candidate or several** is `Ranking.separation`, the gap between
the leader's share and the runner-up's, against `separationThreshold`. Shares are
normalised across the set, so two candidates scoring 99 and 98 read as contested rather
than as one strong answer. Below the threshold the answer is a `.choice` of at most four.

**Whether a candidate may be offered at all.** A candidate marked `isIrreversible` — a
command whose acceptance cannot be undone by pressing Backspace — is never shown without
full separation, and never appears among the alternatives of a `.choice` at any score.

Before any of that, `Quieting.reason` runs six ordered predicates and returns the first
that fires: turned off here, secure field, text selected, caret not at the end of its line,
three suggestions typed past in this field already, or a prose writer who has not yet
paused for 400 ms. It returns *which* rule fired, so the diagnostics can say why nothing
was drawn instead of leaving silence indistinguishable from a broken feature.

Composition does not gate. `PredictionContext.isComposing` is still read and carried, and
`Reason.inputMethodComposing` is still in the enum, but `Quieting.reason` never consults the
one or returns the other. [predict-ime.md](predict-ime.md) has what the signal reaches and
what a gate on it cost.

## The store

One row per surface, one row per entry, one row per succession pair, and two indexes on
`entry`, each for a single query: `entry_prefix` on `(surface_id, text_lower)` for the
prefix range scan run on every keystroke, over the lowercased text so matching ignores case
and keeps the index, and `entry_recent` on `(surface_id, last_used)` for the person's most
recent lines that the model is shown. `Schema.version` is 3: a v1 file, whose index was on
`text`, gains the `text_lower` column, has it filled and has the index moved when it is
opened; a v2 file gains `entry_recent`; a file from a newer build is refused rather than
written to. A surface holds at most 2,000 entries and evicts by count then age. Forgetting
works at three sizes: one entry, one application, everything.

An entry carries `count`, `accepted`, `rejected`, `self_sourced` and `last_used`. A
`superseded_by` value marks text the user has replaced, and a superseded entry is never
proposed again.

## What the measurements found

Phase 0's numbers are in [`Docs/predict-probe.md`](predict-probe.md); re-run them with
`uttrflow-dev probe retrieval`. Two findings sit behind code that would otherwise look
like a free choice.

### `LIKE` is a full surface scan, not a full table scan

Asking SQLite for the plan rather than timing it:

```
RANGE: SEARCH entry USING INDEX entry_prefix (surface_id=? AND text_lower>? AND text_lower<?)
LIKE : SEARCH entry USING INDEX entry_prefix (surface_id=?)
```

Both use the index. Only the range constrains the `text_lower` column — `LIKE 'git c%'`
constrains the surface id and then filters every row belonging to that field, one by one.
So the penalty is not fixed: it grows with how much that one field holds, which is why a
small corpus measured four times and a ranked query over a large one measures far more.

This is asserted as a query plan rather than a wall-clock bound. A threshold calibrated
on this Mac measures whichever machine CI happens to run on — 200 µs here was 495 µs on a
shared runner — while the plan is the same everywhere and fails exactly when somebody
rewrites the query as a `LIKE`.

### The prefilter's mask must be as wide as the query plus its budget

The fuzzy fallback rejects candidates with a 64-bit character mask before it computes any
edit distance. The width of the window that mask covers is the whole of its strength: a
mask over the first *n + k* bytes, where *n* is the query length and *k* its edit budget,
measured **14.9×** faster than no prefilter at all. A fixed twelve-byte window measured
**4.0×**.

Both are sound — a wider window can only weaken the filter, and never rejects a candidate
that would have matched — so the fixed width fails silently, giving up most of the gain
while every test still passes. `FuzzyMatch.maskWidth(forQueryOfLength:within:)` is the one
place the width is decided, and it takes the query.

## Running it in development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --filter UttrflowPredict     # the decision layer, no database and no clock
swift run uttrflow-dev probe retrieval  # the retrieval numbers, on this machine
```

`probe retrieval --entries N` builds a synthetic corpus of commands, URLs and phrases and
times the range scan, the `LIKE`, and fuzzy matching at three prefilter widths. It needs
no permission.

The other two probes do. Accessibility is attributed to the responsible process, so
`uttrflow-dev` launched from a terminal that already holds the grant inherits it and
`AXIsProcessTrusted()` answers true; the probe says so itself when it is refused
("The terminal is what needs permission"). Granting `.build/release/uttrflow-dev` directly in
System Settings › Privacy & Security is the alternative.

```bash
swift build -c release
swift run -c release uttrflow-dev probe surface --seconds 120 --output Docs/predict-sweep.md
swift run -c release uttrflow-dev probe tap --seconds 20
```

`probe surface` records what each application's focused field answers — text, caret
rectangle, styling, or nothing — and prints each new field as it sees it, so somebody has
to click into a text field in every application they want measured while it runs. The
placement decision it was written to inform is made: the inline ghost is the only surface,
and a field that reports no caret rectangle gets nothing drawn
(`SurfaceCapability.placement`, and `draw` in `SuggestionCoordinator`). The sweep still
measures how much of the surface that reaches.

`probe tap` swallows Tab for a few seconds and counts what passed through. `--stall`
sleeps inside the callback past the system's patience, so the tap is disabled and the
recovery path runs.

## The Insights numbers, when they exist

Nothing is on the page yet — phase 6 puts it there. What the store already counts, and
therefore what those numbers will be made of: `count`, `accepted`, `rejected` and
`self_sourced` per entry, `entryCount()` per corpus, and the `Quieting.Reason` that fired.

Read them together, because each one alone is misleading in the same direction:

- **Acceptance rate rises as the feature offers less.** A build that only ever speaks
  about `git status` scores nearly 100% and is worth nothing. Read it against how often
  anything was offered at all.
- **Silence is the expected answer,** so a high silence count is not a fault. The reason
  breakdown is what makes it readable: `secureField` and `writingFluently` are the
  feature working, while `rejectedTooOften` climbing in one application means it is
  wrong there specifically and should be turned off for it.
- **Corpus size is not quality.** 2,000 entries in one field is the eviction cap being
  reached, not a well-learned field.

## The rules that do not bend

1. **Fuzzy is a fallback, never a parallel path.** It runs only when the exact prefix scan
   comes back empty. Measured on 50,000 entries, `git p` matches 925 entries exactly and
   2,776 within one edit — and the extra matches are other commands, `git commit` among
   them. A blended matcher would answer "did you mean `git commit`?" to somebody typing
   `git push` correctly. Queries under three characters are never corrected at all.
2. **Return is only intercepted after Down.** Tab is the accept key. Return belongs to the
   application — it sends the message, runs the command, submits the form — and stealing
   it costs the user the thing they were actually doing. It is taken only once the user
   has pressed Down into the list of a `.choice`, where they are demonstrably choosing
   rather than finishing.
3. **Nothing goes through the clipboard.** The completion is written into the field, and
   the clipboard is not borrowed, not cleared and not restored. `Docs/insertion.md` has
   the traps in the dictation path that pay for this rule; the shorter version is that a
   clipboard round trip races the user's own copy, and this feature fires on a keystroke
   rather than on a held shortcut, so it would race it constantly.
4. **A secure field draws nothing and learns nothing.** `Quieting` refuses it before any
   candidate is scored, and capture never records from it. A password field that a
   completion has ever seen is a password in a database.
5. **Self-sourced evidence is discounted.** An entry that reached the corpus because the
   user accepted our own suggestion counts a quarter of one they typed. Without it,
   offering a candidate is what makes it likelier to be offered, and the failure does not
   announce itself: acceptance rate climbs while the set of things the feature knows
   quietly narrows to what it already said.

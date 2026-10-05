# AI suggestions: register, surroundings and personal style

When the model writes an AI suggestion (tab-to-complete), one mechanism makes it read like a
command in a terminal, a reply this person would send in a chat, and the next line of the document
in a document — with no list of applications anywhere. Each pass carries three kinds of context
read live: the **surroundings** (window title and the text visible around the field), the
**field's own text** before the line, and the **person's own recent lines** in this field. Pure
code derives **register hints** from them — measurable facts, never application names — and the
prompt hands the model the raw context and the hints under a token budget. Latency and accuracy are
the two constraints every choice here is measured against.

| Piece | Where |
|---|---|
| Field and surroundings read | `Sources/UttrflowContext/FocusedFieldReader+System.swift`, `Sources/UttrflowContext/Surroundings.swift` |
| What the model is told | `GenerationSituation` in `Sources/UttrflowPredict/CandidateGeneration.swift`, mapped by `SuggestionMoment` in `Sources/Uttrflow/Suggestion/SuggestionMoment.swift` |
| Register | `Register` in `Sources/UttrflowPredict/Register.swift` |
| Prompt | `CompletionPromptBuilder` in `Sources/UttrflowLocalModel/CompletionPromptBuilder.swift`, run by `MLXCandidateScorer` |
| Recent lines | `PredictStore.recent(in:limit:)` in `Sources/UttrflowPredictStore/PredictStore.swift` |
| Caching for one turn | `SuggestionContextCache` in `Sources/Uttrflow/Suggestion/SuggestionContextCache.swift` |

The loop that calls this is [predict.md](predict.md), the model [predict-llm.md](predict-llm.md),
and the rules that withhold its line [predict-precision.md](predict-precision.md).

`GenerationSituation` carries `application`, `field`, `document`, `preceding` (at most
`SuggestionMoment.precedingContextLength`, 400 characters of the field's own text before the
caret's line), `windowTitle`, `surroundings`, `recentLines` (newest first) and `isMultiline`.

## How a pass is assembled

Context is read only once a pass is certain — after the 120 ms debounce, never for a reused answer
— so a burst cancelled by the next key never pays for it. The surroundings walk and the corpus query
run side by side.

### 1. Read the surroundings

`FocusedFieldReader.surroundings` reads the focused window's `AXTitle` and walks outward from the
field ring by ring — the thread beside a compose box before the sidebar — taking the text of labels,
messages, headings, links, cells and other fields.

- Each ring is gathered nearest the field first and put back into reading order afterwards, so when
  a thread outruns the allowance it is the newest messages that survive.
- In a browser the walk never climbs past the page (`Surroundings.pageRoles`, `AXWebArea`), so the
  tab strip, toolbar and infobars are never read.
- An element is read only where its frame meets the window's: no frame is trusted, zero size is
  hidden, and an off-window element is pruned with its whole subtree. A label a container already
  carries is not read again from its children.
- A field that declares itself secure — the secure role or subrole anywhere, or a name
  `SecureField` recognises on an element that takes text, never on a message that only mentions a
  password — is passed over before its text is asked for, one whose text is mask characters alone
  is dropped, and nothing at all is read around a focused secure field.
- Every element costs one Accessibility message: role, subrole, identifier, placeholder, frame,
  title, description, children and parent in a single multiple-attribute call, the value apart.
- Every label is read without its control and direction marks and without its timestamp parts: a
  chat labels each message "text, 4 September at 6:41 PM, Received from Priya", and `Timestamps`
  drops a part that is only a time, or a date naming a month, weekday or day-half in the current
  calendar's own words, glued or not.
- A terminal's window is not walked (`SuggestionCoordinator.walksSurroundings`): its value already
  holds the scrollback, which reaches the model as `preceding`.

| Bound | Constant | Value |
|---|---|---|
| Walk time | `Surroundings.budgetInMilliseconds` | 60 ms |
| Elements | `Surroundings.maximumElements` | 400 |
| Characters per element | `Surroundings.maximumCharactersPerElement` | 400 |
| Characters in all | `Surroundings.maximumCharacters` | 1,200 (the walk stops the moment they are gathered) |
| One Accessibility message | `FocusedFieldReader.elementTimeoutInSeconds` | 50 ms |
| How long the turn waits for the walk | `FocusedFieldReader.surroundingsAllowance` | 200 ms, then goes on without it |
| How long one window's walk is reused | `SuggestionContextCache.surroundingsLifetime` | 1 s |

The walk runs on its own queue. `SuggestionContextCache` reuses a built `GenerationSituation` for
the same turn, so the alternatives pass asks the machine nothing a second time, and reuses one
window's surroundings for a second, so a burst of passes over an unchanged window walks it once. A
walk that times out is not kept. In a chat this is the last few messages and who they are from; in
Mail the quoted thread; in a browser the page heading and the field's label.
`uttrflow-dev context --bundle <id> --surroundings` prints exactly what this read hands the model.

### 2. Read the person

`PredictStore.recent(in:limit:)` with a limit of `SuggestionMoment.recentLinesShown` (6) first reads
the surface's own retired texts, then runs one indexed `ORDER BY last_used DESC LIMIT ?` read over
`entry_recent` for each scope that matches this surface, and ranks the results in Swift: the lines
written in this very document or conversation first (a greeting belongs to its conversation), then
the rest of the field newest first, each text once, self-sourced-only and superseded lines left out.
The cost scales with the number of matching scopes. Only applications the user allows learning from
have any. The line being typed is never listed among the lines written before
(`SuggestionMoment.recentLines`). In a chat this is how the person answers people; in a terminal
their real commands; in Notes their own phrasing.

### 3. Derive the register

`Register.infer` computes from the situation and the typed text:

| Fact | How |
|---|---|
| `isMultiline` | The prose role, or a value with a newline in it |
| `typicalLength` | Median length in characters of this person's recent lines here, or of the screen's lines when there are none and the screen is a conversation |
| `isConversational` | At least `conversationLines` (3) non-blank screen lines, at least 60% of them under `conversationLineLength` (200) characters, and either people taking turns (at least three lines opening with a short speaker name and a colon, two or more speakers, one speaking twice) or a field named as a message composer ("Type a message", "Message #platform", never a mail's body or subject) beside at least `timedTurns` (2) lines stamped with a time of day. A web page's short menu lines alone are not a conversation |
| `symbolShare` | The share of visible characters, emoji left out, that are neither letters nor digits, over `preceding`, the typed text and the recent lines, excluding punctuation in prose; on lines with a flag or path separator, quotes and dots count as command evidence, and those structured lines give evidence below 8 visible characters, which other samples do not; shell lines sit near 0.14 and prose under 0.06, so `symbolicShare` is 0.10 |
| `usesSentenceCase` | Whether at least half the person's lines here start upper-case and end with sentence punctuation; nothing when they have written nothing here |
| `writesAddresses` | Whether at least half the person's lines here are shaped like web addresses, or with none of their own, whether the field's own accessibility name says it takes one |
| `isSearchField` | Whether the field's own accessibility name says it searches or finds |
| `isCodeDestination` | Whether the destination table classifies the application as a SQL or code editor |

`writesAddresses` and `isSearchField` together decide `answersFromHistoryAlone`: such a field's
line comes only from what this person entered there before, never from generation. The register
turns into short hints the prompt carries (`Register.hints`), a `kind` named at the line (web
address, command, reply, line), a token budget, and a length limit
([predict-precision.md](predict-precision.md)).

Emotion and tone are the model's job, not a classifier's: given the last messages and this person's
earlier replies, the model infers register.

### 4. Assemble the prompt under a budget

`CompletionPromptBuilder` lays out, in order: where the caret is and the hints → what is on screen around the
field → the lines this person wrote here before → `preceding` → the line to finish. The context
around the line has a hard budget of `CompletionPromptBuilder.contextBudgetInTokens` (160) tokens, headings
included; the fixed parts and the line itself sit outside it and are never cut.

- The field's own text before the line is paid for first, from its end, with up to half.
- The person's recent lines take up to half of what is left, newest first.
- The screen takes what remains but never more than `screenBudgetInTokens` (96), as whole lines
  nearest the field, each line said once so a "Reply" under every comment costs one.
- A text or single screen line that exceeds its allowance keeps only complete whitespace-delimited
  words; a word too large to fit is omitted, and whitespace without a word is dropped.
- Once the field's own text fills `ownTextSufficesInTokens` (64), the screen is left out.
- The window title and the leading suggestion the alternatives pass excludes are quoted. Screen
  text, recent lines, preceding text and typed text each use a backtick fence longer than any
  backtick run inside, so a block cannot close its own boundary.
- Where the screen, the title or the text before the line holds another script, the prompt adds
  `LatinOnlyInstruction.text` ([predict.md](predict.md)).

**The estimate.** No tokeniser runs while the prompt is laid out: `CompletionPromptBuilder.estimatedTokens`
counts a run of Latin letters as one token per four, other letters and combining marks as one per
two, and each digit, symbol, newline and space before a digit as one. Over 188 samples of page text,
titles, commands, queries, addresses, Hindi, French and emoji it came to 3,684 estimated tokens for
2,647 real Gemma 3 tokens. Single short lines can be under-counted ("Snoozed" is 4 real tokens
against 2), which a whole section averages out; the budget holds against the estimate.

**The token budget for a pass** (`Register.maxTokens`) is `clamp(typicalLength / 2, 24, 96)` when
the register knows a typical length, else 32 for code-like text, `replyTokens` (48) for a
conversation and 64 otherwise. The one-line pass gets that; the alternatives pass three times that;
each is capped at 128 (`MLXCandidateScorer.maximumTokens`), plus the tokens of the echo it must
repeat (`CompletionText.tokenBudget`). Temperature is 0.

### 5. Write the line into the model's own turn

For the one-line pass, the line up to its last word is appended after the chat template as the
opening of the model's own turn (`Ask.opening(of:)` in `CompletionPromptBuilder.swift`), and the last word is *owed*: a
`TokenHealing` logit processor allows only tokens consistent with it until it is written, then
forbids an immediate newline or end-of-turn so a finished word is continued, then frees the model.
The parser reads `written + answer` as the whole line. The alternatives pass, and a last word
outside ASCII where the vocabulary spells it in byte pieces, repeat the line and continue it
instead. A last word that ends in terminal punctuation may end the line, so a complete line
(`Thanks, see you tomorrow.`) answers nothing.

Measured on 223 misses of the catalogue with `uttrflow-bakeoff complete --fixtures --raw`: asking
the model to repeat the line then continue it left 162 empty answers; prefilling the whole line
gave 59 hits (93 stopped empty at once, since a word cut mid-token cannot be continued and a
finished one invites a newline); leaving the last word unconstrained gave 43 (the model wrote the
likeliest word, `git l` → `git commit`); healing the last word gave 100.

**A word cut mid-word is lengthened unless the model is sure of a break.** `TokenHealing` knows
whether the person stopped inside a word (`isMidWord`: the fragment ends in a letter or digit and
no space follows), and at the step after the owed fragment it prices every token that starts
something new (`Vocabulary.startsNewWord`) by `TokenHealing.newWordPenalty`, 3 logits. It is a
price and not a ban, so a fragment that is a whole word still breaks where the model is sure.
Measured over 1,154 fixtures on Gemma 3 4B QAT 4-bit: breaks directly after a fragment ending in a
letter or digit 62 → 48, spaces among them 47 → 37; hits 573 → 575 over the 611 fixtures the step
can reach, none losing a hit (`tooth` → `toothpaste`, `but` → `buttermilk`; four stop splitting but
misspell instead, `oni` → `oniions`). Under real ambiguity (`npm i`, `see you a`) the fragment is
also a whole word and no local rule can choose. Penalising only spaces is worse: the model escapes
onto other punctuation (`pan.`, `di-jon`), 56 breaks against 48, and a non-breaking space leaks
through.

### 6. Keep the fixed part and the last prompt warm

At load, the instruction prefix — the exact token run two different prompts share, chat template
included — is prefilled into a `[KVCache]`; a pass whose prompt opens with those tokens feeds only
the remainder against a copy (about 60 ms saved per pass). The last pass's whole prompt is kept in a
cache too: consecutive keystrokes on one line share all but the last few tokens, so the next pass
trims that cache back to the longest run the two share and reads only the rest. That saves 20–25 ms
per pass over one typed reply and holds 91 MB between passes ([performance.md](performance.md),
"what a suggestion pass prefills").

## Latency

`uttrflow-bakeoff complete --fixtures` over the 29 hand-written fixtures (`Fixtures.swift`), Gemma 3
4B QAT 4-bit, Apple silicon. The app is a Release build (`Scripts/bundle.sh`), so the Release rows
are what a person sees.

| Configuration | Hit | In register | p50 | p95 |
|---|---|---|---|---|
| Four lines per pass, Debug | 27/29 | 28/29 | 944 ms | 1 340 ms |
| One line first, Debug | 27/29 | 28/29 | 895 ms | 1 054 ms |
| + warm instructions, Debug | 27/29 | 28/29 | 835 ms | 965 ms |
| Same, Release | 27/29 | 28/29 | 677 ms | 819 ms |
| + prompt cap 1,400 characters, Release | 27/29 | 28/29 | **666 ms** | **787 ms** |

The two misses are stable: `sql/update` (`UPDATE users SET ` → nothing usable) and `url/git` (`git`
in an address bar → `git commit -m`). One line first saves about 50 ms at p50 and 290 ms at p95;
warm instructions about 60 ms; a Release build about 160 ms. What is left is a floor near 500 ms
that even a near-empty prompt pays (`search/inv`, 507 ms): a short prefill and eight to twelve
decode steps of a 4B model at a few dozen tokens a second. Neither context nor instructions move
that floor; only a faster decoder does.

### Page context under a token budget

A browser field hands the model a page: navigation, an article, comments, a "Reply" under each.
Under a 1,400-character message cap that filled almost all of the 1,200 surrounding characters, so
every pass prefilled 250–360 tokens of page and the model answered at the length of what it had
read. Measured with an on-disk Gemma 3 4B QAT 4-bit, Release, seven browser-like moments, 20 passes
each, two alternating runs on a heavily loaded machine (compare columns, not absolute numbers),
before and after the 160-token budget:

| Moment | Message tokens before | after | Prefill p50 before | after | Pass p50 before | after |
|---|--:|--:|--:|--:|--:|--:|
| blog comment | 354 | 147 | 146–236 ms | 103–116 ms | 3 019–3 608 ms | 1 455–1 677 ms |
| issue comment | 361 | 143 | 155–248 ms | 117–125 ms | 2 431–3 060 ms | 1 088–1 292 ms |
| web mail reply | 249 | 122 | 108–155 ms | 67–90 ms | 2 693–3 482 ms | 1 340–1 671 ms |
| Hindi news comment | 181 | 109 | 91–125 ms | 64–80 ms | 1 329–1 556 ms | 823–1 031 ms |
| comment with a paragraph typed | 347 | 146 | 152–215 ms | 93–99 ms | 2 071–2 666 ms | 861–1 032 ms |
| bare field | 41 | 41 | 49–72 ms | 52–56 ms | 672–756 ms | 637–730 ms |
| all seven, p50 | | | 143–168 ms | 82–96 ms | 2 038–2 316 ms | 902–1 160 ms |

Prefill falls by about 40%, but most of the time saved is decode: with a page in front of it the
model writes a whole comment, and with the nearest lines it writes a line. On a fanless machine both
savings grow in proportion.

Quality over `uttrflow-bakeoff complete --fixtures`: 542 of 1,154 fixtures get a different message
under the budget; hits go from 968 to 965 and fixtures in register from 990 to 989. The three lost
are one terminal line (`mkdir -p tests` → `mkdir -d tests`) and two notes cuts whose answer was the
same generic sentence; notes lose four in register (77 → 73 of 80 changed), where a document's own
text before the line is held to 64 tokens.

## Accuracy: how it is checked

- **Fixture set.** `Sources/uttrflow-bakeoff/Fixtures.swift` and `Catalogue*.swift`, on the types in
  `Sources/UttrflowEval/CompletionCase.swift` and `Sources/UttrflowEval/LineCut.swift`. `Fixture.all`
  is 29 hand-written fixtures followed by a generated catalogue: a `Scenario` names one place lines
  are typed — its `GenerationSituation`, a length band, text that must never be echoed, sibling
  lines — and lists the full lines typed there; each `Line` is cut at the scenario's `LineCut`s
  (`.afterWord(n)`, `.intoWord(n, by:)`, `.midWord(n)`, `.characters(n)`, `.whole`), and a
  `Determinacy` says how much of the rest the cut determines (the rest of a segment up to a set of
  separators, the whole line, anything in register, or nothing for a finished line). A cut that
  leaves fewer than two typed characters, or nothing to write, is not a case. Cases are named
  `category/scenario/line/cutN` and span terminal, SQL, URL, six kinds of chat, mail, notes, code and
  a `robust/` set. `uttrflow-bakeoff complete --fixtures [--only chat/] [--limit n] [--json f]`
  scores hit rate, register conformance and latency
  ([predict-reliability.md](predict-reliability.md)).
- **Live.** The log's `CONTEXT`, `GENERATE` and `ACCEPT` lines per application; `CONTEXT` records
  lengths only.
- **Guard rails.** Prompt-echo, loop and paragraph filters; at least
  `MLXCandidateScorer.minimumTypedLength` (2) typed characters; secure fields never read; nothing
  generated is stored unless accepted.

## Privacy

Surroundings are read into memory for one pass and never written anywhere — not to the corpus, not
to the log, which names lengths and the application, not the text ([logging.md](logging.md)).
Recent lines come only from applications the user allows learning from, and **Forget what it
learned here** in Settings removes them. Everything runs on the Mac; `make verify`'s offline audit
holds.

## Not done, and why

- No per-application prompts, kinds or tables: the hints are computed and the model decides.
- No sentiment classifier: the transcript plus the person's own replies carry the tone.
- No second scoring pass over generated lines: about 100 ms a line would eat the latency; the pass's
  own score is used instead ([predict-precision.md](predict-precision.md)).
- No reading beyond the focused window: other windows are someone else's context.

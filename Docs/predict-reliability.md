# Reliability loop for tab-to-complete

The bar, set by the operator: if a suggestion worked once it must work every time, in every
application, and a silence must always have a reason. This document is the loop that holds
the feature to that bar and the running record of what it found. Fixes go to the root cause,
with tests, and each is gated by `make verify` before it is committed.

## Three kinds of test, and what each can prove

| Kind | Where | Cases | Proves |
|---|---|---|---|
| Generation fixtures | `Sources/uttrflow-bakeoff/Fixture*.swift`, `bakeoff complete --fixtures [--only p] [--limit n] [--json f]` | ~1 000 generated from scenario × line × cut templates across terminal, SQL, URL/search, six kinds of chat, mail, notes, code, and a `robust/` set built from live failures (™ and bidi marks, emoji, double spaces, finished sentences that must yield nothing, one- and two-character prefixes, 200-character lines) | the model, the prompt and the parser together: hit rate, register conformance (length band, no echo of context), latency p50/p95 — measured in a Release build |
| Seeded property tests | `Tests/UttrflowLocalModelTests/CompletionParsingPropertyTests.swift` and `PromptPropertyTests.swift`; `Tests/UttrflowPredictTests/SuggestionSessionPropertyTests.swift`, `RegisterPropertyTests.swift` and the `RankingPropertyTests` suite in `PredictionEngineTests.swift`; `Tests/UttrflowContextTests/SurroundingsPropertyTests.swift` and `FocusedFieldSnapshotPropertyTests.swift` — each module carries its own `Seeded` xorshift generator, so a failure names the seed that reproduces it; `swift test` | thousands, under ~5 s | the pure pipeline: parser invariants (every result begins with the typed text, distinct, never a prompt heading, never degenerate, one line ends after its first words), prompt invariants (the budget holds, the line is never touched, trimming starts farthest from the line), register invariants (the token budget stays in range, typical length is a median, a conversation is short turns), ranking (better evidence always wins), surroundings-walk invariants on random trees, session sequencing (random scripts keep the promises, rejections are bounded, the quieting reason is the first rule), snapshot line/caret arithmetic on random Unicode. The parser, prompt, register and session suites are being extended |
| Idle-gated live E2E | `Scripts/e2e_predict.sh <report.md>` | ≥ 25 scenarios in Terminal, TextEdit, an address bar and Finder search — never a chat, mail or notes, never Return | the whole system in real applications: ghost drawn, key accepted and read back, alternatives on ↓, no stale ghost across a switch, and above all that the loop is alive after every scenario |

The live harness drives the Mac only after 45 s of no keyboard or mouse input and aborts the
moment the person returns, because it shares their keyboard.

## What the loop found and fixed (newest first)

| Found by | Symptom | Root cause | Fix |
|---|---|---|---|
| Live harness, Terminal | `git s` → `git commit -m` landed nowhere and the field was left with `s` selected; `git c` → `git commit -m` accepted fine | the Accessibility route widened the selection over `s`, Terminal refused the write, and the failed strategy left the selection behind; the keystroke route then read the wrong character before the caret and refused too | a field that took the selection but refused the text puts the caret back before the next route runs; the log names the refusing case, not the dictation message that claimed a clipboard copy |
| Live harness, TextEdit | ↓ never opened on a generated line: `SWALLOWED key=downArrow` never appeared | the alternatives arrived seconds after the line, and the tick that ran as they landed re-read the corpus, redrew the same line as a lone `certain` and disarmed ↓ | `settle` keeps the list behind the same line, sieved to the alternatives that still extend what is typed; a different line still takes the list with it |
| Catalogue run 1 | 180 of 248 failures were the model answering with nothing usable, concentrated on commands, SQL and notes | a one-line pass ran to a token budget that did not count the echo of the typed text, so on a long line the budget was spent re-typing the line and the cut fragment failed the parser | `"\n"` is the stop string of a one-line pass; the budget is a cap per line plus the echo's tokens; a one-line pass that still hits the limit returns nothing rather than a fragment |
| Catalogue run 1 | an address bar was completed like a shell: `git` → `git commit -m`, `news.ycombinat` → `news.ycombinator` | the register saw symbols on single lines and called them commands | `Register.writesAddresses` from the shape of the recent lines (no whitespace, an inner dot followed by a letter), with its own hint checked before the symbolic one |
| Model-path review | a pass that failed was logged and remembered exactly like the model having nothing for the line | `completions` returned `[]` for both, so the coordinator could not tell them apart | `CandidateGenerating` throws; the coordinator logs `GENERATE failed` with the error and remembers the line so a tick never re-runs the failure; the bakeoff records `error: …` as the fixture's answer |
| Collector review | a long thread lost its newest messages to the element and character caps | each ring was gathered in reading order, so the caps cut the end of the thread — the part nearest the compose box | each ring is gathered nearest-first and restored to reading order afterwards; the walk stops the moment the characters are gathered; visibility is the frame against the window, with off-window subtrees pruned |
| Live, WhatsApp | after one chat's suggestion, the next chat showed the old phrase at the old caret and nothing ever again | the surroundings walk blocked on an unresponsive accessibility server, each call waiting the system's seconds; the turn never returned and every keystroke queued behind it | 50 ms per-element messaging timeout; the walk on its own queue; a turn waits ≤ 200 ms for surroundings (`Deadline`); and a `TurnGate` that leaves a turn behind after 10 s so no single hang can end the loop |
| Live, WhatsApp | a line with ™ never got a suggestion; the GPU re-ran a fruitless pass every second | the model repeats the line without the mark, so its echo no longer began with what was typed and every answer was dropped; an empty answer was never remembered | echo matched through case, ™-type/bidi marks and repeated spaces, the offer rebuilt on the typed text; an empty answer remembered against that exact line |
| Live, WhatsApp | replies ignored the conversation | messages exposed as empty-valued static texts with the text in the description; nested date headings; the recipient only as a group label | description as a text fallback, text roles walked when they say nothing, container labels kept, buttons skipped, marks stripped |
| Live, Messages | a field went dead after three "refusals" | fuzzy matches, case-only differences and finishing a suggestion by hand all counted as typing past | only a real prefix completion typed past counts; empty line resets; generated guesses never count |

## Scorecards

| Run | Cases | Hit | In register | p50 | p95 | Reading |
|---|---|---|---|---|---|---|
| 1 — 2026-09-05, Release, Gemma 3 4B | 1 090 | 849 (78 %) | 901 (83 %) | 764 ms | 941 ms | chat 87 %, mail 92 %, terminal 85 %; notes 60 %, URL 63 %, SQL 74 %, code 77 %. Of 248 failures, 180 are the model answering with **nothing usable** (`first "-"`) — concentrated on commands, SQL and notes, the shapes a model wraps in backticks or a code fence, which the parser did not strip and the one-line stop cut at; 68 are wrong answers, half of them an address bar treated like a shell (`git` → `git commit -m`, `news.ycombinat` → `news.ycombinator`), which the register now names (`writesAddresses`). The CLI aborts at exit in MLX/Metal teardown (`std::mutex::lock` in a static destructor) after writing its JSON; harmless to the app, noted here so nobody chases it as a run failure. |

## How to run one cycle

1. `xcodebuild -scheme uttrflow-bakeoff -configuration Release -derivedDataPath .build/xcode … build`
   then `.build/xcode/Build/Products/Release/uttrflow-bakeoff complete --fixtures --json /tmp/fixtures.json`
   (never concurrently with `make app-dev`: they share `.build/xcode`).
2. `swift test` for the property suites.
3. `Scripts/e2e_predict.sh /tmp/e2e.md` while the operator is away.
4. Read the failures, fix the root cause with a test, `make verify` (hands-off: it wedges if the
   frontmost application changes while its window tests run), commit, `make app-dev`, relaunch.

# AI suggestions: reliability

The bar for AI suggestions (tab-to-complete): a suggestion that works once works every time, in
every application, and a silence always has a named reason (`Quieting.Reason`, logged by
`SuggestionCoordinator`; [predict.md](predict.md), "Why nothing is drawn"). This page is how the
feature is held to that bar — three kinds of test — and the behaviour of other applications and of
the model that the reader, the parser and the loop handle. Fixes go to the root cause with a test,
gated by `make verify`. What each application publishes is collected in
[compatibility.md](compatibility.md), which this page feeds for `Caret`, `Value`, `Completion` and
most of the notes; the model-only precision numbers are in [predict-precision.md](predict-precision.md).

## Three kinds of test

| Kind | Where | Cases | Proves |
|---|---|---|---|
| Generation fixtures | `Sources/uttrflow-bakeoff/Fixture*.swift` and `Catalogue*.swift`; `uttrflow-bakeoff complete --fixtures [--only p] [--limit n] [--json f] [--raw] [--failed-in run.json]` | about 1,150, generated from scenario × line × cut across terminal, SQL, URL and search, six kinds of chat, mail, notes, code, and a `robust/` set (™ and bidi marks, emoji, double spaces, finished sentences that must yield nothing, one- and two-character prefixes, 200-character lines) | The model, the prompt and the parser together: precision, coverage, register conformance (length band, no echo of context), latency p50/p95, in a Release build ([predict-context.md](predict-context.md)) |
| Seeded property tests | `Tests/UttrflowLocalModelTests/CompletionParsingPropertyTests.swift`, `PromptPropertyTests.swift`; `Tests/UttrflowPredictTests/SuggestionSessionPropertyTests.swift`, `RegisterPropertyTests.swift`, `RankingPropertyTests` in `RankingTests.swift`; `Tests/UttrflowContextTests/SurroundingsPropertyTests.swift`, `FocusedFieldSnapshotPropertyTests.swift` — each module has its own `Seeded` xorshift generator, so a failure names the seed that reproduces it | thousands, in seconds | The pure pipeline: every parsed result begins with the typed text, is distinct, never a prompt heading, never degenerate; the prompt budget holds, the line is never touched, trimming starts farthest from the line; the token budget stays in range; better evidence always wins; surroundings-walk invariants on random trees; random session scripts keep their promises and the quieting reason is the first rule; line and caret arithmetic on random Unicode |
| Idle-gated live end-to-end | `Scripts/e2e_predict.sh <report.md> [max-idle-wait-seconds] [scenario-regex]` | at least 25 scenarios in Terminal, TextEdit, an address bar and Finder search — never a chat, mail or notes, never Return | The whole system in real applications: ghost drawn, key accepted and read back, alternatives on ⌥↓, no stale ghost across a switch, and the loop alive after every scenario |

The live harness drives the Mac only after 45 s with no keyboard or mouse input (`IDLE_REQUIRED`),
aborts the moment the person returns, and waits while the screen is locked, since a locked Mac is
idle and the login window must never be typed into.

## How fields in other applications behave, and what handles each

| Where | What the application does | How Uttrflow handles it |
|---|---|---|
| Chrome, every Electron application | Answers the caret's glyph bounds with a zero-size rectangle at a false position | The selection's text-marker range still has real bounds (`AXBoundsForTextMarkerRange` of `AXSelectedTextMarkerRange`, a zero-width rectangle a line tall), asked before the one-pixel-field fallback (`CaretLocator`); when a collapsed caret at the value's end exposes paragraph direction, both fallback paths carry it into the anchor |
| Chrome | Answers every caret bound with a zero-size rectangle until its full Accessibility tree is on, and ignores `AXManualAccessibility`'s answer while applying it | A text field read with no caret turns the tree on once per process — `AXManualAccessibility` first, `AXEnhancedUserInterface` for Chromium browsers only, since elsewhere it slows window animations — and the value read back decides; the caret appears about two seconds later. Stopping suggestions turns off only what was turned on here. Every write is recorded before its answer, and a process whose attempt got no answer is asked again after 5 s, at most four times (`FullTreeSwitch`) |
| A field that refuses `AXSelectedTextRange` | Gives no range, so no caret | The selection is measured in text markers from the field's start, and the caret falls back to the marker bounds and the one-pixel field (`CaretLocator`) |
| A rich `contenteditable` editor in Chrome | Every glyph bound is zero-size, and the text-marker rectangle is the whole editor's frame | A marker rectangle is a caret only when it is one line: not the field's own frame, and no taller than three times the type size, or 72 pt where the field gives none (`CaretLocator.isLine`) |
| A browser code editor (Chrome, Safari) | Renders its own text and keeps an empty input, one to three pixels wide, parked at the caret for input methods | That input's frame is the caret; its line is read off the rendered row it sits on, chosen by height and by reaching the caret so a gutter number is never taken, split at the input's position, within 400 elements and 40 ms (`HiddenInputLine`). WebKit widens the input to about 1,000 pt, so an empty text area no taller than one bare line of type (18 pt) counts too (`HiddenInputLine.isStub`), and WebKit's highlighted runs are joined by parent and line band (`HiddenInputLine.sharesBand`) |
| A browser code editor while typing | The system-wide focused element is the word under the caret | The application's own focused element is asked |
| Any field with no caret to draw at | — | Quiet for `nowhereToDraw` before any candidate is asked for, never a silent hide |
| A wrapped paragraph in a browser | Has no line break within 256 characters of the caret | In prose too long to complete whole, the line starts at the earliest sentence start within 256 characters of the caret, and the sentences before it become the text before the line; a terminal, a one-line field and prose with no sentence end in reach keep the limit (`FocusedFieldSnapshot.lineStart`) |
| A browser window | Holds its own tab strip, other tabs' titles and infobars beside the page | The surroundings walk never climbs past the page (`Surroundings.pageRoles`) |
| A messaging application | Exposes each message as an empty-valued static text with the text in its description, nested date headings, and the recipient only as a group label | The description is a text fallback, text roles are walked when they say nothing, container labels are kept, buttons skipped, marks stripped |
| A messaging application | Labels every bubble "message, text, 3Septemberat6:41 PM, Received from …", the date glued without spaces | `Timestamps` drops a part that is only a time or a dated time in the calendar's own words from every label read and every completion; a completion is cut where it repeats a comma-separated part of a screen label (`CompletionText.shortestLabelPart`, 8 characters or more) exactly, and nowhere else, since a reply quotes the screen and a shell reuses a file name |
| A messaging application | An unresponsive accessibility server makes each call wait the system's seconds | 50 ms per-element messaging timeout, the walk on its own queue, a turn waits at most 200 ms for surroundings, and `TurnGate` leaves a turn behind after 10 s, so no single hang can end the loop |
| A chat composer | A half-typed or abandoned message looks like any other committed line | Only Return commits in a messaging application (`CommitPolicy.whereReturnSends`, tested in `Tests/UttrflowPredictCaptureTests/CommitPolicyTests.swift`) |
| A chat composer | The person's recent lines in the field span every conversation | Lines written in this very conversation come first (`PredictStore.recent`), and the window title scopes the corpus ([predict-precision.md](predict-precision.md)) |
| Terminal | Refuses an Accessibility write after taking the selection | A field that took the selection but refused the text gets the caret back before the next route runs |
| A field where the typed-past count rises | Fuzzy matches, case-only differences and finishing a suggestion by hand look like typing past | Only a real prefix completion typed past counts towards `Quieting.rejectionsBeforeSilence`; an empty line resets the count; generated guesses never count |

**Applications Accessibility cannot see into.** A Java/SWT SQL editor gives the reader nothing: the
focused element is an `SWTComposite` or an outline, most reads fail outright (`read=false`), and from
the background the application reports no focused element. No fix is possible on the reading side.
Accepting a completion into a browser code editor is not measured.

## How the model and parser behave, and what handles each

| What the model does | How Uttrflow handles it |
|---|---|
| Asked to repeat the line then continue it, a 4B model does neither reliably | The line up to its last word is written into the model's own turn and `TokenHealing` holds the first tokens to the typed last word ([predict-context.md](predict-context.md)) |
| Gemma's newline is a byte-fallback piece, `<0x0A>`, and its end-of-turn token is named in the configuration's ids, not its strings | Byte pieces read as the character they spell; the configuration's ending ids join the stop set; the character owed after the word must be visible, since a lone space token would satisfy "one more" |
| A word ended with a space gets lengthened (`docker image ` → `docker images`) | A word ended with a space is written exactly and followed by a space |
| A last word outside ASCII is spelt in byte pieces | Healing compares UTF-8 bytes, and a byte piece is the one byte it names |
| An indented code line is trimmed before its echo is matched | The echo is matched against the typed text without its indentation, which the answer keeps |
| A long line hits the token budget mid-line | A cut line is kept to its last whole word; a one-line pass that still hits the limit returns nothing rather than a fragment; the budget is a cap per line plus the echo's tokens, and `"\n"` is the stop string of a one-line pass |
| The model repeats the line without a ™ or bidi mark, or with spaces collapsed | The echo is matched through case, those marks and repeated spaces, and the offer is rebuilt on the typed text |
| The model answers nothing for a line | The empty answer is remembered against that exact line, so the next tick does not re-run it |
| A pass fails | `CandidateGenerating` throws, the coordinator logs `GENERATE failed` with the error's type and case, and the line is remembered so a tick never re-runs the failure; the bakeoff records `error: …` as the fixture's answer |
| The model takes a reply as complete and the healing forces one more token | A reply always gets a whole message's budget, a terse typical length is not quoted for one, and a new word of under `CompletionText.shortestNewWord` (3) characters is dropped |
| The alternatives arrive after the tick that redraws the line | `settled` keeps the list behind the same line, sieved to the alternatives that still extend what is typed |
| A whole word typed without a space (`git l`, `npm i`) | Healing allows both the exact token and a longer one, and the model's own guess decides; only the model can know whether the word is finished |

The `uttrflow-bakeoff` CLI can abort at exit in MLX/Metal teardown (`std::mutex::lock` in a static
destructor) after writing its JSON; it does not affect the app or the results.

## Scoring a run

A fixture whose expectation takes any continuation (`Determinacy.any`, the default for chat, notes
and mail) has nothing to check a hit against, so the report counts its hits as *unjudged*, prints
them apart, and reads precision over judged fixtures only. An address or search fixture expects
`<none>`, since the generator refuses there by design. `Scripts/predict_scorecard.py new.json
[old.json]` compares two runs. A terminal fixture stands on a substitute machine and records
`invented` lines ([predict-agent.md](predict-agent.md)).

## How to run one cycle

1. `xcodebuild -scheme uttrflow-bakeoff -configuration Release -derivedDataPath .build/xcode … build`,
   then `.build/xcode/Build/Products/Release/uttrflow-bakeoff complete --fixtures --json "$TMPDIR/fixtures.json"`.
   Never run it at the same time as `make app-dev`: both use `.build/xcode`.
2. `swift test` for the property suites.
3. `Scripts/e2e_predict.sh "$TMPDIR/e2e.md"` while nobody is using the Mac.
4. Read the failures, fix the root cause with a test, run `make verify` hands-off (it wedges if the
   frontmost application changes while its window tests run), commit, `make app-dev`, relaunch.

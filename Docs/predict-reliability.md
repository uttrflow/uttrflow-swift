# Reliability loop for tab-to-complete

The bar, set by the operator: if a suggestion worked once it must work every time, in every
application, and a silence must always have a reason. This document is the loop that holds
the feature to that bar and the running record of what it found. Fixes go to the root cause,
with tests, and each is gated by `make verify` before it is committed.

## Three kinds of test, and what each can prove

| Kind | Where | Cases | Proves |
|---|---|---|---|
| Generation fixtures | `Sources/uttrflow-bakeoff/Fixture*.swift`, `bakeoff complete --fixtures [--only p] [--limit n] [--json f]` | ~1 000 generated from scenario × line × cut templates across terminal, SQL, URL/search, six kinds of chat, mail, notes, code, and a `robust/` set built from live failures (™ and bidi marks, emoji, double spaces, finished sentences that must yield nothing, one- and two-character prefixes, 200-character lines) | the model, the prompt and the parser together: hit rate, register conformance (length band, no echo of context), latency p50/p95 — measured in a Release build |
| Generated property tests | `Tests/*` with a seeded generator, `swift test` | thousands, under ~5 s | the pure pipeline: parser invariants (every result begins with the typed text, distinct, never a prompt heading, never degenerate), prompt budget invariants, register invariants, surroundings-walk invariants on random trees, session sequencing (rejection counting, stale generations, accept clears), snapshot line/caret arithmetic on random Unicode |
| Idle-gated live E2E | `Scripts/e2e_predict.sh <report.md>` | ≥ 25 scenarios in Terminal, TextEdit, an address bar and Finder search — never a chat, mail or notes, never Return | the whole system in real applications: ghost drawn, key accepted and read back, alternatives on ↓, no stale ghost across a switch, and above all that the loop is alive after every scenario |

The live harness drives the Mac only after 45 s of no keyboard or mouse input and aborts the
moment the person returns, because it shares their keyboard.

## What the loop found and fixed (newest first)

| Found by | Symptom | Root cause | Fix |
|---|---|---|---|
| Live, WhatsApp | after one chat's suggestion, the next chat showed the old phrase at the old caret and nothing ever again | the surroundings walk blocked on an unresponsive accessibility server, each call waiting the system's seconds; the turn never returned and every keystroke queued behind it | 50 ms per-element messaging timeout; the walk on its own queue; a turn waits ≤ 200 ms for surroundings (`Deadline`); and a `TurnGate` that leaves a turn behind after 10 s so no single hang can end the loop |
| Live, WhatsApp | a line with ™ never got a suggestion; the GPU re-ran a fruitless pass every second | the model repeats the line without the mark, so its echo no longer began with what was typed and every answer was dropped; an empty answer was never remembered | echo matched through case, ™-type/bidi marks and repeated spaces, the offer rebuilt on the typed text; an empty answer remembered against that exact line |
| Live, WhatsApp | replies ignored the conversation | messages exposed as empty-valued static texts with the text in the description; nested date headings; the recipient only as a group label | description as a text fallback, text roles walked when they say nothing, container labels kept, buttons skipped, marks stripped |
| Live, Messages | a field went dead after three "refusals" | fuzzy matches, case-only differences and finishing a suggestion by hand all counted as typing past | only a real prefix completion typed past counts; empty line resets; generated guesses never count |

## How to run one cycle

1. `xcodebuild -scheme uttrflow-bakeoff -configuration Release -derivedDataPath .build/xcode … build`
   then `.build/xcode/Build/Products/Release/uttrflow-bakeoff complete --fixtures --json /tmp/fixtures.json`
   (never concurrently with `make app-dev`: they share `.build/xcode`).
2. `swift test` for the property suites.
3. `Scripts/e2e_predict.sh /tmp/e2e.md` while the operator is away.
4. Read the failures, fix the root cause with a test, `make verify` (hands-off: it wedges if the
   frontmost application changes while its window tests run), commit, `make app-dev`, relaunch.

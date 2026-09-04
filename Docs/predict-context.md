# Context-aware suggestions: register, surroundings and personal style

The goal: one generalised mechanism that makes a suggestion in a terminal read like a
command, in a chat like a reply this person would send, and in a document like the next
line of this document — with no list of applications anywhere. Latency and accuracy are
the two constraints every decision below is measured against.

## What existed before G1, and what the phases changed

| Piece | Where | Before G1 | Now |
|---|---|---|---|
| Field reading | `UttrflowContext/FocusedFieldReader+System.swift` | One AX read per turn: bundle id, app name, role, subrole, identifier, placeholder, description, document (URL or cwd), whole value, selection, caret rect, window rect, font size + family, secure, composing. Not read: the window title, any text outside the field. | The same read, plus a second, separately budgeted read of the focused window's title and the visible text around the field (`surroundings`), made only once a model pass is certain. |
| What the model is told | `UttrflowPredict/CandidateGeneration.swift` → `GenerationSituation` | `application`, `field`, `document`, `preceding` (≤400 chars of the field's own text before the caret's line). | Those four, plus `windowTitle`, `surroundings`, `recentLines` (the person's own lines here, newest first) and `isMultiline`. |
| The prompt | `UttrflowLocalModel/MLXCandidateScorer.swift`, `PromptBuilder.swift` | One fixed instruction + one user message; a new `ChatSession` per call prefilled the ~120-token instruction every time; `maxTokens` fixed at 128, temperature 0. | The instruction prefix is prefilled once at load into a KV cache and a pass feeds only the tokens past it (against a copy); `maxTokens` is `min(128, register.maxTokens × share)`, share 1 for the one line and 3 for the alternatives; temperature 0. |
| Memory | `UttrflowPredictStore/PredictStore.swift`, SQLite `surface`/`entry` | Per surface (bundle + role + locator + scope): every line the user typed there (with consent), counts, accepted/rejected, last used. Queried only by prefix and successor; no "the last N lines this person wrote here". | `recent(in:limit:)` exists: newest first, each text once, across every document of the field, self-sourced-only and superseded lines left out, over the `entry_recent` index. |
| Gates | `UttrflowPredict/Verifier.swift`, `Verification.swift` | Remembered lines pass attestation (environment index), nearest-neighbour correction, then the 4B plausibility floor (−6.0, ~100 ms per line). Generated lines are not scored. | Unchanged. |
| Timing | `Uttrflow/Suggestion/SuggestionCoordinator.swift` | 120 ms debounce, in-flight pass cancelled by the next key, last answer reused while the line still begins one of its lines, prose answered 400 ms after the last key. Generation of 3–4 lines ≈ 500–1 000 ms on the 4B; corpus path ≈ 1–150 ms. | The same debounce, cancellation and reuse; one line generated first and the alternatives fetched behind it; an empty answer remembered per line. Measured in the table below. |
| Register | — | `isProse` = multi-line field that is not a terminal was the only "kind" the code knew. Accept key by bundle-prefix table (terminals →, editors ⌥⇥) — key semantics, not context. | `Register` in `UttrflowPredict` computes five facts off the moment and turns them into prompt hints and a token budget; `isProse` and the accept-key table still do their own jobs. |

## The approach in one paragraph

Nothing about an application is hardcoded. Every turn that reaches the model carries
**three kinds of context read live**: the *surroundings* (window title and the text visible
around the field), the *field's own text* before the line, and the *user's own recent lines
on this surface*. From these, pure code derives a small set of **register hints** —
measurable facts, not app names: is the field one line or many, how long are this person's
lines here, is the visible text a back-and-forth of short turns, how much of it is symbols.
The prompt hands the model the raw context **and** the hints, and asks it to match register,
length and tone to them. The user's own lines are the personalisation: the model imitates
how this person writes *here*, and a chat reply is drafted against the last messages on
screen. Everything is bounded by a token budget so the added context costs tens of
milliseconds, not hundreds.

## How it works, step by step

1. **Read surroundings (once per pass, budgeted, uncached).** `FocusedFieldReader.surroundings`
   reads the focused window's `AXTitle` and walks outward from the field ring by ring — the
   thread beside a compose box before the sidebar — taking the text of labels, messages,
   headings, links, cells and other fields. Each ring is gathered nearest the field first and
   put back into reading order afterwards, so when a thread outruns the allowance it is the
   newest messages that survive, not the oldest. An element is read only where its frame meets
   the window's: no frame is trusted, zero size is hidden, off-window is pruned with its whole
   subtree; a label a container already carries is not read again from its children. Every
   element costs one Accessibility message — role, frame, value, title, description, children
   and parent in a single multiple-attribute call. `Surroundings.collect` stops at 60 ms,
   400 elements, 400 characters per element and 1 200 in all — the moment the characters are
   gathered, not a ring later — and returns what it has. Around it, every Accessibility call into the other application gives up
   after 50 ms (`elementTimeoutInSeconds`), the walk runs on its own queue, and the turn
   waits at most 200 ms for it (`Deadline`) before going on without it. There is no cache:
   the read happens once a pass is certain — after the debounce, never for a reused
   answer — so a cancelled burst never pays for it. In a chat this is the last few messages
   and who they are from; in Mail the quoted thread; in a browser the page heading and the
   field's label; in a terminal nothing (the value already holds the scrollback,
   `preceding`).
2. **Read the person (one SQL query).** `PredictStore.recent(in:limit:)` with a limit of 6 —
   the most recent distinct lines this user typed in this field, newest first, over the
   `entry_recent` index on `(surface_id, last_used)`. Only surfaces the user allowed
   learning from have any. In WhatsApp this is literally how they answer people; in a
   terminal their real commands; in Notes their own phrasing.
3. **Derive register hints (pure, tested, no model).** `Register.infer` computes from the
   situation and the typed text:
   - `isMultiline`: whether the field holds many lines (the prose role, or a value with a
     newline in it);
   - `typicalLength`: median length in characters of the user's recent lines here, or of
     the screen's lines when there are none and the screen is a conversation — the
     strongest verbosity signal there is;
   - `isConversational`: the screen shows at least three non-blank lines and at least 60 %
     of them are under 200 characters;
   - `symbolShare`: the share of visible characters that are neither letters nor digits,
     over `preceding`, the typed text and the recent lines (shell lines sit near 0.14,
     prose under 0.06; the line is 0.10);
   - `usesSentenceCase`: whether at least half the person's lines here start upper-case and
     end with sentence punctuation, or nothing when they have written nothing here yet.
   These are numbers and booleans, derived the same way in every application.
4. **Assemble the prompt under a budget.** `PromptBuilder` (in `UttrflowLocalModel`,
   deterministic, tested by character count) lays out: where the caret is and the hints →
   what is on screen around the field → the lines this person wrote here before →
   `preceding` → the line to finish. Hard cap 1 400 characters, about 400 tokens of Gemma's
   vocabulary; the fixed parts are paid for first, `preceding` and the recent lines get up
   to half of what remains each, and the surroundings take what is left — so the screen is
   trimmed first, then the oldest own lines, and the line never. `maxTokens` is
   `clamp(typicalLength / 2, 24, 96)` when the register knows a typical length, else 32
   for symbolic text, 48 for a conversation and 64 otherwise; the alternatives pass gets
   three times that, and every pass is capped at 128.
5. **Emotion and tone are the model's job, not a classifier's.** Given the last messages
   and this person's earlier replies, the 4B infers register; there is no sentiment
   module, because one would be a second hardcoded thing to be wrong. The evaluation set
   (below) is where we check it actually does.
6. **Keep the fixed part warm — done.** At load the instruction prefix — the exact token run
   two different prompts share, chat template included — is prefilled into a `[KVCache]`;
   each pass checks the real prompt opens with those tokens and feeds only the remainder
   against a copy of the cache. It saved ~60 ms per pass.

## Latency targets (from a pause to a drawn ghost)

| Path | Target | Lever |
|---|---|---|
| Remembered line, verified | 1–150 ms | unchanged |
| Reused model answer (typing on / backspace) | 0 ms | unchanged |
| New generation, command | ≤ 400 ms | register-sized `maxTokens`, warm instruction prefix |
| New generation, chat reply | ≤ 600 ms | `maxTokens` from the person's line length, surroundings ≤ 1 200 chars |
| New generation, paragraph | ≤ 900 ms | `maxTokens` ≤ 96 |
| Context reads (AX surroundings + SQL) | ≤ 200 ms wait, off the keystroke path | 60 ms walk budget, 50 ms per element, `Deadline` |

What each phase measured against these is the G2–G4 table below; the generation targets are
not yet met, and the table says where the remaining time goes. Measured by
`uttrflow-bakeoff complete --fixtures` over the fixture set and by `GENERATE … elapsed=` in
the live log; p50 and p95 reported per phase, regressions block the phase.

## Accuracy: how we know it works

- **Fixture set** (`Sources/uttrflow-bakeoff/Fixtures.swift` and `Catalogue*.swift`, on the
  types in `Sources/UttrflowEval/CompletionCase.swift` and `LineCut.swift`). `Fixture.all`
  is 29 hand-written fixtures followed by the catalogue, which is generated: a `Scenario`
  names one place lines are typed — its `GenerationSituation`, a length band, text that
  must never be echoed, `known` sibling lines — and lists the full lines typed there; each
  `Line` is cut at the scenario's `LineCut`s (`.afterWord(n)`, `.intoWord(n, by:)`,
  `.midWord(n)`, `.characters(n)`, `.whole`), and a `Determinacy` says how much of the rest
  the cut determines — the rest of the word or segment up to a separator set (`.command`,
  `.query`, `.address`, `.prose`, `.code`), the whole line, anything in register, or
  nothing at all for a finished line. A cut that leaves fewer than two typed characters,
  or nothing left to write, is not a case. Scenario × line × cut comes to roughly 1 090
  cases across terminal, SQL, URL, six kinds of chat, mail, notes, code and a `robust/` set
  built from live failures, named `category/scenario/line/cutN` so hit rates read per
  category. `bakeoff complete --fixtures [--only chat/] [--limit n] [--json f]` scores hit
  rate, register conformance and latency; run before and after every phase.
- **Live KPI**: `ACCEPT / GENERATE` ratio and "typed past" rate per application, straight
  from the existing log lines; the un-hardcoded design is judged by an application we never
  tested doing as well as one we did.
- **Guard rails already in place** stay: prompt-echo, loop and paragraph filters; ≥ 2 typed
  characters; secure fields never read; nothing generated is stored unless accepted.

## Privacy

Surroundings are read into memory for one pass and never written anywhere — not to the
corpus, not to the log (the log names lengths and the application, not the text). Recent
lines come only from surfaces the user allowed learning from, and `forget(bundleIdentifier:)`
already removes them. Everything runs on the Mac; no network is touched (`make verify`'s
offline audit still holds).

## Phases

| Phase | Deliverable | Files | Test |
|---|---|---|---|
| G1 Read — **done** | `Surroundings.collect` walks outward from the field, ring by ring (the thread beside a compose box before the sidebar), each ring nearest-first then restored to reading order so the newest messages survive the caps; frame-against-window visibility with off-window subtrees pruned; container labels not re-read from children; one multiple-attribute message per element; 60 ms and 400 elements, 400 chars per element, 1 200 in all, stopping the moment the characters are gathered; read only once a pass is certain, after the debounce, never on a reused answer. `PredictStore.recent(in:limit:)` newest first, distinct, across the field's documents, wrong lines left out. Both in `GenerationSituation` and the prompt; the log records lengths only. | `UttrflowContext/Surroundings.swift`, Reader+System (`AXElementTree`), PredictStore, CandidateGeneration, MLXCandidateScorer.prompt, Coordinator.situation | `SurroundingsTests` (fake tree: order, skips, caps, budget, allowance), `RecentLinesTests`, `PromptTests` |
| G2 Register — **done** | `Register.infer` reads five facts off the moment (single/multi-line, typical length of this person's lines here or of the screen's turns, conversation on screen, symbol share — shell lines sit near 0.14, prose under 0.06, so the line is 0.10 — and sentence case), turns them into hints the prompt carries and a token budget `clamp(typical/2, 24, 96)`; `PromptBuilder` capped the message near 2 400 characters at G2, since halved to 1 400 (the last row of the table below), trimming the screen first, then the oldest own lines, the line never. | `UttrflowPredict/Register.swift`, `UttrflowLocalModel/PromptBuilder.swift`, MLXCandidateScorer | `RegisterTests`, `PromptTests` |
| G3 Warm — **done** | Two changes, each measured. **One line first**: the pass asks for the single most likely completion and ends at its newline; the alternatives are fetched in a second pass once that line is on screen, which a keystroke cancels, so ↓ still opens a list. **Warm instructions**: at load the instruction prefix — the exact token run two different prompts share, template included — is prefilled into a KV-cache; each pass checks the real prompt opens with it and feeds only the remainder against a copy. | MLXCandidateScorer, SuggestionSession.expandGenerated, Coordinator.generate | fixtures before/after, table below |
| G4 Prove — **done** | 29 fixtures across terminal, SQL, address bar, four kinds of chat, mail, notes, code and search, each with surroundings, the person's lines, preceding text, the typed prefix, acceptable continuations, a length band and text that must not be echoed; `bakeoff complete --fixtures [--only chat/]` prints per-fixture hit, register conformance and latency, then per-category rates and p50/p95. The live matrix is the user's own testing, read off `CONTEXT`/`GENERATE`/`ACCEPT` in the log. | `uttrflow-bakeoff/Fixtures.swift`, `Complete.swift` | the table below |

## What G2–G4 measured (Gemma 3 4B QAT 4-bit, 29 fixtures, Apple silicon)

| Build | Hit | In register | p50 | p95 | What changed |
|---|---|---|---|---|---|
| G2 baseline, Debug bakeoff | 27/29 | 28/29 | 944 ms | 1 340 ms | register hints, budgeted prompt, four lines per pass |
| + one line first | 27/29 | 28/29 | 895 ms | 1 054 ms | pass ends at the first newline |
| + warm instructions | 27/29 | 28/29 | 835 ms | 965 ms | instruction prefix read once; every first line identical |
| same code, **Release** bakeoff | 27/29 | 28/29 | 677 ms | 819 ms | the app is a Release build (`bundle.sh`), so this is what the person sees |
| + prompt budget 2 400 → 1 400 chars, Release | 27/29 | 28/29 | **666 ms** | **787 ms** | every first line identical; the fixtures' contexts rarely reached the old cap, a live chat thread does |

The two misses are stable across every build: `sql/update` (`UPDATE users SET ` → nothing usable) and
`url/git` (`git` in an address bar → `git commit -m`, a plausible reading of an ambiguous prefix). Every
chat, mail, note and terminal fixture hits, and no fixture echoes its context.

**What the numbers say about where the time goes.** Cutting generation to one line saved ~50 ms at p50 and
~290 ms at p95; caching the ~220-token instruction prefix saved ~60 ms; the Release build saved ~160 ms;
halving the prompt budget saved ~10 ms at p50 and ~30 ms at p95 on fixtures whose context was small to
begin with. What is left is a floor near 500 ms that even a near-empty prompt pays (`search/inv`, 507 ms):
a short prefill and eight to twelve decode steps of a 4B model at a few dozen tokens a second. Neither
context nor instructions move that floor. The lever that does is **speculative decoding** — the 1B Gemma
drafting tokens the 4B verifies in one pass, which `ChatSession`/`generate` already support through
`SpeculativeDecodingConfig` — and after it a smaller verifier. Targets (command ≤ 400 ms, reply ≤ 600 ms)
are not yet met; the p95 of 787 ms is within the "1–2 s is acceptable for now" the operator set for this
stage.

## Not doing, and why

- No per-application prompts, kinds or tables: the hints are computed, the model decides.
- No sentiment classifier: the transcript plus the person's own replies carry the tone.
- No scoring of generated lines with the verifier: 3 × 100 ms would eat the latency win;
  the fixture set is where quality is checked instead.
- No reading beyond the focused window: other windows are someone else's context.

# Context-aware suggestions: register, surroundings and personal style

The goal: one generalised mechanism that makes a suggestion in a terminal read like a
command, in a chat like a reply this person would send, and in a document like the next
line of this document — with no list of applications anywhere. Latency and accuracy are
the two constraints every decision below is measured against.

## What exists today

| Piece | Where | What it does now |
|---|---|---|
| Field reading | `UttrflowContext/FocusedFieldReader+System.swift` | One AX read per turn: bundle id, app name, role, subrole, identifier, placeholder, description, document (URL or cwd), whole value, selection, caret rect, window rect, font size + family, secure, composing. **Not read:** the window title, any text outside the focused field. |
| What the model is told | `UttrflowPredict/CandidateGeneration.swift` → `GenerationSituation` | `application`, `field`, `document`, `preceding` (≤400 chars of the field's own text before the caret's line). |
| The prompt | `UttrflowLocalModel/MLXCandidateScorer.swift` | One fixed instruction ("autocomplete engine … infer what is being typed … up to four lines") + one user message. New `ChatSession` per call: the ~120-token instruction is prefilled every time. `maxTokens` fixed at 128, temperature 0. |
| Memory | `UttrflowPredictStore/PredictStore.swift`, SQLite `surface`/`entry` | Per surface (bundle + role + locator + scope): every line the user typed there (with consent), counts, accepted/rejected, last used. Queried only by **prefix** (`candidates(for:matching:)`) and successor (`successors`). **Not available:** "the last N lines this person wrote here". |
| Gates | `UttrflowPredict/Verifier.swift`, `Verification.swift` | Remembered lines pass attestation (environment index), nearest-neighbour correction, then the 4B plausibility floor (−6.0, ~100 ms per line). Generated lines are **not** scored. |
| Timing | `Uttrflow/Suggestion/SuggestionCoordinator.swift` | 120 ms debounce, in-flight pass cancelled by the next key, last answer reused while the line still begins one of its lines, prose answered 400 ms after the last key. Generation of 3–4 lines ≈ 500–1000 ms on the 4B; corpus path ≈ 1–150 ms. |
| Quieting | `UttrflowPredict/PredictionContext.swift` | `isProse` = multi-line field that is not a terminal; the only "kind" the code knows. Accept key by bundle-prefix table (terminals →, editors ⌥⇥) — key semantics, not context. |

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

1. **Read surroundings (once per turn, budgeted).** `FocusedFieldReader` gains
   `surroundings(of field)`: the focused window's `AXTitle`, and the visible text runs
   (`AXStaticText`, text cells, other text areas) in the focused window, taken in
   reading order, nearest the field last, capped at 1 200 characters and **60 ms** of AX
   time — past the budget it returns what it has. Cached per (window, field value hash),
   so a tick re-read costs nothing. In a chat this is the last few messages and who they
   are from; in Mail the quoted thread; in a browser the page heading and the field's
   label; in a terminal nothing (the value already holds the scrollback, `preceding`).
2. **Read the person (one SQL query).** `PredictStore.recent(in surface, limit: 6)` — the
   most recent distinct lines this user typed on this surface, newest first (cheap: an
   index on `surface_id, last_used`). Only surfaces the user allowed learning from have
   any. In WhatsApp this is literally how they answer people; in a terminal their real
   commands; in Notes their own phrasing.
3. **Derive register hints (pure, tested, no model).** `Register` in `UttrflowPredict`
   computes from the snapshot + surroundings + recent lines:
   - `shape`: single-line field / multi-line field (from role and whether the value holds newlines);
   - `typicalLength`: median length of the user's recent lines here (bytes), or of the
     visible runs when there are none — the strongest verbosity signal there is;
   - `conversational`: visible runs alternate short (< 200 chars) turns and end near the field;
   - `symbolShare`: share of non-letter characters in `preceding` + recent lines (commands,
     SQL and code sit high; prose low);
   - `sentenceCase`: whether the person's lines here start upper-case and end with
     punctuation (formal) or not (casual).
   These are numbers and booleans, derived the same way in every application.
4. **Assemble the prompt under a budget.** `PromptBuilder` (in `UttrflowLocalModel`,
   deterministic, tested by character count) lays out, in order: fixed instructions →
   surroundings (trimmed to fit) → "how this person writes here" (the recent lines) →
   `preceding` → the line to finish. Hard cap **≈ 700 tokens** total; when over, trim
   surroundings first, then recent lines, never the line itself. The instructions say:
   *match the length, tone and register of the person's own lines and of what is on
   screen; a reply answers the last message; never continue the earlier text, only the
   last line.* `maxTokens` becomes adaptive: `clamp(2 × typicalLength / 4, 16, 96)`
   tokens — a command gets ~20, a chat reply ~40, a paragraph ~90 — which is the single
   biggest latency lever besides the debounce.
5. **Emotion and tone are the model's job, not a classifier's.** Given the last messages
   and this person's earlier replies, the 4B infers register; there is no sentiment
   module, because one would be a second hardcoded thing to be wrong. The evaluation set
   (below) is where we check it actually does.
6. **Keep the fixed part warm.** The instruction block is identical every call; MLX
   `ChatSession` accepts a pre-computed `[KVCache]` for a prompt prefix. Prefill it once
   at model load and reuse it, saving the ~100–150 ms the instructions cost per pass today.

## Latency budget (targets, from a pause to a drawn ghost)

| Path | Today | Target | How |
|---|---|---|---|
| Remembered line, verified | 1–150 ms | same | unchanged |
| Reused model answer (typing on / backspace) | 0 ms | 0 ms | unchanged |
| New generation, command | 500–700 ms | ≤ 400 ms | adaptive `maxTokens` ≈ 20, cached instruction prefix |
| New generation, chat reply | 600–1 000 ms | ≤ 600 ms | `maxTokens` ≈ 40, surroundings ≤ 1 200 chars |
| New generation, paragraph | ~1 000 ms | ≤ 900 ms | `maxTokens` ≤ 96 |
| Context reads (AX surroundings + SQL) | — | ≤ 60 ms, off the keystroke path | budget + cache |

Measured by `uttrflow-bakeoff complete` over the fixture set and by `GENERATE … elapsed=`
in the live log; p50 and p95 reported per phase, regressions block the phase.

## Accuracy: how we know it works

- **Fixture set** (`Tests/Fixtures/situations/*.json`): ~40 situations across a
  terminal, SQL editor, URL bar, chat with a visible thread, mail reply, note, document —
  each with surroundings, recent lines, preceding text, the typed prefix and 1–3 acceptable
  continuations plus a register expectation (length band, ends-with-punctuation, no
  earlier-text continuation). `bakeoff complete --fixture` scores hit rate and register
  conformance; run before and after every phase.
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
| G1 Read — **done** | `Surroundings.collect` walks outward from the field, ring by ring (the thread beside a compose box before the sidebar), 60 ms and 400 elements, 400 chars per element, 1 200 in all, nearest last; read only once a pass is certain, after the debounce, never on a reused answer. `PredictStore.recent(in:limit:)` newest first, distinct, across the field's documents, wrong lines left out. Both in `GenerationSituation` and the prompt; the log records lengths only. | `UttrflowContext/Surroundings.swift`, Reader+System (`AXElementTree`), PredictStore, CandidateGeneration, MLXCandidateScorer.prompt, Coordinator.situation | `SurroundingsTests` (fake tree: order, skips, caps, budget, allowance), `RecentLinesTests`, `PromptTests` |
| G2 Register | `Register` hints, `PromptBuilder` with budget and adaptive `maxTokens`, new instruction text | UttrflowPredict/Register.swift, UttrflowLocalModel/PromptBuilder.swift, MLXCandidateScorer | pure unit tests for every hint and the trimming order; fixture hit-rate before/after |
| G3 Warm | Instruction KV-cache prefilled at load and reused | MLXCandidateScorer | bakeoff p50 per fixture before/after |
| G4 Prove | Fixture set, `bakeoff complete --fixture`, live matrix (Terminal, DBeaver, Notes, Messages, WhatsApp, Chrome, Mail, Slack) | bakeoff, Tests/Fixtures | hit rate ≥ 0.6 on commands, ≥ 0.4 on replies; p95 within budget |

## Not doing, and why

- No per-application prompts, kinds or tables: the hints are computed, the model decides.
- No sentiment classifier: the transcript plus the person's own replies carry the tone.
- No scoring of generated lines with the verifier: 3 × 100 ms would eat the latency win;
  the fixture set is where quality is checked instead.
- No reading beyond the focused window: other windows are someone else's context.

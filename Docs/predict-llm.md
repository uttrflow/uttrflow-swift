# AI suggestions: the local model

AI suggestions (tab-to-complete) use one local language model, Gemma 3 4B (4-bit QAT, run with
MLX), in two roles: it judges remembered lines in context, and it writes a line where the corpus and
the machine have nothing. `MLXCandidateScorer` in `Sources/UttrflowLocalModel/MLXCandidateScorer.swift`
implements both `CandidateScoring` and `CandidateGenerating`; `UttrflowApp`
(`Sources/Uttrflow/UttrflowApp.swift`) builds it and hands it to the suggestion loop. Dictation keeps
its own speech and clean-up engines, so a suggestion's speed is never traded for dictation quality.
The loop that calls the model is [predict.md](predict.md); what the model is shown is
[predict-context.md](predict-context.md); when its line is withheld is
[predict-precision.md](predict-precision.md).

## Two roles

- **Judging what this person types.** The corpus holds this user's own commands and phrasings,
  recalled by prefix and by edit distance. Those candidates are ranked by evidence and then judged
  by the model in context: gate 2 of `Verifier` scores each remembered line's log-likelihood
  against `Verification.plausibilityFloor`. A line the machine attests (gate 1) is never sent to the
  model, and a model that is not loaded yet is no objection, so the statistical gates answer alone
  until it is. A habit the model judges wrong here is not shown, however often it was typed.
- **Writing a line.** When the corpus and the machine have nothing, the model writes the
  continuation itself — `git c` in a shell offers `checkout`, then `commit` and `cherry-pick` behind
  it. A generated line is scored by the pass that wrote it and drawn only over
  `Verification.certainFloor`, or `choiceFloor` in a list.

Context decides both: where the caret is (the application and what kind of field), what surrounds
it, this person's own lines there, and in a terminal the working directory and what is in it.

## How the model is held

`UttrflowApp` wraps one `MLXCandidateScorer(model: .gemma3)`:

| Wrapper | What it does |
|---|---|
| `IdleReleasingModel` | Lets the weights go after `IdleRelease.window(physicalMemory:)` unasked — 600 s on a Mac with at least 16 GB, 180 s with less — and reloads them from disk on the next query |
| `DiscretionaryModel`, `DiscretionaryGenerator` | Run a pass only when `EnergyConditions.current().allowsDiscretionaryWork` (not Low Power Mode, no thermal pressure) and `DictationInProgress.shared.isDictating` is false |

The weights (about 3 GB) are fetched only once the feature is first turned on, never at launch
(`AppDelegate.prepareTheModelIfNeeded`), and the AI suggestions screen says what the model is doing
while it downloads, loads or is set aside for memory.

A pass lands well under a second after a pause: p50 666 ms and p95 787 ms in a Release build over
the 29 hand-written fixtures ([predict-context.md](predict-context.md)). What keeps it there: a
120 ms debounce, one line first with the alternatives fetched behind it, the instruction prefix and
the previous prompt kept in KV caches, a 160-token budget for the context around the line, and the
line itself up to its last word written into the model's own turn so the answer can only continue
it. In a terminal the machine speaks before the model: where the next word has a closed set of
values, `TokenChoice` holds the decode to one of them ([predict-agent.md](predict-agent.md)).

## Apple's on-device model is not used for completion

Apple's Foundation Models framework runs the dictation clean-up ([bakeoff.md](bakeoff.md)), so it was
measured for completion too. `AppleCandidateGenerator` gives it the identical instructions, prompt,
parser and copy cut the local model gets, and `uttrflow-bakeoff complete --fixtures --model apple`
holds it to the same catalogue (macOS 26, Apple Intelligence on):

| Model | Hit | In register | p50 | p95 | Empty | Errors |
|---|---|---|---|---|---|---|
| Gemma 3 4B (4-bit, MLX) | 1 009 / 1 090 (93 %) | 98 % | 752 ms | 883 ms | 2 | 0 |
| Apple on-device, strict | 453 / 1 100 (41 %) | 44 % | 472 ms | 813 ms | 546 | 65 |
| Apple on-device, most generous reading | 579 / 1 100 (53 %) | — | 471 ms | — | 419 | 65 |

The Apple rows include ten `robust/chat-labels` cases the Gemma row does not. The generous reading
treats an answer that did not repeat the line as its continuation, but only where a word boundary
says how the two join (a space on either side, opening punctuation, or a closing quote with an
unmatched opener in the typed text); letters against letters are not joined, since "busy nahi" and
"hoon bolo" would read as one word. Apple's misses,
read raw: 137 echo the line and stop (`git c` → `git c`), 350 answer something unrelated or drop the
echo (`SELECT * FROM u` → `LIMIT 10;`), 34 fail to fill the structured answer, and 31 are guardrail
refusals on ordinary chat text. Both generators now read candidate replies through the same
continuation filter: echo-less Apple answers must parse as an extension after joining, and refusal,
apology and instruction-meta openings in the added words are rejected. The opening table is
`CompletionText.rejectedOpenings` and its entries are covered by a table-driven test. By category,
strict: chat 51 %, terminal 50 %, url 45 %, mail 37 %, notes 26 %, sql 24 %, code 20 %.

The gap is the framework's shape, not the model's size. It returns text: there is no way to write
the line into the model's turn, hold its first tokens to the typed word, stop at a newline, read a
token's probability, or keep the instructions warm across passes — the five controls that take the
local model from 78 % to 93 % on this catalogue. It also refuses content by policy and runs only
with Apple Intelligence on, on Apple silicon, on macOS 26. What it saves is a 3 GB download, 4 GB of
memory and 280 ms at the median, which is why it stays the clean-up engine, where a whole sentence
is rewritten and none of those controls are needed.

## Where the seams are

- `SuggestionCoordinator` builds its `Verifier` with the `CandidateScoring` the app hands it; the
  race between the model and `Verification.budgetInMilliseconds` (7,000 ms) is `Verifier.raced`.
- `SuggestionCoordinator.candidates(for:)` asks the corpus, then the environment; when both are
  empty and the generator is ready, `generate` asks the model.
- `SuggestionSession.turnBudgetInMilliseconds` (8,000 ms) is timed from after the field read, and
  `resolve` and `resolveGenerated` drop what arrives later. A late answer is drawn against a fresh
  read of the field.

## Where the weights come from

`AnonymousHub.client()` is the only hub client this app builds. It names two things a bare
`HubClient()` would decide for itself:

- **`tokenProvider: .none`.** The default reads `HF_TOKEN`, `HUGGING_FACE_HUB_TOKEN`,
  `$HF_TOKEN_PATH`, `$HF_HOME/token`, `~/.cache/huggingface/token` and `~/.huggingface/token`.
  Uttrflow is not sandboxed, so the last two are the person's own files, and a personal token would
  be attached to this app's downloads. Uttrflow fetches public weights and has no account on the
  model host.
- **`host: HubClient.defaultHost`.** The default follows `HF_ENDPOINT`.

Each model in `LocalModel.candidates` names the commit its weights are fetched at, and
`ModelConfiguration(id:revision:)` uses it, so two installs a day apart run the same model.

Once that pinned snapshot is complete, `LocalModel` prunes older snapshots for the same model and
deletes only blobs no snapshot still references. An incomplete download never triggers pruning, and
an unreadable cache scan leaves every older snapshot in place.
Pruning assumes one Uttrflow instance exclusively manages the Hugging Face cache; it does not
coordinate with other processes using that cache.

**To bump a model revision**, take the repository's current commit:

```bash
curl -s https://huggingface.co/api/models/<repository> | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])'
```

Put it in `LocalModel`, and say in the pull request what changed. `Scripts/offline_audit.sh` fails
on a bare `HubClient()`, on a token provider other than `.none`, on `HF_ENDPOINT` or `detectHost`,
and on a model fetched from a branch (`revision: "main"`, `resolve/main/`).

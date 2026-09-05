# Tab-to-complete: the LLM-arbitrated design

The suggestion is not a lookup. The local model has a hand in every suggestion the user
sees, in one of two ways:

- **Localization (personalization).** The corpus holds what *this* user types — their commands,
  their phrasings — recalled by prefix and by edit distance, and (later) by meaning. Those local
  candidates are ranked by evidence and then judged by the model *in context*, once it is
  loaded: gate 2 of `Verifier` scores each remembered line's log-likelihood against
  `plausibilityFloor`, and a model still loading is no objection, so the statistical gates
  answer alone until then. A habit the model judges wrong in this situation is not shown,
  however often it was typed. Correctness outranks habit.
- **Generation.** When the corpus and the machine have nothing for the situation, the model
  writes the continuation itself — `git c` in a shell offers `checkout`, then `commit`,
  `cherry-pick` behind it. The corpus never held these; the model knows them. A generated
  line is the model's own and is not scored again.

Context decides both. The model is told where the caret is (the application, and what kind of
field — a shell, a SQL editor, a URL bar, prose), what surrounds the caret (the line, the text
before and after it, nearby lines), and the ephemeral situation (a terminal's working directory
and git branch). The same context that makes a local candidate right or wrong makes a generated
one fit or not.

## Working first, fast later

A 1–4B model cannot answer inside a keystroke. For now that is accepted: a suggestion may land
well under a second after a pause — measured at p50 666 ms and p95 787 ms in a Release build
over the fixture set, the table in [predict-context.md](predict-context.md) — and the model
that serves suggestions is the one dictation already uses. What is done so far — a 120 ms
debounce, one line first, a warm instruction prefix, a 1 400-character prompt budget, and the
line itself up to its last word written into the model's own turn so the answer can only
continue it and no echo is paid for — is also there. In a terminal the machine now speaks before the
model ([predict-agent.md](predict-agent.md)): where the next word is a directory, a file, a branch
or a program's verb, the pass is told the values that exist and `TokenChoice` holds the decode to
one of them, so the model ranks what is there and cannot write what is not; where nothing there
begins as the word was typed, no pass runs and the turn is quiet for `notOnThisMachine`. A smaller model dedicated to suggestions, speculative decoding and the thermal
and battery guards are still to come and do not gate a working system. Dictation keeps its
own model so its quality is never traded for the speed of a suggestion.

## Apple's on-device model, measured for completion

Apple's Foundation Models framework runs the dictation clean-up (`Docs/bakeoff.md`), so the
question of using it for tab-to-complete too was measured rather than argued.
`AppleCandidateGenerator` gives Apple's model the identical instructions, prompt, parser and
copy-cut the local model gets, and `uttrflow-bakeoff complete --fixtures --model apple` holds
it to the same 1 090-case catalogue (plus the ten chat-label cases), 2026-09-05, macOS 26,
Apple Intelligence on.

| Model | Hit | In register | p50 | p95 | Empty | Errors |
|---|---|---|---|---|---|---|
| Gemma 3 4B (4-bit, MLX), run 4 | 1 009 / 1 090 (93 %) | 98 % | 752 ms | 883 ms | 2 | 0 |
| Apple on-device, strict | 453 / 1 100 (41 %) | 44 % | 472 ms | 813 ms | 546 | 65 |
| Apple on-device, most generous reading | 579 / 1 100 (53 %) | — | 471 ms | — | 419 | 65 |

The generous reading treats an answer that did not repeat the line as its continuation, which a
text-only model cannot be held to any other way — but only where a word boundary says how the two
join: a space on either side, or punctuation opening the answer. Letters against letters are not
joined, since "busy nahi" and "hoon bolo" would read as one word, and an earlier reading that
glued them counted such lines as hits (63 %). The Apple rows cover 1 100 cases because the ten
`robust/chat-labels` cases were added the same morning; Gemma's run 4 predates them. Apple's misses, read raw: 137 echo the line and
stop (`git c` → `git c`), 350 answer something unrelated or drop the echo (`SELECT * FROM u` →
`LIMIT 10;`), 34 fail to fill the structured answer, and 31 are guardrail refusals on ordinary
chat text. By category, strict: chat 51 %, terminal 50 %, url 45 %, mail 37 %, notes 26 %,
sql 24 %, code 20 %.

What the numbers come from is the framework's shape, not the model's size. The framework gives
back text: there is no way to write the line into the model's turn, hold its first tokens to the
typed word, stop at a newline, read a token's probability, or keep the instructions warm across
passes — the five things that took the local model from 78 % to 93 % on this catalogue. It also
refuses content by policy, is available only with Apple Intelligence switched on, on Apple
silicon, on macOS 26, and declares fifteen languages. Where it wins is what it does not cost:
no 3 GB download, no 4 GB of memory, and a pass 280 ms faster at the median — which is why it
stays the clean-up engine, where a whole sentence is rewritten and none of those controls are
needed. A completion is a different job, and the local model keeps it.

## Phases

Phases A to C are done and are described as built in [predict-context.md](predict-context.md);
what follows is what each set out to do.

- **A — Context & de-fragmentation (no model) — done.** The text before the caret's line, the
  window title and the visible text around the field are read and handed to the model as one
  `GenerationSituation`; no dialect is classified — the register is computed from measurable
  facts and the model infers the rest. The corpus answers from every document of the same field,
  so a phrase learned in one folder is found in the next.
- **B — Model in the app, validating — done.** The model is linked into the `xcodebuild`-built app
  behind the `CandidateScoring` and `CandidateGenerating` protocols the tests already use
  (`UttrflowApp` builds one `MLXCandidateScorer` and hands it over as both), loaded at launch, and
  wired as gate 2 of the `Verifier`. The turn budget is 8 000 ms and the verification budget
  7 000 ms, so a slow answer is drawn rather than dropped.
- **C — Generation — done.** When the corpus and the machine are empty the model writes the single
  most likely line, which is drawn inline; the alternatives are fetched behind it and open on ↓.
- **D — Embeddings.** Store a vector per entry (a new column, brute-force cosine over the few
  thousand entries a surface holds) so a phrase close in meaning is recalled, not only one close in
  spelling. (The earlier decision against embeddings was about the dictation dictionary, a
  different problem; it does not bind here.)
- **E — Optimisation.** A smaller suggestion model, speculative decoding and the thermal/battery
  guards — measured against a go/no-go. The debounce, the warm prefix and the prompt budget are
  already in.

## The seams (where the code changed)

- Validate every candidate: `SuggestionCoordinator` builds its `Verifier` with the
  `CandidateScoring` the app hands it, and the racing and budget machinery in `Verifier.raced`
  runs against `Verification.budgetInMilliseconds` (7 000 ms).
- Generate on empty: `SuggestionCoordinator.candidates(for:)` asks the corpus, then the
  environment; when both are empty and the generator is ready, `generate` asks the model.
- Budget: `SuggestionSession.turnBudgetInMilliseconds` is 8 000 ms, timed from after the field
  read, and both `resolve` and `resolveGenerated` drop what arrives later. A late answer is drawn
  against a fresh read of the field, so a caret that moved is followed and a line that changed is
  not written over.

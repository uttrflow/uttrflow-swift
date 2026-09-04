# Tab-to-complete: the LLM-arbitrated design

The suggestion is not a lookup. Every suggestion the user sees has passed through the local
model, in one of two ways:

- **Localization (personalization).** The corpus holds what *this* user types — their commands,
  their phrasings — recalled by prefix, by edit distance, and (later) by meaning. Those local
  candidates are handed to the model, which validates them *in context* and ranks them. A habit
  the model judges wrong in this situation (a mistyped `git comit`) is not shown, however often it
  was typed. Correctness outranks habit.
- **Generation.** When the corpus has nothing for the situation, the model generates the
  continuation itself — `git c` in a shell offers `checkout`, `commit`, `cherry-pick`, ranked by
  how likely each is here. The corpus never held these; the model knows them.

Context decides both. The model is told where the caret is (the application, and what kind of
field — a shell, a SQL editor, a URL bar, prose), what surrounds the caret (the line, the text
before and after it, nearby lines), and the ephemeral situation (a terminal's working directory
and git branch). The same context that makes a local candidate right or wrong makes a generated
one fit or not.

## Working first, fast later

A 1–4B model cannot answer inside a keystroke. For now that is accepted: a suggestion may land a
second or two after a pause, and the model that serves suggestions is the one dictation already
uses. Optimisation — a smaller model dedicated to suggestions, batching, debouncing, caching — is
a later phase and does not gate a working system. Dictation keeps its own model so its quality is
never traded for the speed of a suggestion.

## Phases

- **A — Context & de-fragmentation (no model).** Expose the text after the caret and the lines
  around it (already read, never surfaced); classify the surface into a dialect (shell / URL /
  SQL / code / prose) from the application, the field role, and the document; assemble one
  `PredictionContext` the model will read. Stop keying the corpus so tightly to one document's
  folder that a phrase learned in one file is invisible in the next — scope becomes a ranking and
  context signal, not a wall.
- **B — Model in the app, validating.** Link the model into the shipping app without breaking the
  SPM gates (it needs the Metal toolchain the command-line build cannot run, so the concrete model
  is injected only in the `xcodebuild`-built app, behind a protocol the tests already use). Load it
  warm at launch; wire the scorer as the validation gate; fix its two faults (it tokenises the
  context twice and cannot truly cancel a forward pass); lift the 40 ms turn budget off the model
  path so a slow answer is drawn, not dropped.
- **C — Generation.** Produce ranked continuations with their probabilities from the model, for
  when the corpus is empty; draw the leader inline and the rest in the below-caret list.
- **D — Embeddings.** Store a vector per entry (a new column, brute-force cosine over the few
  thousand entries a surface holds) so a phrase close in meaning is recalled, not only one close in
  spelling. (The earlier decision against embeddings was about the dictation dictionary, a
  different problem; it does not bind here.)
- **E — Optimisation.** A smaller suggestion model, batching, debouncing to a typing pause,
  caching, and the thermal/battery guards — measured against a go/no-go.

## The seams (where the code changes)

- Validate every candidate: hand a real `CandidateScoring` to the `Verifier`
  (`SuggestionCoordinator` builds it with `scoring: nil` today); the racing and budget machinery is
  already there, dormant.
- Generate on empty: where `candidates()` merges the corpus and environment answers and returns
  them, synthesise from the model when that merge is empty.
- Budget: the 40 ms caps that drop a late answer live in `SuggestionSession.resolve`; the model
  path needs its own, longer budget or an async refinement that redraws when the model returns.

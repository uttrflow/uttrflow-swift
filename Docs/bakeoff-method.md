# How the bake-off measures, and why each row is there

`uttrflow-bakeoff` (`Sources/uttrflow-bakeoff/`) scores every candidate clean-up engine against
`EvaluationCorpus`, and its subcommands measure memory, processor time and leaks. The measurement
logic lives in `UttrflowEval` (`Sources/UttrflowEval/`), where tests reach it; the command holds
the wiring and the tables. Results are in [`bakeoff.md`](bakeoff.md) and
[`performance.md`](performance.md).

## A separate executable

It links MLX, which needs Metal shaders that Swift Package Manager's command line cannot build,
so it is not a subcommand of `uttrflow-dev`. `make bakeoff` builds it with `xcodebuild` (Debug)
and runs it with `ARGS`.

Each candidate's result is written to disk as it finishes, so a model that stalls mid-download
costs only its own run. Two candidates can share a family name — Gemma 3 at 1B and 4B — so the
stored file is keyed by size as well, and the report prints the size.

Every result carries a run header: run id and date, prompt version, corpus fingerprint and case
count, the source commit the rules and guard were built from (`+dirty` when the tree had edits),
the macOS build, chip and memory, and whether context was withheld. Results are written under
`runs/<run id>/`, so a second run of one engine adds a file rather than replacing one;
`--summarise` reports the latest run of each candidate.

| flag | what it does |
|---|---|
| `--models a,b` | only these local candidates (`gemma3Small`, `llama32`, `qwen3`, `ministral3`, `gemma3`, or a repository name) |
| `--baselines-only` | rules, Apple's model and the shipping router, no local models |
| `--summarise` | prints what is already stored and stops |
| `--verbose` | prints every failed case, not only the summary |
| `--sample` | prints what a model writes, before any scoring |
| `--ignore-context` | withholds everything on screen |
| `--results-path` | where results are kept (default `.bakeoff`) |
| `--against <file>` | compares each measured candidate with a saved result and fails on a regression; output goes to a `-compared` sibling |
| `--allow-difference a,b` | with `--against`, lets the named header fields differ (`corpus`, `system`, `hardware`, `context`) |
| `--ledger <path>` | writes the last stored run per prompt version and macOS build as a Markdown table, and stops |

## Comparing against a saved result

`--against` first compares run headers and exits non-zero, naming each field, when the corpus,
macOS build, hardware or context setting differs and `--allow-difference` does not name it. The
prompt version and source commit are what a change varies, so they may differ freely. A baseline
stored before run headers is compared without this check, with a note.

Every saved result carries a fingerprint of each case it scored (spoken and expected text, the
must-keep, must-not-add, must-begin and must-end lists, doubtful runs, language, destination and
context) and of the corpus as a whole. Origin, split, issue, category and classes are labels and
stay out, so relabelling a case does not change it. `--against` prints a changed corpus first,
lists added, removed and changed cases, and judges only cases whose fingerprint matches; a
result stored before fingerprints is judged case by case as before.

## `--ignore-context`

Context is a claim. Running the corpus with it withheld is the only way to find out whether it
earns its place or merely adds words to the prompt. Results go to a separate directory so a
with-context run cannot overwrite a without-context one.

## `--sample`

A score says a model did badly; only its words say why, and whether the fault is the model or the
way it is asked.

## Declining is not failing

An engine that says it cannot handle a language has behaved well and is not scored as though it
answered wrongly, so each pinned candidate is asked about availability first.

## The shipping-router row

Every other candidate is pinned to one engine so its strengths can be read off. That removes the
fallback, so it predicts badly what a user gets: Apple's model refuses the `injection` case,
which pinned scores zero, and the router hands it to rules and gets it right. `measureShipping()`
runs `TextTransformers.router(configuration: .default)`, so the report includes the configuration
the app runs.

The router row takes no availability pre-check. Declining is what the engines do; the router's
job is to have somewhere to decline to, so a router that produces nothing is scored as a failure.

Apple publishes neither the parameter count nor the quantisation of its on-device model, so the
report prints "n/p" rather than a number from elsewhere.

## Per-category pass rates

The overall figure hides the axis that decides this product: a model excellent at English that
mangles Hindi has not solved the problem. The category list is built from the enum, so a new
category cannot be added to the corpus and go unreported. A rewrite thrown away is always reported
with a reason, because a rewrite discarded for the wrong reason is invisible in a score.

## Provenance and the held-out split

Every `EvaluationCase` names its `origin`: `authored` (written from scratch to state a behaviour,
the default), `reportRewrite` (rebuilt from a reported failure, keeping its shape with every value
invented) or `synthetic` (generated from a template or a rule). An optional `addedFor` names the
issue the case was added for. No origin admits real text from a person; `make pii-audit` scans the
corpus source like any other tracked file.

`CorpusSplit` puts one case in five in `heldout` and the rest in `development`, decided by an
FNV-1a digest of the case id alone. A stored split would let somebody move a case they had tuned
against; a split by position would move existing cases every time one is added. A prompt, rule or
lexicon author reads only development cases. `CorpusSplitTests` fails when a held-out case's spoken
or expected text appears in the prompt contract, a block's rules or any worked example, and when
any category or language with ten or more cases holds out less than 10% or more than 30%.

The bake-off header prints the count per origin and per split, and the report prints a "By split"
pass-rate table. A candidate that scores well on development and worse on held-out has been tuned
to the cases rather than to the behaviour.

### Which score to look at

- **While tuning**, read the development score and the failing development cases. Never open a
  held-out case's text to fix it; held-out expected text is never copied into `Docs/` or a prompt.
- **When judging a change**, read the held-out score. `--against` pairs each case both runs judged
  and prints, per split, the change in pass rate with a 95% paired interval, then the gap
  (development minus held-out) and a verdict named after the held-out split.
- The verdict is `better` only when the held-out interval lies above zero. A development gain with
  an unmoved held-out score is `not shown better`. A development gain with a held-out interval
  below zero is `over-fitted`, and the command exits non-zero. The held-out lines are the ones
  quoted in a pull request.

## What the scorer counts

- **A phrase is read inside one sentence.** `Scorer` keeps sentence ends when it looks for a
  `mustKeep` or `mustNotAdd` phrase, so "clear the cache" is not satisfied by "…clear. The
  cache…". A stop with no space after it stays part of its word, so "p.m." is not two sentences.
- **Shared words are counted in order.** `Scorer.overlap` takes its shared-word count from
  `WordErrorRate.measure`, so a permutation of the reference does not score as a match.
- **A `mustNotAdd` guard** matches words on whole-word boundaries, and a guard with no letters or
  digits (a lone brace) literally.

## Evidence the corpus must hold

A corpus that only ever shows a deletion being made scores over-deletion as a win. Two test suites
hold the corpus to showing both sides:

- **`CorpusEvidenceTests`** requires every correction trigger in `Restatement.triggers` to appear
  in some case that keeps it, and at both scales a pass deletes a verbatim repeat — one word
  (`StammersPass`) and a run of two to four (`RepeatedPhrasePass`) — a case that deletes one and a
  case that keeps one. Triggers with no keep case yet are listed in `owedAKeepCase`, which may
  shrink and may never grow.
- **`PositionalEvidenceTests`** requires every doubtful run the corpus names to appear in some case
  that says the same spelling more than once, so a check that ignores position cannot score as
  well as one that reads it. Runs still owed one are listed in `owedADistractorCase`, which may
  shrink and may never grow, and a stale entry fails.

## `footprint` — will both models fit

Idle memory, the speech model loaded, the language model working, and both at once. The last is
the number that decides whether both run on a 16 GB Mac, and it cannot be inferred from the
others, so it is measured rather than added up. RAM is printed in the units the machine is sold
in: a 48 GB Mac holds 51.5 decimal gigabytes, and printing that invites an argument about the
wrong thing.

## `profile` — what using it costs

`footprint` answers "will both models fit"; `profile` answers "what does using them cost, and
does repeating it leak". The phase order, what counts as a leak and whether cost is linear in
utterance length live in `PerformanceProfiler` and the types around it. The method and the
readings are in [`performance.md`](performance.md); the leak rules are in
[`performance-leaks.md`](performance-leaks.md).

Audio is read before anything is measured, so the timings are transcription and clean-up rather
than the disk; the decoded samples are a few megabytes and already resident when the idle reading
is taken.

The profiler asks for a fresh recogniser twice, once cold and once warm, and the dictation
closure needs whichever is current. That is why the engine is held in a reference box rather than
a captured `var`: the two closures are separate captures of the same thing.

### Processor time, not wall-clock time

A table of seconds answers only how long somebody waited. A dictation that finishes in 3.6
seconds having held four cores busy has spent fourteen processor-seconds, and that figure decides
whether the fans come on, what the battery does, and how the same work behaves on a Mac with fewer
cores. The report prints the implied clock so the arithmetic can be checked against the chip's
specification; a figure nothing like the real clock means the counters and the times disagree.
How the counters are read is in [`eval-profiling.md`](eval-profiling.md).

## Synthesised speech, cached

A profile has to compare two machines or two commits, and a person reading a paragraph twice does
not produce the same seconds of speech either time. Nothing here touches the microphone.

The cache is keyed on the passage text and the voice, not on the file name, so a changed passage
is spoken again rather than reported against yesterday's audio. Audio is 16 kHz mono, what the
recogniser wants and what the microphone path resamples to. `say -v <name>` can exit 0 and write
audio for a name absent from `say -v ?`, so the requested voice is checked against that listing
first; a missing voice falls back to the system default, and the report names the voice that
actually spoke, because the seconds of audio depend on it.

## The candidate list

`LocalModel.candidates` is chosen for plausible Hindi coverage at a size that fits on a laptop,
not for parameter count. The Gemma 3 1B is a control: clean-up is a shallow task and it might have
been enough.

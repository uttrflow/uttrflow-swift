# Measuring a change

Which command answers the question your change raises, how long it takes, and what it needs
before it can run. The pages linked in each row say how the tool decides; this page says when
to reach for it. Every command named here is checked against the `Makefile`, `Scripts/` and the
tool sources by `Scripts/measure_commands_audit.py`, which runs in `make docs-audit`.

## Which command for which change

| You changed | Question | Command | Run time | Needs | Reading the result |
|---|---|---|---|---|---|
| the clean-up prompt or a rule | did any case get worse? | `make bakeoff`, then `make bakeoff ARGS="--against <saved-result.json>"` | not timed on this page; one pass per engine over the evaluation corpus | the Metal toolchain; the models it scores, downloaded on first run (0.8 to 3.0 GB each, [bakeoff.md](bakeoff.md)) | a case that passed before and fails now is a regression; paste the comparison into the pull request ([bakeoff-method.md](bakeoff-method.md)) |
| one sentence through one engine | what does this engine write for this input? | `uttrflow-dev clean` | seconds | the engine's model installed | the printed text is the inserted text ([bakeoff.md](bakeoff.md)) |
| the recogniser, its pin or its decoding options | did any language, stressor or cohort get worse? | `uttrflow-eval record` once, then `uttrflow-eval transcribe` with `--baseline` and `--fail-on-regression` | about 15 minutes of reading once; the transcribe pass is unattended | a corpus recorded by you; the speech model installed | a non-zero exit is a regression or "no verdict", and the printed reason says which ([measuring-accuracy.md](measuring-accuracy.md), [eval-methodology.md](eval-methodology.md)) |
| a lexicon, the vocabulary or the joiner | are the words still right end to end? | `Scripts/dictation_bench.py` to build the corpus and jobs, `uttrflow-dev bench` to play them, `Scripts/dictation_bench.py` again to score | about a minute to synthesise the corpus; the first recogniser load can take minutes while it compiles | a Release build of `uttrflow-dev`; the system `say` voices | raw and final word error rate per category, before against after ([performance-dictation.md](performance-dictation.md#end-to-end-the-words-and-the-wait)) |
| the latency path | how long is the wait after key-up? | `uttrflow-dev bench` in real-time mode (`--mode rt` on the jobs) | as above | as above | the wait after key-up per clip, and each recognition and tidy with its own start and end ([performance.md](performance.md#re-running-it)) |
| processor or memory cost of a dictation | what does one dictation cost? | `make bakeoff ARGS="profile"` | not timed on this page | the speech model installed; the Metal toolchain | processor-seconds and footprint per phase ([performance.md](performance.md#re-running-it)) |
| energy or memory rules in the source | does the source keep to the budget? | `make perf-budget` | seconds; no build | nothing; it runs in `make verify` | each allowance printed with its reason; a failure names the line ([performance.md](performance.md)) |
| the suggestion model's memory | does a pass stay under the budget? | `make perf-budget-models` | not timed on this page | the speech model and the suggestion model installed, so a Mac rather than CI | fails when a reading is over the budget ([performance.md](performance.md)) |
| anything held across dictations | does the heap grow over hours? | `make soak` (`Scripts/soak.sh`) | about 50 minutes by default: six samples ten minutes apart, with five waits between them | a running app in a windowing session, being used | a class whose count only rises is the chain to look at ([soak.md](soak.md)) |

## What is shared

- **The Metal toolchain.** `make bakeoff` stops and prints the install command when it is
  missing: `xcodebuild -downloadComponent MetalToolchain`.
- **The speech model.** `uttrflow-dev models install` puts it where every tool above reads it.
- **Your own recordings.** Only `uttrflow-eval` uses a person's voice, and the recordings stay on
  your Mac; whether any are ever committed is an open decision in [measuring-accuracy.md](measuring-accuracy.md#why-the-audio-is-not-committed).
- **Before and after on one machine.** Every comparison above is the same command run on the
  branch and on `origin/main`, on the same Mac; a number from another machine is not a baseline.

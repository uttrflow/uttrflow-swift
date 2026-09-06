# How the bake-off measures, and why each row is there

`Sources/uttrflow-bakeoff/` scores every candidate clean-up engine against the same corpus.
`Docs/bakeoff.md` is the operator's guide; this page is the reasoning behind the numbers.

## A separate executable

It links MLX, which needs Metal shaders that Swift Package Manager's command line cannot
build, so it cannot be a subcommand of `uttrflow-dev` without dragging that requirement into
the everyday tool. Build it with `make bakeoff`.

Each candidate's result is written to disk as it finishes, so a model that stalls mid-download
costs only its own run; `--summarise` prints everything measured so far. Two candidates can
share a family name — Gemma 3 ships at 1B and 4B — so the stored file is keyed by size as well,
or one would silently overwrite the other, and the report prints the size for the same reason.

## `--ignore-context`

Context is a claim, not a given. Running the corpus with it withheld is the only way to find
out whether it earns its place or merely adds words to the prompt. Results go to a separate
directory so a with-context run cannot overwrite a without-context one.

## `--sample`

A score says a model did badly; only its actual words say why — and whether the fault is the
model or the way it is being asked.

## Declining is not failing

An engine that says it cannot handle a language has behaved well, and must not be scored as
though it answered wrongly, so each pinned candidate is asked about availability first.

## The shipping-router row

Every other candidate is pinned to one engine so its own strengths can be read off. That is
the right way to compare engines and the wrong way to predict what a user gets, because it
removes the fallback: Apple's model refuses the `injection` case outright, which pinned scores
zero, and the shipping router hands the case to rules and gets it right. Without this row the
report would understate the product by describing a configuration nobody runs.

The router row takes no availability pre-check. Declining is what the *engines* do, and the
router's whole job is to have somewhere to decline to — a router that produced nothing would be
a real failure, so it is scored as one.

The shipping configuration is Apple's model first, a local model for what it cannot do, and
rules as the floor that always answers. Apple publishes neither the parameter count nor the
quantisation of its on-device model, so the report says so rather than repeating a number from
elsewhere.

## Per-category pass rates

The overall figure hides the only axis that decides this product: a model that is excellent at
English and mangles Hindi has not solved the problem a local model exists to solve. The
category list is built from the enum rather than a fixed list, so a new category cannot be
added to the corpus and then quietly go unreported.

A rewrite thrown away is always reported with a reason. A rewrite discarded for the wrong
reason is invisible in a score, and that has already cost this project twice.

## `footprint` — will both models fit

Idle memory, the speech model loaded, the language model working, and both at once. The last is
the number that decides whether this runs on a 16 GB machine, and it is the only one that
cannot be inferred from the others, so it is measured rather than added up. RAM is printed in
the units the machine is sold in — a 48 GB Mac holds 51.5 decimal gigabytes, and printing that
invites an argument about the wrong thing.

## `profile` — what using it feels like

`Footprint` answers "will both models fit"; `Profile` answers "what does using them feel like,
and does repeating it leak". Every decision — the order of the phases, what counts as a leak,
whether cost is linear in utterance length — lives in `PerformanceProfiler` and the types
around it, where a test can reach them. What is left in the command is the wiring and the
table.

Audio is read before anything is measured, so the timings are transcription and clean-up
rather than the disk. The decoded samples are a few megabytes and are already resident when
the "idle" reading is taken — see `Docs/performance.md`.

The profiler asks for a *fresh* recogniser twice, once cold and once warm, and the dictation
closure needs whichever is current. That is why the engine is held in a reference box rather
than a captured `var`: the two closures are separate captures of the same thing.

### Processor time, not wall-clock time

A table of seconds answers only "how long did somebody wait". A dictation that finishes in 3.6
seconds having held four cores busy has spent fourteen processor-seconds, and it is that figure
— not the 3.6 — that decides whether the fans come on, what the battery does, and how the same
work behaves on a Mac with four cores instead of twelve.

The report prints the chip's nominal clock so the arithmetic can be checked against a
specification anybody can look up. A figure nothing like the Mac's real clock means the
counters and the times disagree, and that every instruction count above it is suspect.

## Synthesised speech, cached

A profile has to compare two machines or two commits, and a person reading a paragraph twice
does not produce the same seconds of speech either time. The operator is the only one who can
record a microphone, and this measurement must not wait on them.

The cache is keyed on the passage text and the voice, not on the file name: a cache keyed only
on the name would go on reporting yesterday's audio under today's passage, which is the quiet
kind of wrong a performance document never recovers from.

Audio is 16 kHz mono — what the recogniser wants and what the microphone path resamples to, so
nothing is resampled twice. A named voice may simply not be installed on a given Mac; falling
back to the system default keeps the profile runnable, and the report names the voice that
spoke because the seconds of audio depend on it.

## The candidate list

Chosen for plausible Hindi coverage at a size that fits on a laptop, not for parameter count —
the requirements are explicit that a model must not be picked for being small. The 1B is a
control: clean-up is a shallow task and it might have been enough.

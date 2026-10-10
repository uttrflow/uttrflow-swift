# How long a dictation takes, and how accurate it is

A dictation is the recogniser (Whisper large-v3 turbo on CoreML through WhisperKit,
`Sources/UttrflowSpeech/`) and the tidier (Apple's on-device model, then rules) driven by
`DictationPipeline` (`Sources/UttrflowPipeline/`). This page holds the measured latency, the wait
after key-up, word error rate on a synthetic corpus, and what loading the model costs. Readings
come from `uttrflow-bakeoff profile` (method in [`performance.md`](performance.md)) and from
`uttrflow-dev bench` with `Scripts/dictation_bench.py` (below). Accuracy against recorded speech is
[`measuring-accuracy.md`](measuring-accuracy.md); early transcription is
[`early-transcription.md`](early-transcription.md).

The current latency is the dated table in
[`performance.md`](performance.md#latency-budget-per-stage), which names the commit, hardware, load
and mode it was measured at. Every latency figure on this page is historical and says which commit
recorded it; read it for the shape of the cost, not for today's value.

## Latency in the profile

**Historical, recorded by commit `8b07c12e9` (2026-08-29), before early transcription.** Median and slowest of three runs each, model already loaded, Debug,
load average up to 24:

```
  length   audio   runs  end-to-end          transcription       transformation
  ───────────────────────────────────────────────────────────────────────────────
  short    3.42    3     1.68      2.23      0.54      1.39      0.85      1.15
  medium   13.91   3     2.41      3.31      1.06      1.07      1.33      2.25
  long     58.10   3     7.36      8.74      4.07      5.14      3.29      3.61
```

The profile reads audio off disk and types into nothing, so capture and insertion are not in it.
The app times every stage of a real dictation as a `PipelineStage` — `microphoneOpen`,
`keyDownToAudio`, `capture`, `drain`, `transcription`, `correction`, `transformation`, `expansion`,
`insertion` — and shows them on the Diagnostics page.

**The microphone opening** builds the audio graph, queries the input format, installs a tap and
starts the engine before a single sample exists, while the user is already speaking; it is
`microphoneOpen`. Creating the recording's file is not part of it: `RecordingStore.begin` hands the
folder, WAV, backup exclusion, header and creation date to the writer's own task, which creates the
file before writing the first block it was handed, so nothing captured in between is lost. Timed
over 300 `begin()` calls against a temporary folder on a quiet Mac:

| `RecordingStore.begin()` | median | p90 | p99 | max |
|---|---|---|---|---|
| file work on the writer (shipped) | 13–26 µs | 24–42 µs | 57–125 µs | 62–459 µs |
| file work inline (not used) | 225–340 µs | 314–513 µs | 540–652 µs | 2.8–4.9 ms |

`uttrflow-dev latency --opens N` opens the real microphone N times through the shipping
`AVAudioCaptureEngine` (`--device UID` picks an input from `--list-devices`; `--idle S` keeps it
closed S seconds before each opening, for the cold case), times each `start()` through the same `measuring(.microphoneOpen)` the
pipeline uses, polls every millisecond for the first sample, and summarises with `StageLatency`.
One run of 20 opens, debug build, built-in microphone, on a heavily loaded Mac (load average
339–387), so these are loaded-machine figures; re-run on a quiet Mac before a decision rests on
them:

| | median | slowest | samples |
|---|---|---|---|
| `microphoneOpen` (`start()` returning) | 779 ms | 1454 ms | 20 |
| start called to first sample | 879 ms | 1555 ms | 20, 0 silent |

The first sample arrives about 100 ms after `start()` returns, one hardware block. For a modifier
shortcut `keyDownToAudio` starts at key-down and is read when the press is adopted after
`modifierSettle`, so it records the settle rather than the first sample; for any other shortcut it
is not recorded. Neither has a latency budget; the stages that do are in
[`performance.md`](performance.md#latency-budget-per-stage).

**Dictionary correction** is held to work, not time: `CorrectionEngineTests` checks that a
10,000-entry dictionary reads no more entries than a 50-entry one and that the screen is read once
per utterance. **The doubtful-word candidate step** is budgeted at under 5 ms a piece
([`cleanup-design.md`](cleanup-design.md)); `DoubtfulWordsTests` counts Double Metaphone encodings
through `DoubleMetaphone.tally` instead of timing, and fails when ten times the screen words costs
more than one encoding each or a doubtful run costs more than four. A wall-clock bound is not used
because it failed under a sanitizer build and a busy machine on changes that never touched the
step.

### Transcription steps every 30 seconds

**Historical, recorded by commit `8b07c12e9` (2026-08-29), before early transcription.** From an earlier `profile` run, re-confirmed by the one above (superLinear for transcription, linear
for clean-up). Marginal cost, in extra seconds of work per extra second of speech:

```
  end-to-end        short→medium 0.142   medium→long 0.162   linear
  transcription     short→medium 0.069   medium→long 0.093   superLinear
  transformation    short→medium 0.070   medium→long 0.070   linear
```

Clean-up costs the same per second of speech whatever the length. Transcription steps at Whisper's
thirty-second window. Timed either side of the boundary, three runs each:

| audio | transcription |
|---|---|
| 24.96 s | 2.12 / 2.14 / 2.15 s |
| 33.75 s | 3.22 / 3.25 / 3.28 s |

Those 8.8 extra seconds cost 1.14 s against the 0.61 s the in-window rate predicts; the extra
≈ 0.5 s is a second encoder pass over a window that is mostly padding. A dictation costs roughly
**1.6 s fixed, plus 0.14 s per second of speech, plus 0.5 s for every thirty-second window after
the first**; 1.1 s of the fixed part is the clean-up model starting work. That predicts 10.4 s for
the 58-second passage against 10.74 s measured.

## Loading the model

| | seconds | who pays it |
|---|---|---|
| Neural Engine compile, no compiled copy on this Mac and OS | 148–254 | the first launch after install, and after anything that changes the model or the OS |
| a fresh process, compiled copy cached | 2–9 | every login, and the next dictation after a memory-pressure release |
| a second recogniser in a live process | 4–9 | nobody — `BackedSpeechEngine` loads once and keeps it |

The cold compile is not the app's work: the app spent 21.6 processor-seconds (0.15 of a core) over
148 s, while `ANECompilerService`, a system daemon, ran at 88% of a core throughout. A rebuilt
binary does not empty the compiled copy: a fresh build loaded in 2.25–2.40 s on a quiet machine,
so the copy belongs to the model and the OS. With the copy cached, a load costs 5.68
processor-seconds at 0.98 cores. Loading is CoreML preparing four `.mlmodelc` bundles each time a
recogniser is constructed, so the recogniser is constructed once and kept.

### Launch and WhisperKit's prewarm

`WhisperKitBackend` loads with WhisperKit's prewarm on; only a measurement harness passes
`prewarm: false` (`uttrflow-bakeoff profile --no-prewarm`). `PerformanceProfiler` watches the first
load with `PeakMemory.observed`. Six interleaved runs of each, Debug, load average 9–38:

| | seconds | processor seconds | added to the footprint | peak during the load |
|---|---|---|---|---|
| prewarm on (shipped) | 2.25–2.40 | 2.19–2.36 | 104.6–108.6 MB | 182.8–186.8 MB footprint, 341–354 MB resident |
| prewarm off | 1.34–1.38 | 1.32–1.89 | 87.5–92.2 MB | 183.6–186.1 MB footprint, 347–348 MB resident |

On a warm compile prewarm costs about 0.9 s of launch and 16 MB once loaded, and the load's peak is
the same either way, inside the 400 MB dictation line. The first dictation after a warm launch
waited 1.05 s against 1.02–1.03 s for the next two. Prewarm exists to hold down the peak of the
**first** compile, and that peak is not measured:

- **There is no compiled cache to remove.** A load writes nothing under `~/Library/Caches`, the
  model folder or the per-user cache directory. A cold load is a Neural Engine compile the system
  has no copy of, and the only levers are a restart and `purge`, which needs root.
- **Most of that peak is in another process.** `MemoryFootprint` and `/usr/bin/time -l` each report
  one process, so neither sees `ANECompilerService`, and the number the app can report is not the
  one an 8 GB Mac runs out of memory on.

Measuring it needs a machine-wide instrument and two restarts, since the first load after one is
the only cold load there is: run
`uttrflow-bakeoff profile --dictations 1 --repetitions 1 --transcribe-only` first thing after a
restart, add `--no-prewarm` after the next, and watch `ANECompilerService` beside both.

## End to end: the words and the wait

`uttrflow-dev bench` plays clips through `DictationPipeline` exactly as a held key would — the
shipping router, early transcription, the piece joiner — and prints one JSON line per dictation:
the text, the wait after key-up, each recognition and each tidy with its start and end, processor
seconds, and the peak footprint sampled every 20 ms. `Scripts/dictation_bench.py` builds the
corpus, writes the jobs and scores a run. One process loads the recogniser once and plays every
clip: separate processes would each compile for the Neural Engine at the same moment and stall
each other, which is why `uttrflow-dev dictate`, one clip per process, cannot run a corpus.

**The corpus is synthetic and invented.** `say` voices for US, UK and Indian English and for Hindi;
replies of one to four words, passages of 5 s to 2 min (with a 0.9 s breath every third sentence
from 30 s up, and one 60 s passage without), numbers, email addresses on `example.com`, code
identifiers, invented proper nouns with and without a vocabulary, Hinglish read in the Latin
alphabet, spoken punctuation, self-corrections, the `TranscriptionCorpus` passages, Hindi replies
(`hi-reply`), mixed-language clips (`code-switch`), and ten clips again with brown noise at 20 and
10 dB SNR, 24 dB quieter and 12 dB hotter (clipping). No recording of a person is involved.

**Developer speech** (`devspeech`) is invented sentences with commands, flags, file names,
acronyms and made-up project names, read by all three English voices, by Samantha at 130 and 240
words a minute (`devspeech-slow`, `devspeech-fast`), and two of them with the noise and level
variants above. The whole corpus is rebuilt from `Scripts/dictation_bench.py`; no audio is
committed.

**Developer vocabulary** (`devvocab-commands`, `-flags`, `-tools`, `-acronyms`) is short phrases,
at least eight per category, each read by all three English voices twice: bare, and after a
fixed lead-in such as "In the terminal, run". `score` prints the two as a paired table: the raw
WER of each, and how many clips heard the term's words in order. The lead-in is the preceding
context; the difference between the columns is what it is worth to the recogniser.

Baseline, shipping recogniser and cleaner, fast mode, 24 pairs per category (raw WER bare →
after the lead-in; term heard bare → after): commands 29.8% → 4.6%, 15 → 21; flags 13.9% → 8.3%,
17 → 22; tools 62.5% → 22.5%, 10 → 14; acronyms 8.8% → 2.9%, 20 → 21. Final exact WER over both
halves: flags 85.4%, tools 44.4%, acronyms 31.5%, commands 30.5%; spoken flags are not yet written
as `--flag`.

**Entities and false overrides.** Each clip tags its entities: the developer-vocabulary term,
the invented names in `nouns` whether or not they are supplied as vocabulary, and the supplied
vocabulary words its text contains. `score` prints, per category and per vocabulary supplied or
not, four rates over the final text against the written reference: entity error (a term with any
word wrong), tagged-word WER and untagged-word WER (substitutions and deletions only; an inserted
word belongs to neither), and the false-override rate, words the recogniser had right that the
final text has wrong, over words the recogniser had right. The false-override rate is counted only
where the spoken and written references normalise the same, since elsewhere the two stages answer
different references; `clips compared` says how many. `uttrflow-eval transcribe` scores the
recogniser alone and carries no entity tags, so these are scored here.

**Personas and apps** (`persona-developer`, `-clinician`, `-support`) are invented people: each
has a vocabulary of a tool, a project and a colleague, the app it dictates into (Terminal,
TextEdit, Mail, passed to the job as the frontmost app), and four sentences using those words, read
by all three English voices. Each sentence is scored three times on the same audio: vocabulary
off, on, and swapped for the next persona's (wrong). `score` prints, per persona and app, the
final WER and entity error under each, the gain (off minus on) and the harm (wrong minus off), in
points of final WER, over sentences scored under all three. A harm above `PERSONA_HARM_LIMIT` (2
points) makes `score` exit non-zero. The persona here is a supplied vocabulary: in the app the
learned persona ranks which dictionary words `WorkingSet` hands the recogniser, so what it chooses
is scored by putting those words in these lists.

**Professional domains** (`domain-medical`, `-legal`, `-financial`, `-scientific`) are at least
`DOMAIN_MIN_SENTENCES` (15) sentences and `DOMAIN_MIN_TERMS` (40) distinct terms per domain:
generic drug names, anatomy and clinical abbreviations said as letters and one as a word; Latin
legal phrases and section, clause and rule numbers read aloud; accounting terms, ratios and
letter abbreviations; units, chemical names and Greek letters. No brand names, and no term with a
regional spelling, so a term is right or wrong by its words alone. Each sentence is read by all
three English voices twice on the same audio: with no vocabulary (`bare`), and with its own terms
supplied (`vocabulary`). Its terms are its entities under both, so the entities table's `domain-…,
no vocabulary` and `domain-…, vocabulary` rows are the term error rate per domain without and
with the dictionary. `corpus` refuses a domain under either minimum or a term its sentence does not
contain.

Baseline, shipping recogniser and cleaner, fast mode, clean audio, one Release run under a load
average of 90–190 (term error without → with the sentence's terms supplied; final WER of the
category over both):

| domain | clips per condition | term error, no vocabulary | term error, vocabulary | final WER |
|---|---|---|---|---|
| legal | 51 | 17.0% | 0.7% | 4.8% |
| medical | 51 | 9.5% | 4.1% | 3.1% |
| financial | 48 | 8.3% | 1.4% | 3.1% |
| scientific | 51 | 3.8% | 0.8% | 0.7% |

**The bar for a starting vocabulary pack is 5% term error with no vocabulary**: a domain above it
gets a pack, a domain under it does not. Legal, medical and financial are above it; scientific is
not. Bare, the misses are Latin phrases (`res judicata`, `stare decisis`, `ratione materiae`,
`nolo contendere`), letter abbreviations (`GAAP`, `ROE`, `CABG` said as a word), multi-word
terms (`weighted average cost of capital`) and drug names (`budesonide`, `atorvastatin`).
Supplied, `budesonide` and `ST elevation` are missed as often as bare,
so a pack does not fix every term.

**Voices and their licence.** Every voice is a macOS system voice (Samantha, Daniel, Rishi,
Lekha), used under the macOS software licence agreement that ships them. `corpus` refuses a voice
missing from `VOICE_SOURCES`, so a new voice is added there with its source before it is used.

**What synthetic speech hides.** `say` reads every word at an even pace, with no hesitations,
restarts, mumbled endings, breathing, room echo or microphone colour, and the same text in the
same voice gives the same samples every time. Real dictation has all of these, so word error
rates here are a floor: they rank changes against each other and do not predict what a person
will see. A recorded set of real speakers is personal data and is not part of this corpus
(`make audio-audit`).

**Two word error rates.** *Raw* is the recogniser's pieces joined, against what was said; *final*
is the inserted text, against what should be typed. Both lower-case, drop punctuation, spell
numerals, and split identifiers and addresses into words, so "3.5%" and "three point five percent"
agree; neither sees capitals or punctuation. Hindi is scored against the Devanagari and the
romanised passage, whichever is closer.

### Word error rate

**Historical, recorded by commit `7acaae647` (2026-09-14).** One run of the commands below, Release, load average 6–30, each clip all at
once with the shipping router:

| category | clips | raw | final |
|---|---|---|---|
| replies, 1–4 words | 14 | 0.0% | 0.0% |
| 5 s | 3 | 0.0% | 0.0% |
| 15 s | 3 | 2.5% | 2.5% |
| 30 s | 3 | 2.9% | 2.9% |
| 60 s | 4 | 1.0% | 1.0% |
| 120 s | 3 | 0.5% | 0.5% |
| numbers | 4 | 6.0% | 6.0% |
| email addresses | 3 | 2.2% | 2.2% |
| code identifiers | 4 | 0.0% | 1.7% |
| spoken punctuation | 3 | 16.7% | 9.5% |
| self-corrections | 4 | 2.3% | 0.0% |
| invented names, no vocabulary | 9 | 28.1% | 28.1% |
| invented names, in the vocabulary | 9 | 0.0% | 0.0% |
| `TranscriptionCorpus`, English | 18 | 2.8% | 3.1% |

| voice | clips | raw | final |
|---|---|---|---|
| US English | 31 | 2.1% | 2.2% |
| UK English | 27 | 2.3% | 2.4% |
| Indian English | 26 | 3.5% | 3.3% |

| audio, over the same ten clips | raw | final |
|---|---|---|
| as synthesised | 2.4% | 2.4% |
| 24 dB quieter | 2.9% | 2.9% |
| 12 dB hotter, clipping | 3.4% | 3.4% |

The ten `hi-reply` clips, run alone in fast mode with the rules cleaner and the `hi` Languages
profile, were all decoded as Hindi, raw WER 20.0% and final 32.1%; the two shortest still had word
errors (`हाँ ठीक है` became `हाप पहे`, `हाँ जी` became `हाजजी`). These are synthetic-voice results,
not a claim about real speakers.

- **A vocabulary is worth what it costs.** Invented names go from 28% wrong to none when they are in
  the prompt; the cost is below.
- **Numbers and names are the English errors.** "4,250 dollars and 75 cents" is written
  "$4,250.75" (fair, but counted); "Jaxvale" becomes "Jack's Vale". Code identifiers are joined as
  the recogniser chose; "src" is heard as "source".
- **Volume barely registers** on synthetic speech. The same audio can still come back differently
  between runs: "Ship it" at 10 dB SNR came back "Shit is." in one run and as nothing in the next,
  and split 16 to 34 over 50 runs — the model's own greedy reading and the temperature ladder
  deciding whether it is shown ([`speech-engines.md`](speech-engines.md)). `score` names every clip
  run more than once that answered differently.
- **The tidier changed the words of 2 of 120 English clips**: it removed a stray quotation mark the
  recogniser left, and turned "thick" into "theek" in a noisy clip. Every other English dictation
  came out identical to the rules pinned alone.

### The wait

**Historical, recorded by commit `7acaae647` (2026-09-14).** **All at once** hands the whole file over and releases the key, so every piece is recognised and
tidied after key-up: what a retry does, and the worst case. **Real time** plays the file at speaking
pace, so early transcription works ahead while the key is held. The wait is key-up to the words
being ready; recognising and tidying are each dictation's total across its pieces, so in real time
they can exceed the wait.

| | clips | speech | wait p50 | wait p95 | first piece tidied while held, p50 | recognising p50 | tidying p50 | processor s per speech s | peak footprint |
|---|---|---|---|---|---|---|---|---|---|
| replies, all at once | 14 | 0.8 s | 1.07 s | 2.40 s | — | 0.56 s | 0.50 s | 0.110 | 362 MB |
| replies, rules only | 14 | 0.8 s | 0.60 s | 0.69 s | — | 0.60 s | 0.00 s | 0.080 | 362 MB |
| 5 s, all at once | 3 | 5.1 s | 1.06 s | 1.14 s | — | 0.57 s | 0.49 s | 0.035 | 258 MB |
| 15 s, all at once | 3 | 16.8 s | 3.56 s | 4.53 s | — | 1.25 s | 2.31 s | 0.031 | 258 MB |
| 30 s, all at once | 3 | 31.5 s | 8.41 s | 9.30 s | — | 4.07 s | 6.56 s | 0.030 | 219 MB |
| 60 s, all at once | 4 | 58.4 s | 10.83 s | 12.25 s | — | 7.45 s | 9.99 s | 0.029 | 255 MB |
| 120 s, all at once | 3 | 116.2 s | 19.94 s | 22.38 s | — | 15.90 s | 18.47 s | 0.030 | 270 MB |
| replies, real time | 14 | 0.8 s | 1.67 s | 3.91 s | — | 0.75 s | 0.79 s | 0.147 | 229 MB |
| 5 s, real time | 3 | 5.1 s | 1.58 s | 2.41 s | — | 0.61 s | 0.97 s | 0.039 | 229 MB |
| 15 s, real time | 3 | 16.8 s | 2.99 s | 3.68 s | — | 1.29 s | 1.70 s | 0.034 | 228 MB |
| 30 s, real time | 3 | 31.5 s | 1.93 s | 3.39 s | 16.9 s | 3.10 s | 3.91 s | 0.035 | 229 MB |
| 60 s, real time | 4 | 58.4 s | 2.75 s | 7.38 s | 17.6 s | 6.32 s | 7.19 s | 0.034 | 287 MB |
| 120 s, real time | 3 | 116.2 s | 2.03 s | 2.19 s | 15.1 s | 9.79 s | 12.70 s | 0.034 | 372 MB |

- **Early transcription holds the wait near two seconds from 30 s up.** All at once, a two-minute
  dictation waits 20 s; spoken, 2 s. The 15 s passages have no breath long enough to cut at, so
  they are one piece and wait for all of it.
- **For a short dictation the tidier is half the wait.** A reply recognises in about 0.56 s and
  then waits about 0.5 s more for Apple's model, which returned the rules' answer on every reply
  measured.
- **Processor time is 0.03 s per second of speech** above five seconds, inside the 0.1 budget. A
  reply costs more per second (0.11) because the encoder always reads a full 30-second window.
- **Peak footprint stays under the 400 MB dictation line**; the highest was 372 MB, during a
  two-minute real-time dictation.

### Naming a slow wait in the app

Every dictation from the microphone times its wait from key-up to the words placed and splits it by
cause (`DictationWait`): from `DecodeEffort`, fallback seconds, the wait for the speech model to
load (`BackedSpeechEngine`) and the time spent decoding a piece again after a capped or empty decode
(`CappedDecodeRetry` and the pipeline's unprompted second decode); then a tidy that timed out, the
insertion, and screen reads made after key-up; the rest is "other". The target,
`DictationWait.target`, is 4 s, the spoken-reply p95 in the table above. A wait past it is named by
the cause furthest past its median over the last 100 dictations (`DictationWaits`). The cause is kept
on the History record on this Mac; Diagnostics shows p50 and p95 per dictation and the count per
cause. A cold tidier session has no separate timing yet, so its time falls under "other".

### What the recognising time is made of

**Historical, recorded by commit `7acaae647` (2026-09-14).** WhisperKit reports its own stages in `TranscriptionResult.timings`. Read with a temporary print
over 528 decodes of the same corpus:

- **Decoder steps are about four fifths of it**, one Neural Engine call per token, 20 ms each on a
  quiet machine and 37 ms under a load average of 100–200. The encoder is about a sixth, roughly
  0.28 s per 30-second window.
- **Everything on the processor around the steps is under 5%**: the key-value cache copy, logits
  filtering, sampling and word timestamps.
- **The temperature fallback never fired** in 528 decodes, so the fallback settings cost nothing on
  this corpus and cannot be tuned against it.
- **A vocabulary costs one decoder step per prompt token, every piece.** Four or five invented names
  are 20–26 tokens and took the median recognition of a 4.6 s clip from 1.61 s to 2.50 s under
  load; at 20 ms a step a full 111-token prompt is about 2.2 s more for every piece.

### Measured and not used

- **The GPU for the encoder and decoder.** Recognition was about 30% faster (a 15 s clip 0.95 s
  against 1.33 s) but the footprint was **3.4 GB** against 250 MB, with a first recognition after
  launch of 2.4–8.1 s while shaders warmed: twelve times the dictation budget on an 8 GB Mac.
- **Skipping Apple's model for longer dictations.** Identical to the rules on 117 of 120 synthetic
  English clips, and the tidier is most of the all-at-once wait; but synthetic speech has none of
  a person's pauses, fillers and slips, so this is not evidence that real dictation would match.
- **A shorter vocabulary prompt.** The per-token cost above is real and so is the accuracy it buys;
  trading one for the other needs vocabularies of the size people keep.

## Re-running the bench

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release --product uttrflow-dev
swift build -c release --product uttrflow-eval                             # the scorer's word normalisation
python3 Scripts/dictation_bench.py corpus                                  # .build/bench, about a minute
python3 Scripts/dictation_bench.py jobs --cleaners shipping,rules > .build/bench/jobs-fast.tsv
python3 Scripts/dictation_bench.py jobs --mode rt --clean-only \
    --categories reply,dur5,dur15,dur30,dur60,dur120 > .build/bench/jobs-rt.tsv
cat .build/bench/jobs-fast.tsv .build/bench/jobs-rt.tsv > .build/bench/jobs.tsv
.build/release/uttrflow-dev bench .build/bench/jobs.tsv > .build/bench/run.out
python3 Scripts/dictation_bench.py score .build/bench/run.out
```

`score` counts words through `uttrflow-eval normalise`, the same `TextNormaliser.standard` the
Swift scorers use, and prints the rules in force first; a run printed under other rules is not
comparable. `Tests/UttrflowEvalTests/Golden/normalisation.tsv` pins both entry points to one table.

`score --baseline <path>` compares the final text's rates, one cleaner and mode at a time, with a
stored run through `uttrflow-eval compare`, the rule `make accuracy-gate` judges with; add
`--save-baseline` to store the run, or `--fail-on-regression` to exit non-zero on a worse slice.

`--categories hi-reply` selects the Hindi replies, whose jobs use the `hi` Languages profile.
`--categories code-switch` selects an English passage followed by a Hindi one and a Hindi sentence
followed by an English one, each after a 1.5-second pause; their jobs use both `en,hi` and `hi,en`
profiles so each piece detects its own language, and both romanised and Devanagari Hindi forms are
scored.

One clip many times over, which says whether the recogniser answers the same audio the same way:

```
python3 Scripts/dictation_bench.py jobs --repeat 50 --cleaners rules --categories reply \
    | grep snr10 > .build/bench/jobs-repeat.tsv
.build/release/uttrflow-dev bench .build/bench/jobs-repeat.tsv > .build/bench/run-repeat.out
python3 Scripts/dictation_bench.py score .build/bench/run-repeat.out
```

`--idle-before <seconds>` waits before each job and emits an `idle` event, so the tidier's kept
session goes cold between dictations as it does in use; without it every tidy in a run is warm.

```
.build/release/uttrflow-dev bench .build/bench/jobs.tsv --idle-before 300 > .build/bench/run-cold.out
```

Each `clean` line names the steps that changed something (`steps`) and any answer refused before
the one kept (`refused`). Clip audio is named by its voice and words, so changing either speaks it
again. Run one `bench` at a time: two processes compete for the Neural Engine and each other's
compile. The full run takes about half an hour, its first load included.

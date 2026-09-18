# What Uttrflow costs a Mac

Processor, memory, latency and disk — measured rather than estimated, both while it is
working and while it is not. Reproduce with:

```
make bakeoff ARGS="profile --app dist/Uttrflow.app"
```

Everything below came off one machine. The figures were taken on **28 August 2026**;
the thirty-second-window study further down is from the first run, on 23 August, and is
labelled where it appears.

| | |
|---|---|
| chip | Apple M5 Pro — 6 performance cores, 12 efficiency |
| memory | 48 GB |
| macOS | 26.5.1 (build 25F80) |
| speech model | `openai_whisper-large-v3-v20240930_turbo_632MB` |
| clean-up | Apple's on-device foundation model (confirmed: `tidied by foundationModels`) |
| build | debug, via `xcodebuild` — see [limits](#what-these-numbers-are-not) |

**Three headlines, in the order they matter.**

**A dictation is nearly free, and it is free in the surprising direction.** A
fifteen-second dictation costs **0.76 processor-seconds** and finishes in 2.4 s. It never
holds even half a core, because the work is not on the processor at all — it is on the
Neural Engine, and the app spends most of a dictation waiting. That is why the answer to
"what Mac does this need" is not about cores or clock speed.

**Sitting still cost a whole core, and that was a bug.** With its window open the app
used **97.5% of one core, continuously, for as long as it ran** — from login, because it
is a login item — and ⌘H did not stop it. It is fixed; the section on it is below,
because it is much the largest thing this document has ever found.

**No leak, and nothing close to memory pressure.** Peak footprint 379 MB, peak resident
536 MB. An 8 GB Mac is never in danger from Uttrflow alone. Ten consecutive dictations
left the process smaller than it started.

## The energy budget

Uttrflow runs all day, from login, on laptops. The Mac to design for is the smallest one it
supports: an 8 GB M1 Air, which has no fan and slows itself down when it gets hot. Its
performance cores do roughly 55–60% of the work of this document's M5 Pro, and it has far
fewer of them, so the budget is written in quantities that do not depend on the machine —
wakeups, work per event, processor-seconds per second of speech — and scaled where a figure
has to be.

| state | budget | today |
|---|---|---|
| idle: menu bar only, windows closed, suggestions off | ~0% of a core; at most 2 timer wakeups a second from the app's own code | clipboard poll 4.8/s (#375) |
| idle with tab-to-complete on | nothing beyond the line above once 12 s have passed with no keystroke, click or switch and nothing drawn | a 1 Hz tick for ever, each one an Accessibility read of the frontmost app (#374) |
| typing, suggestions on | the tap callback does one atomic load; a turn per keystroke, coalesced to one running and one waiting; a model pass only after 120 ms of quiet, cancelled by the next key | as budgeted |
| a model suggestion pass | at utility priority; none in Low Power Mode or at serious thermal pressure; ≤ 1 processor-second per pass on M1 | user-initiated, ungated (#376); 0.17 processor-seconds per pass here since #427, so ≈ 0.3 on M1 |
| dictation | speech ≤ 0.1 processor-seconds per second of audio on M1; finished within 0.5× the audio's length on M1 | 0.04 here, which scales to ≈ 0.07; 0.20× wall clock here on a loaded machine |
| a copy | classified at utility priority, off the main thread; ≤ 0.2 processor-seconds for a 2 MB clip on M1 | 0.085 here for the costliest 2 MB clip measured, ≈ 0.17 on M1 (#460) |
| animation | none continuous while nobody can see it; none decorative under Reduce Motion, Low Power Mode or serious thermal pressure | #359, #377 |

How the rows were measured, on 13 September 2026, on a machine at a load average of 50–180 from
other builds, so wall-clock figures are pessimistic and processor-seconds are the ones to trust:

- **Model pass.** `uttrflow-bakeoff complete --fixtures --model gemma3`, release build, under
  `/usr/bin/time -l`: 30 fixtures cost 22.96 processor-seconds and one cost 4.09, so each pass
  past the first is 0.65 processor-seconds and 11.3 G instructions, p50 784 ms. A debug build
  costs twice that (1.28 s), which is why this row is measured in release. Re-measured for #427 on
  14 September over all 1,154 fixtures, back to back at a load average up to 240: 1,086
  processor-seconds with the prompt tokenised whole, 192 with `PromptTokens`, so 0.94 against 0.17 a
  pass, p50 1,166 ms against 207 ms, and every fixture's lines identical.
- **Speech.** `uttrflow-bakeoff profile --transcribe-only`, release: 0.15, 0.51 and 2.19
  processor-seconds for 3.4, 13.9 and 58.1 seconds of speech — 0.04 per second of audio, 0.27 G
  instructions per second of audio.
- **Clipboard poll.** A stand-alone loop that sleeps and reads `NSPasteboard.changeCount`, its
  own wakeups read with `proc_pid_rusage`: 4.8 wakeups a second at 200 ms, 1.7 at 500 ms with a
  100 ms tolerance, 1.0 at 1 s. Processor time is under 0.05% of a core in every case; the
  wakeups are the cost.
- **A copy.** `ClipKindDetector.kind(of:)` timed in a release build on 14 September over nine
  kinds of clip at 16 KB to 2 MB; the table and the method are under *Classifying a copy* below.
- **The tick.** Counted from the code, not measured: one wakeup a second and one cross-process
  Accessibility read, for as long as the feature is on.

## The method

`uttrflow-bakeoff profile` drives one process through the app's whole life and reads
memory at each named moment. The order is fixed, because the order is the measurement:

1. read memory with nothing loaded;
2. load the speech model, timed, and read again;
3. one dictation that is **thrown away** — the first of a process pays for buffers every
   later one reuses, and counting it would make warm-up look like a leak;
4. ten (or thirty) consecutive dictations of the same paragraph, reading memory after
   each — this is the leak check;
5. each of the three utterance lengths, timed three times;
6. a second, independent load of the speech model, last, so a second recogniser held
   alongside the first cannot inflate any figure above it.

While each dictation runs, memory is polled every 20 ms. That is the only way to catch a
spike that has settled again by the time the next named moment is read.

Two memory figures are reported throughout, because for a product that memory-maps a
646 MB CoreML model they are very different numbers:

- **footprint** (`phys_footprint`) — what Activity Monitor's Memory column shows, and
  what a memory limit is enforced against. Dirty and compressed pages only.
- **resident** (`resident_size`) — every page in physical RAM, the model's mapped weights
  included. Larger, and evictable under pressure, so it overstates the true cost.

Neither alone is honest. The footprint on its own looks as though 200 MB of model went
missing; the resident size on its own suggests pressure that clean file-backed pages do
not actually create.

Cross-checked from outside the process: watching `ps -o rss` through a run put the peak
at 463 MB, against the 362 MB the process reports for itself. The two do not have to
agree — `ps` counts shared framework pages that the task's own accounting attributes
differently — but they are the same order, which is the point of checking.

### The speech

Three passages, read aloud by the system synthesiser (`say -v Samantha`) into 16 kHz
mono WAV and cached under `.build/profile-audio`. Synthesised rather than recorded on
purpose: a person reading the same paragraph twice does not produce the same seconds of
speech, and a profile has to be able to compare two commits rather than two takes.
Nothing here touches the microphone — that is the operator's to trigger.

The passages are ordinary work dictation, with fillers, a mid-sentence restart, a port
number, a version string and an Indian name, because a profile run on clean read-aloud
prose measures the recogniser doing an easier job than the product's.

| length | words | audio |
|---|---|---|
| short | 12 | 3.42 s |
| medium | 46 | 13.91 s |
| long | 191 | 58.10 s |

## Memory

```
  moment                        footprint   resident    change
  idle, nothing loaded          11.1 MB     50.5 MB     —
  speech model loaded           229.8 MB    459.8 MB    +218.8 MB
  after one dictation           295.5 MB    525.1 MB    +65.6 MB
  after 10 dictations           267.8 MB    517.9 MB    -27.7 MB
  after the length sweep        148.0 MB    510.2 MB    -119.7 MB
  peak, mid-dictation           379.4 MB    535.7 MB
```

- **The 648 MB model does not cost 648 MB of memory.** It adds 219 MB of footprint and
  409 MB of resident size, because CoreML maps the weight files rather than reading them
  into anonymous memory. Under pressure macOS can drop those pages and re-read them.
- **The peak is the number that matters, and it is 379 MB.** A dictation transiently
  costs about 84 MB more than the settled figure — activations and the clean-up model's
  working set. On an 8 GB Mac with a browser open that is still not a swap event.
- **The shipped app, watched from outside, sits at 300–310 MB of resident memory** from
  a minute after login onwards, and stays there. That figure is not conditional on the
  user dictating: `AppDelegate` calls `prepare()` at launch, so the model is loaded and
  held whether or not anybody ever speaks. See [what is paid before anybody
  speaks](#what-is-paid-before-anybody-speaks).
- Of the 10.9 MB idle figure, about 4.8 MB is the three decoded audio clips, which this
  harness reads before anything is measured so that the timings are transcription and
  clean-up rather than the disk. A real idle app carries no audio at all, so the true
  idle floor is around 6 MB.

### The suggestion model's GPU memory

The suggestion model runs on MLX, and MLX keeps every buffer it frees in a cache for reuse.
It reuses a cached buffer only for a request of nearly the same size, and by default it
empties the cache only near most of the GPU's working set, which is tens of gigabytes on a
48 GB Mac. Every suggestion pass reads a prompt of a different length, so every pass
allocated buffers nothing could reuse and left them in the cache: one app grew from 2.9 GB
to 12 GB in forty minutes of typing.

`GPUBufferCache` now caps that cache at 256 MB for the process, and every pass through
`MLXCandidateScorer` — a generation, an alternatives pass, a score — empties it when the
pass ends, however it ends. `MLXCleanupModel` does the same around a rewrite. So turning
AI suggestions off or leaving the Mac idle leaves the weights and at most the capped cache —
in practice nothing. Turning AI suggestions off also releases the weights — see [the memory budget](#the-memory-budget).

Measured with `uttrflow-bakeoff gpu-memory` (Release, Gemma 3 4B QAT, 48 GB Apple silicon):
forty passes over invented message threads of 120–310 words, every fourth pass cancelled
part-way, each followed by one score. The figures are MLX's own counters, in MB.

| after | active, before | cache, before | peak, before | active, after | cache, after | peak, after |
|---|---|---|---|---|---|---|
| loading | 2,485 | 218 | 2,701 | 2,485 | 218 | 2,701 |
| pass 1 | 2,485 | 807 | 2,907 | 2,541 | 0 | 2,843 |
| pass 5 | 2,485 | 2,661 | 3,040 | 2,485 | 0 | 3,013 |
| pass 10 | 2,485 | 3,931 | 3,041 | 2,485 | 0 | 3,036 |
| pass 20 | 2,485 | 6,273 | 3,111 | 2,485 | 0 | 3,036 |
| pass 30 | 2,485 | 8,302 | 3,111 | 2,485 | 0 | 3,036 |
| pass 40 | 2,485 | 9,565 | 3,111 | 2,485 | 0 | 3,036 |
| 5 s idle | 2,485 | 9,565 | 3,111 | 2,485 | 0 | 3,036 |

- **The bound is the weights plus one pass.** The weights hold 2,485 MB, one pass needs
  about 550 MB more at its peak, and the cache holds nothing once a pass has ended. The
  cap matters only inside a pass and for the buffers a cancelled pass frees after it
  has returned: in the worst reading, 86 MB were cached between passes.
- **It costs a pass no measurable time.** Paired runs of forty uncancelled passes, old and
  new binaries alternating, gave medians of 647 against 661 ms, 762 against 653 ms and
  640 against 628 ms on a quiet machine, and 847 against 869 ms and 907 against 930 ms
  under other builds. The run-to-run spread is larger than any difference.
- **Either half alone leaves memory behind.** A 1 GB cap without
  emptying held 1,024 MB after every run; emptying without a cap left 107 MB behind a
  cancelled pass. Both together are what the table shows.

## The memory budget

Uttrflow runs all day on Macs with far less memory than the one these figures came from, so
what it holds is budgeted against the smallest Mac it supports: an 8 GB MacBook Air, where
macOS and a browser already claim most of the memory before Uttrflow opens.

### What holds memory, and when

Measured on Release builds with `/usr/bin/time -l` and MLX's own counters, 48 GB Apple silicon,
13 September 2026.

| holder | loaded when | released when | cost |
|---|---|---|---|
| speech model, Whisper large-v3 turbo on CoreML | launch, `loadSpeechModel()` | quit | +114 MB footprint loaded, 267 MB peak footprint and 340 MB peak resident mid-dictation; the weights are file-mapped, so macOS can drop them itself |
| suggestion model, Gemma 3 4B QAT on MLX | launch or the moment AI suggestions is turned on, only for somebody who turned it on | AI suggestions turned off; no query for 3 minutes on a Mac under 16 GB, 10 minutes otherwise; or quit | 2,485 MB of GPU memory, 3,036 MB at a pass's peak, 3,464 MB peak process footprint; anonymous, so nothing but a release frees it |
| MLX's buffer cache | during a pass | the end of every pass | capped at 256 MB, 0 MB between passes |
| the recording | the shortcut | the end of the dictation | at most 15 MB: 240 s at 16 kHz in 4-byte samples |
| clipboard thumbnails | the panel is drawn | least recently used first | at most 32 MB, see `Docs/clipboard-budget.md` |
| clipboard, history, dictionary and suggestion stores | launch | quit | under a megabyte of text each at measured sizes; the prediction corpus is SQLite on disk |

Clean-up runs in Apple's model process, not this one, and is not counted here.

### The budget

| state | 8 GB Mac | 16 GB Mac and up |
|---|---|---|
| idle, suggestions off | **≤ 300 MB** footprint | ≤ 300 MB |
| peak during a dictation, suggestions off | **≤ 400 MB** | ≤ 400 MB |
| suggestions on, between passes | ≤ 3.0 GB, and none of it under memory pressure | ≤ 3.0 GB |
| suggestions on, peak of a pass | ≤ 3.5 GB | ≤ 3.5 GB |
| after turning suggestions off | back to the idle line within a second | same |

The speech model fits inside the first two lines with room to spare, and it stays loaded:
reloading costs the next dictation 2–9 s, and about 150 s on the first load after a reboot
(`Docs/startup.md`), while its file-backed weights are exactly the memory macOS already
reclaims on its own.

The suggestion model is what the budget is about. On an 8 GB Mac its 3 GB is close to half of
all memory, which is why nothing loads it for somebody who never asked, and why turning the
feature off gives it back. `AppDelegate` releases it when the switch goes off, after any load
still running has landed, and `MLXCandidateScorer.release()` swaps out the weights (keeping the modules
and tokenizer, see "Reloads no longer quantise" below), drops the warmed instructions and the
vocabulary, and empties MLX's cache. Measured with
`uttrflow-bakeoff gpu-memory --release`:

| | MLX active | process footprint |
|---|---|---|
| loaded, after six passes and 5 s idle | 2,485 MB | 2,677 MB |
| one second after `release()` | 0 MB | 190 MB |

MLX holds no active memory after the release; the 190 MB left is the process with MLX and Metal initialised and has not been broken down further. Turning the
feature back on loads the weights again from disk: `gpu-memory --release` timed that reload at 3.2 s and 4.4 s in two runs, back to 2,485 MB active.

### When nothing is being typed

`IdleReleasingModel` lets the weights go when no suggestion has asked for the model within a
window chosen from `ProcessInfo.physicalMemory` by `IdleRelease.window`: 3 minutes on a Mac
with less than 16 GB, 10 minutes otherwise. The next query in a supported field loads it
again in the background; that moment's model suggestion stays quiet, as it does during any
load, and remembered completions are unaffected. A release the caller asked for — the switch
turned off — is never undone by a query. So on a small Mac the 3 GB is held while somebody is
typing, not through a meeting or a film.

### Under memory pressure

`MemoryPressureSource` watches the kernel's pressure events. At a warning or a critical
reading `AppDelegate` releases the suggestion model the same way, and the AI suggestions screen
says it is paused to free memory rather than going quiet. Once pressure is back to normal the
model waits for the calm to last before it loads again — two minutes the first time — and
`SuggestionModelPressure` doubles that wait, up to thirty minutes, each time a reload is
followed by pressure within thirty minutes. Without the wait, the 3 s reload of 2.5 GB is
exactly what pushes a small Mac straight back into pressure, and the model would load and
drop in a loop. A reload that holds for thirty minutes starts the wait over.

The speech model is left alone under pressure, for the reasons above.

## How the budget is enforced

Both budgets above are checked, not only stated. `make perf-budget` runs in `make verify`, needs
no build, no model and no window, and reads the source for the ways a budget has been broken
before. `Scripts/perf_budget_audit.py` holds the rules and prints every allowance with its reason
on every run:

| check | fails when |
|---|---|
| wakeups | a repeating `Timer`, repeating `DispatchSource` timer, display link or sleeping loop in product code has an interval under 500 ms, or one the audit cannot resolve, and is not listed with the reason it is not an idle cost |
| priority | the suggestion and local-model modules ask for more than utility priority, detach a task without one, or the app uses the suggestion model outside a `Discretionary` wrapper |
| motion | a `TimelineView`, `repeatForever`, phase or keyframe animator or repeating symbol effect reads neither `MotionBudget` nor `WindowAttention`, or is paused by a literal |
| cache | a model pass (`perform`, `generate`, `TokenIterator`, `ChatSession`) sits in no function that caps MLX's cache and clears it on exit, a `release()` does not clear it, or the cap is over 256 MB |
| counters | `ResourceBudget`'s limits differ from the table above |

`--self-test` injects one violation per check into the tree as read and fails unless the audit
catches it, so a rule that has stopped matching the code is found rather than trusted. A breach
already on `main` is listed under the issue that fixes it, and fails as stale once it is gone.

Memory itself can only be read with the models loaded, so `make perf-budget-models` runs
`uttrflow-bakeoff gpu-memory --release` and `uttrflow-bakeoff profile` and each exits non-zero
when a reading is over its line: every settled moment of a profile against the idle line, its
peak against a dictation's, each pass's peak and settled footprint against the suggestion lines,
and the footprint a second after a release against the idle line. `ResourceBudget` in
`UttrflowEval` is the one judge both use.

## Processor

Memory answers "will it fit". This is the other half — what it costs to run — and a table
of seconds cannot answer it. A dictation that finishes in 2.4 seconds having held four
cores busy has spent ten processor-seconds, and it is that figure, not the 2.4, that
decides whether the fans come on and what the battery does.

```
  length   audio   cpu s    cores   cpu s/audio s  kernel   instructions
  ──────────────────────────────────────────────────────────────────────
  short    3.42    0.28     0.16    0.08           13%      3.5 G
  medium   13.91   0.76     0.28    0.05           12%      8.8 G
  long     58.10   3.04     0.39    0.05           11%      35.0 G
```

**A dictation barely touches the processor.** Fifteen seconds of speech costs 0.76
processor-seconds. Across the whole profiling run — model load, thirteen dictations,
memory polled every 20 ms — the process averaged **0.21 of a core over 221 seconds**.

The reason is that the work is not on the processor. Whisper runs on the Neural Engine
through CoreML and the clean-up model is Apple's, in another process; Uttrflow's own
threads spend most of a dictation waiting for them. `cores` never reaching 0.4 is that
waiting, measured.

**This is the number that decides which Macs this product runs well on**, and it decides
it in an unexpected direction: not many, and not fast. A dictation needs a Neural Engine
far more than it needs cores, and every Apple silicon Mac has one. What it does *not*
tell you is how much slower a smaller Neural Engine is — see [limits](#what-these-numbers-are-not).

The counters are printed with the arithmetic left in so it can be checked: the run implied
**4.10 GHz at 3.82 instructions per cycle**, which is the right clock for this chip's
performance cores. A figure nothing like it would mean the times and the hardware counters
disagree and that every instruction count above should be thrown away.

### How much does a slower processor matter? Barely

The claim above — that this is not really a processor workload — is testable on one
machine, by taking the performance cores away. `taskpolicy -b` runs the profile at
background priority, which confines it to the efficiency cores. The implied clock falls
from **4.10 GHz to 1.87 GHz**, and the instruction counts come back identical to three
significant figures (3.5, 8.8, 35.1 G against 3.5, 8.8, 35.0 G), which is what says the
same work was done on a slower processor rather than different work being done.

| length | performance cores | efficiency cores only | slower by |
|---|---|---|---|
| short, 3.4 s of speech | 1.68 s | 1.67 s | — |
| medium, 13.9 s | 2.41 s | 3.11 s | 1.29× |
| long, 58.1 s | 7.36 s | 10.55 s | 1.43× |

**Less than half the clock speed costs between nothing and 43%.** A three-second
dictation is unchanged. If wall-clock time tracked processor speed the long passage would
have taken 16 seconds; it took 10.6.

That is the closest this Mac can come to answering "how will it feel on a smaller Mac",
and it answers only the processor half. It says a slower *processor* is close to
irrelevant. It says nothing about a smaller *Neural Engine*, which is the part actually
doing the work and the part that genuinely differs between an Air and a Pro — see
[limits](#what-these-numbers-are-not).

One thing the same run showed by accident: with the compile cache warm, loading the model
costs **5.68 processor-seconds at 0.98 cores** — a full core for six seconds. Cold it was
0.15 cores for 148 seconds. The two are not the same event and averaging them would
describe neither.

### A suggestion pass's tokenizer

A suggestion pass spent more processor time turning its prompt into tokens than running the
model (#427). `sample` of a Release `uttrflow-bakeoff gpu-memory` run put 35% of all on-CPU
samples in ICU's `RegexMatcher`, under `PreTrainedTokenizer.applyChatTemplate → encode →
String.split(by:)`. The tokenizer splits text on its added tokens with one alternation regex
before anything else, Gemma 3 declares 6,415 of them, and every pass rendered and tokenised the
whole prompt — the fixed instructions, the screen, the person's lines — to add one typed
character. Rendering the template itself, and building the message, are each under 1%.

`PromptTokens` tokenises the template's frame once, when the model loads, and each line of the
message once, keyed by its exact bytes; a pass pays only for the lines that changed. It is
token-identical to the whole template because every break it cuts at is a hard boundary for
this tokenizer: `\n` is an added token, every added token holding a line break is only line
breaks, none swallows whitespace, and the frame's edges are added tokens no first or last
character of the message can join. It checks each of those at load against `tokenizer.json`
and probe messages, and a message it cannot vouch for is tokenised whole. `PromptTokensTests`
holds it to the whole template over 3,000 random messages of boundary characters with the cache
shared between them, and over Gemma 3's own tokenizer where it is on disk
(`UTTRFLOW_TOKENIZER_PROOF=300`, run for #427, all identical). The keys are bytes because Swift
calls the two spellings of "é" one string and the tokenizer does not; that test fails on a
`String` key.

Measured 14 September 2026 on the M5 Pro at a load average of 45–240 from other builds, so the
processor figures are the ones to trust. One Release binary, the cache switched off by an
environment variable that was never committed, 100 passes each, every fourth cancelled, one
score a pass, two rounds:

| harness | processor a pass, before → after | tokenising the prompt a pass | pass p50 / p95 |
|---|---|---|---|
| `gpu-memory --typing`: one reply typed a character a pass under one screen | 1.54 s, 1.93 s → 0.31 s, 0.32 s | 1,111 ms, 1,494 ms → 7 ms, 6 ms | 2,244 / 2,565 ms → 425 / 828 ms |
| `gpu-memory`: a different screen every pass | 0.96 s, 0.92 s → 0.40 s, 0.38 s | 587 ms, 615 ms → 50 ms, 54 ms | 1,122 / 1,578 ms → 550 / 1,128 ms |

Per 100 keystroke-turns that is about 150–190 processor-seconds before and 31 after. All 75
completed passes of every run returned the same lines with the cache on and off, and the same
as a build of `main` before the change.

What is left is the score: `judgedTokens` tokenises the candidate twice, about 100 ms a pass
through the same regex, and that is now the largest tokenizer cost. The regex is the dependency's;
upstream it is huggingface/swift-transformers#383, with a fix open as #386, and nothing here
patches or bumps it.

### The processor time that is not the app's

Two costs sit outside the process and would be missed by any figure taken from inside it:

- **`ANECompilerService`, at 88% of a core for two and a half minutes**, the first time a
  given binary loads the model. Covered above.
- **`WindowServer`, at 35–49%**, for as long as the home page's animation was running.
  The app was committing a Core Animation transaction every display frame, and the window
  server has to do something with each one. Fixed with the animation itself, below.

## What it costs while nobody is using it

This is where the largest finding in this document is, and it is a bug rather than a
measurement.

Uttrflow is a login item and opens its window at launch, so "running, with the window
open, nobody touching it" is the state it spends nearly all of its life in. Measured on
the shipped bundle from outside, by the process's own cumulative processor time over a
minute:

```
  state                             before        after
  window visible and frontmost      97.5%         97.9%
  window covered by another app     ~98%          0.08%
  app hidden with cmd-H             98.2%         0.10%
  resident memory, all states       305 MB        309 MB
```

**Before the fix, a whole core, from login, indefinitely** — 58.5 processor-seconds every
60 seconds, holding steady over half an hour. Hiding the app with ⌘H did not help: 98.2%
with nothing on screen at all.

`sample` put the cause beyond doubt. 2852 of 3736 samples on the main thread were in
`__CFRunLoopDoSources0 → CA::Transaction::flush → NSDisplayCycleFlush → NSHostingView.layout()
→ ViewGraph.updateOutputs`, driven from `TimelineView` inside `ClipboardDemonstration` —
the home page's drawn demonstration of the paste. It asks to be redrawn every display
refresh, each redraw re-runs the layout of the card *and the window around it*, and it
keeps asking whether or not there is anybody to see it. SwiftUI does not stop it; that is
what the ⌘H row proves.

The fix is to stop when nothing can see it — `NSWindow.occlusionState`, plus the app-hidden
notifications, feeding `TimelineView`'s own `paused:`. Covered, hidden, minimised, on
another Space, or with a different page chosen in the sidebar, the cost goes from 97.5% of
a core to **0.08%**: about twelve hundred times less, for no change to anything anybody
sees.

### What is *not* fixed, stated plainly

**This section describes the state before #359.** With the window on screen and frontmost it
cost ~98% of a core. The pause could not help there, since somebody was looking at it, and one
redraw of this card was 8 ms of processor time, spent re-solving the whole window's layout
rather than the card's.

Capping the frame rate was tried and measured, window frontmost:

| redraw cap | cost |
|---|---|
| none (display rate, 120 Hz here) | 97.5% of a core |
| 60 a second | 91.7% |
| 10 a second | 26.4% |

Sixty buys 6%, which does not pay for any loss of smoothness on a ProMotion display, so
**no cap is shipped**. Ten buys three quarters of it and is visibly steppier on the panel's
rise — available as a deliberate trade, not taken here.

The real repair is structural: stop a redraw of one card from re-solving the root
geometry. `ViewThatFits` sat inside the per-frame closure and re-measured both candidate
arrangements on every frame, which was the obvious thing to move.

**It was attempted, and the obvious move is wrong.** Written down because it costs a build
and an hour to find out, and because it fails in the worst available way — silently, and
looking like a triumph.

Hoisting `ViewThatFits` above the clock means each of its two candidate arrangements has
to carry its own `TimelineView`. Do that and **the animation stops dead**: a `TimelineView`
inside a `ViewThatFits` candidate is never driven, even in the candidate that is chosen and
drawn. Nothing warns you. The card renders correctly, at whatever instant it was first
built, and simply never moves again.

The measurement then reports 0.05% of a core, down from 97.5%, which is exactly what a
spectacular fix would look like. What proved it was `sample`: **zero** `ClipboardDemonstration`
frames and **zero** `NSHostingView.layout` samples in three seconds. A frozen view and a
free view are the same number on the outside, so the frame count is the check that matters,
not the processor figure.

### Three ways this measurement lies, all of which look like success

Anybody re-measuring this card should confirm it is *animating* before believing any figure.
It is absent or frozen — and therefore free — in all of these:

- **The window is not frontmost.** This is the pause working correctly, and it is easy to
  trigger by accident: a shell command that steals focus back is enough. Check the frontmost
  application at both ends of the measurement, not just the start.
- **Permissions are blocked.** `HomePresentation` hides the demonstration whenever
  `MainPresenter.obstruction` finds one, and a rebuilt bundle has a new code signature and
  therefore no Accessibility grant. A freshly built copy of this app is *always* in that
  state until it is re-approved, so the card is not there to animate.
- **The card is below the fold.** It is the last thing in a `ScrollView`, under the orbit
  stage, the figures and today's list. At the default window size it is off screen, and
  off-screen means not drawn.

That gate needs a bundle that has been granted Accessibility, a window big enough to show
the card, and a way to hold focus — none of which were available in the session that found
this. The `sample`-based frame count above is the gate any attempt has to pass before its
processor figure means anything.

### What #288 changed, and why it was not the fix

`ViewThatFits` left the card: the arrangement is chosen by
`ClipboardDemonstrationMetrics.arrangement(forOfferedWidth:)` from a width measured once by
`onGeometryChange`. That was merged without the processor figure being re-taken, and on
hardware the card still cost a core. The per-frame re-measurement of two arrangements was real
but was not what the time went on. What the time went on was a redraw at the display's rate
in windows nobody was using, which the sections below cover.

### Why that pause was not enough

The pause above stopped the card only when `NSWindow.occlusionState` lost `.visible`, and
AppKit keeps `.visible` while any sliver of the window is on screen. The main window opens at
launch and usually sits partly uncovered behind whatever the user is working in, so the card
kept animating exactly where nobody was looking at it. Measured on the installed Release build
of 0.5.0 on 13 September 2026, with the user's real history on the page (#359):

| state | cost |
|---|---|
| window partly visible behind another app | 114–128% of a core |
| another app brought frontmost, window still partly visible | 83–100% |
| window fully covered | 0–1% |

macOS filed `cpu_resource` reports for it. `sample` put about 2,200 of 3,230 main-thread
samples in `NSHostingView.layout()`, under the card's drawing.

### What the card does now

Two changes, both in `Sources/Uttrflow/Main/`:

- **It moves only in the window being used.** `WindowAttention` animates when the view is
  shown, its window is key, the application is active and not hidden, and the window is on
  screen. `WindowVisibility.swift` feeds it from the occlusion, key-window, active and hidden
  notifications. Anywhere else the card rests on `ClipboardDemonstrationPhase.resting`, the
  panel open with the address row chosen, so a glance at a background window still shows what
  the feature is.
- **Its clock wakes when the drawing changes, not on every display frame.**
  `ClipboardDemonstrationMoments` is the card's `TimelineSchedule`. Of the eight-second loop,
  only the panel rising (0.9 s) and going (0.6 s) move continuously, and those got an
  instant every 1/120 s, now every 1/30 s (below). The typed line wakes once per character, and
  everything else is a still state that wakes once, at its boundary. That was 226 wakes a loop
  instead of 960 at 120 Hz. `ClipboardDemonstrationMomentsTests` checks that the instant drawn matches what the
  clock would show everywhere outside the moving stretches.

### Measured, before and after

Apple M5 Pro (Mac17,8), 48 GB, macOS 26.5.1 (25F80), built-in 120 Hz display. Both builds
come from `make app-dev` (Release configuration), `origin/main` at a8e747b against this change.
CPU is the per-second delta of the process's cumulative processor time, 30 samples per state.

A development build has no Accessibility or microphone grant, and `HomePresentation` hides
the card while a permission is missing, so both builds carried the same local-only harness,
never committed: the card shown regardless of permissions, a clipboard shortcut filled in
memory, launch reduced to opening Home, and the page scrolled to the bottom from inside the
process so the card is on screen in its real place. With no permission the page has no
figures or history list, so the window is lighter than a real one and the absolute figures
are lower than #359's. The ratios are the point.

| state | before (mean, range) | after (mean, range) |
|---|---|---|
| (a) window key and frontmost | 39.1% (28–61) | 11.3% (0–38) |
| (b) window partly visible, another app frontmost | 37.4% (28–75) | 0.1% (0–1) |
| (c) window fully covered | 0.0% (0–0) | 0.0% (0–1) |
| (d) app hidden | 0.0% (0–1) | 0.0% (0–1) |

The frontmost state was checked on each second's reading (key window, active application),
and (b) with another application frontmost and the window uncovered on half its width. A second
clean before-run of (a) read 37.7%. After the change, (a) is no longer flat: it reads 0–1% in
the still stretches and 25–40% in the second that holds the panel's rise, repeating every
eight seconds.

**The card still animates.** `sample` over three seconds of (a) found 27 frames in
`ClipboardDemonstration` after the change against 34 before, and 0 in (b), where it is meant
to be still. That is the frame-count gate from the section above, and it is what separates
this from the frozen kind of cheap.

### Tried while fixing it, and not kept

Each was measured with the card forced to animate, 30 seconds each, against the schedule
without per-character typing at 12.6–18.8% across two runs:

| attempt | cost |
|---|---|
| the document and panel in their own `NSHostingView`, so a frame cannot re-lay-out the window | 14.5% |
| the panel's rise and fade as SwiftUI animations instead of clock ticks | 12.9% |
| a constant shadow, with only the opacity animated | 13.8% |

None is distinguishable from noise of about ±5 points, so none is in the code. Per-character
typing is: over 64 seconds, back to back, it read 12.3% against 14.0% without it, in line
with its 26% fewer wakes. What remains while animating is roughly proportional to the number
of wakes, which is why the schedule is the lever, and why the frame budget below lowers the
rate during motion rather than anything else.

### Reduce Motion, Low Power Mode, thermal pressure and a frame budget

None of the app's continuous animations asked what the Mac wanted (#377). `MotionBudget` answers
that as a pure value from Reduce Motion and `EnergyConditions` (Low Power Mode and thermal
state), tested in `MotionBudgetTests`:

| | demonstration | working dots | dock frame cap |
|---|---|---|---|
| nothing asked | moves, 30 frames a second while the panel moves | walk | 60 a second |
| Reduce Motion | still frame | still, fully lit | 60 a second |
| Low Power Mode | still frame | walk | 20 a second, the meter's data rate |
| serious or critical thermal state | still frame | walk | 20 a second |

`WindowAttention` carries the budget, and `WindowVisibility.swift` re-evaluates it on
`NSProcessInfoPowerStateDidChange`, `ProcessInfo.thermalStateDidChangeNotification` and
`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` beside the window notices. The dock
reads `MotionBudgetObserver.shared`, which re-reads on the same three notices.

Counted headlessly by `ClipboardDemonstrationMomentsTests`, with the 39-character address line:

| schedule | wakes per eight-second loop | while the panel rises | while it goes |
|---|---|---|---|
| every display frame, 120 Hz | 960 | 108 | 72 |
| on change, motion at 120 Hz | 226 | 108 | 72 |
| on change, motion at 30 Hz | 91 | 27 | 18 |
| still, under any budget that stops it | 1 | 0 | 0 |

Wakes fall by 60% against the schedule above, and the section above found the cost roughly
proportional to wakes. **The processor figure for the 30 Hz cap has not been taken**: it needs
the harness and the frame-count gate described above, and until somebody runs them the 11.3%
row stands as the last measurement.

### A card the window cannot show (#421)

`WindowAttention` asked only about the window, so with the window key the card went on moving
wherever it was inside that window. It sits at the bottom of Home's `ScrollView`, in a plain
`VStack`, so it stays in the hierarchy when scrolled away and its `TimelineView` keeps waking. The
window opens at the top of Home, and at the default size the card is below the fold, so that is
the usual state of a window in use. `NSWindow.occlusionState` keeps `.visible` while any part of
the window is on screen, so a card moved past the display's edge was not caught either.

The rule now also needs `isViewVisible`: the part of the card inside its scroll view's bounds,
measured by SwiftUI (`onGeometryChange` with `bounds(of: .scrollView)`) and reduced by
`WindowAttention.uncoveredFrame`, has to overlap a display by an area
(`WindowAttention.isVisible`). The frame travels to `WindowVisibility.swift`'s reporting view
through a reference held in `@State`, so a scroll re-checks the rule without re-evaluating the
card's body. The window's move, resize and screen notices re-check it too.

Measured on 14 September 2026 on the Mac above, Release builds from `make app`: before is
`origin/main` at 5ca34e7, after is this change on 80b5820. The window was key in the active
application, raised through System Events, and processor time was counted only across 50 ms
steps where it was still frontmost. "Loop" is three eight-second stretches per state, so each
covers whole loops of the animation; "rise" is only the 0.9 s in which the panel rises, where
the card does the most work, over three to eight loops. A card counts as moving only when window
captures at 1.2, 1.5 and 1.8 s into the loop differ, and they did in every on-screen row.

| state, window key and frontmost | before, loop | before, rise | after, loop | after, rise |
|---|---|---|---|---|
| card on screen | 15.4% | 28.0% | 11.9% | 40.6–41.0% |
| card scrolled fully out of view | 18.4% | 33.2% | 1.9% | 0.9–3.2% |
| window shortened until the scroll view hides the card | — | — | — | 1.6% |
| card past the bottom of the display, top of the window on it | 11.6% | — | — | 1.1% |
| History page instead of Home, for comparison | 0.2% | 2.7% | — | — |

The after loop for the on-screen card was taken on a build carrying an earlier, discarded version
of this change (below), whose answer for an on-screen card is the same.

Unchanged by this, and measured on the before build with the card on Home: window partly visible
behind another application 0.02%, fully covered 0.13%, minimised 0.18%, closed 0.4% between
suggestion passes. The machine was otherwise in use, so the loop figures carry that noise; the
rise figures are the cleaner comparison.

**Tried and not kept: `NSView.visibleRect`.** The first version asked the reporting view, which
is the card's `background`, for its `visibleRect` and watched every enclosing `NSClipView`. It
does not see SwiftUI's scroll clipping: the scrolled-out card still cost 31.4% across the rise,
and 31.1% once the window was shortened below it.

### The clipboard poll

macOS offers no notification for a copy, so `PasteboardWatcher` reads the change count on a
timer, from login, for as long as the app runs. That makes it the largest steady wakeup source in
an idle Uttrflow, and its cost is wakeups rather than processor time. A stand-alone loop doing
exactly this, its own wakeups read with `proc_pid_rusage` over 30 s:

| cadence | wakeups a second | processor |
|---|---|---|
| 200 ms, no tolerance (before) | 4.8 | ≈ 0.04% of a core |
| 500 ms, 100 ms tolerance (now) | 1.7 | ≈ 0.02% |
| 1 s, 200 ms tolerance | 1.0 | ≈ 0.01% |

The poll was 200 ms because ⌘C followed by the panel shortcut is a single hand movement. That race
is now closed where it happens: `toggleQuickPanel` calls `PasteboardWatcher.catchUp` before it reads
the clips, so a copy made a moment before is always in the panel whatever the cadence. The poll
therefore runs at 500 ms, with a fifth of that as tolerance, at utility priority.

What this gives up: the clipboard holds only its latest contents, so two copies inside one
interval keep only the second. That window grew from 200 ms to 500 ms.

### Classifying a copy (#460)

Every text copy up to the 2 MB clip bound goes through `ClipKindDetector.kind(of:)`. Where it runs:
the watcher calls it on its own actor, inside the utility-priority task `AppDelegate` starts, so
never on the main thread; opening the panel awaits `catchUp`, which classifies a pending copy while
the panel waits. A clip typed into the panel or kept from a dictation was classified on the main
actor, and now goes through `ClipKindDetector.classify(_:)`, a detached utility task awaited through
a continuation so the wait does not raise its priority.

After #443 the reading was linear, and still seconds per copy. Processor time for one
`kind(of:)` call, release build, one core, M5 Pro, 14 September 2026, before (main at #458) and
after; an 8 GB M1 Air takes roughly twice as long:

| input | 16 KB | 256 KB | 1 MB | 2 MB |
|---|---|---|---|---|
| code | 0.020 → 0.000 s | 0.267 → 0.002 s | 1.034 → 0.007 s | 2.122 → 0.013 s |
| prose | 0.041 → 0.002 s | 0.656 → 0.006 s | 2.615 → 0.012 s | 5.169 → 0.020 s |
| minified JavaScript, one line | 0.019 → 0.001 s | 0.300 → 0.004 s | 1.167 → 0.016 s | 2.303 → 0.029 s |
| base64, 76 columns | 0.027 → 0.007 s | 0.447 → 0.031 s | 1.744 → 0.020 s | 3.533 → 0.057 s |
| base64, one line | 0.016 → 0.000 s | 0.282 → 0.002 s | 1.104 → 0.015 s | 2.214 → 0.030 s |
| logs | 0.043 → 0.005 s | 0.700 → 0.026 s | 2.710 → 0.052 s | 5.479 → 0.085 s |
| CSV | 0.041 → 0.004 s | 0.656 → 0.020 s | 2.602 → 0.024 s | 5.173 → 0.029 s |
| hex dump | 0.044 → 0.014 s | 0.742 → 0.060 s | 2.902 → 0.065 s | 1.995 → 0.014 s |
| hex, one line | 0.017 → 0.000 s | 0.261 → 0.002 s | 1.037 → 0.007 s | 2.066 → 0.013 s |

Wall clock matched processor time to within a few percent in every row; the call is single-threaded.
Before, a megabyte of prose spent 0.69 s in the vendor-key pattern, 0.20 s in the card-number
pattern and 1.65 s in `CodeShapes`, which read the whole clip with ten patterns and counted every
signal even after two were found.

What changed:

- **The secret scan still reads every byte**, and answers exactly as before; the vendor-key and
  card-number patterns are handed a window at each literal prefix or long digit run rather than
  the clip. See `Docs/clipboard-secrets.md`.
- **The code-shape signals read a sample of a large clip.** Up to 64 KB a clip is read whole.
  Above that, `CodeSample` reads its first and last 16 KB and sixteen 2 KB windows spread evenly
  between, each trimmed to whole lines where it holds a line break. The whole-clip checks that
  cost nothing (a shebang, an import on the first line, a one-line shell command) still see the
  whole clip.
- **Two signals end the count**, cheapest first, and a pattern is skipped when the bytes lack a
  literal it cannot match without.

`ClipClassifyScalingTests` counts the bytes handed to the code-shape signals and the characters
handed to the two secret patterns, so the bound is a count rather than a clock: the first stays at
the sample's size for 256 KB, 1 MB and 2 MB clips, and the second is zero for a clip with no
prefix and no long digit run. On the code before this change both grow with the clip.

**What sampling gives up, measured.** A differential run kept the whole-clip classifier as the
oracle over 50,795 clips (460 MB): 20,000 random strings and 10,000 planted secrets from #443's
set, 18,000 realistic clips up to 32 KB and 2,000 of 32–64 KB (code, prose, minified, base64,
logs, CSV, hex, Markdown with code blocks), 300 of 64 KB–2 MB, and every planted shape at the
start, middle and end of 256 KB clips, with secrets and code snippets spliced in at random.

- **The secret verdict differed on none**, at any size.
- **The kind differed on 32, all above 64 KB, all code becoming text.** Twelve were base64 in
  76-column lines, which the whole-clip reading called code because somewhere in a quarter of a
  megabyte a line began `//` and another held `++`. Twenty were prose, logs, CSV or a hex dump
  with one to three lines of code spliced in between the sampled windows; the whole-clip reading
  called the whole document code on the strength of those lines.
- **Below 64 KB nothing differed.** `ClipKindOracleTests` runs 50,000 random, planted and realistic
  clips below it against the oracle on every `make verify`.

A secret beyond the sample is not a trade-off here, because nothing about secrets is sampled.

## What is paid before anybody speaks

`AppDelegate` calls `pipeline.prepare()` at launch, which loads the speech model. So every
login pays 4–9 seconds of loading and **holds 219 MB of footprint / 409 MB of resident
memory for the whole session**, whether or not the user ever dictates — and the app is a
clipboard manager that many users will open for the clipboard alone.

`BackedSpeechEngine.transcribe` already loads on demand if nobody prepared it, so the
launch-time call is an optimisation rather than a requirement: removing it would return
that memory to anyone who does not dictate, at the price of making their first dictation
4–9 seconds slower. Which of those to prefer is a product decision and is recorded here
rather than taken.

## The leak check — **PASS**

Ten consecutive medium dictations, then thirty, footprint read after each. The tool
prints one reading per line; the thirty below are re-wrapped into three columns.

```
Leak check — 30 consecutive dictations
  1  193.7 MB     11  156.9 MB     21  157.0 MB
  2  194.0 MB     12  156.9 MB     22  157.0 MB
  3  194.1 MB     13  157.0 MB     23  138.5 MB
  4  194.0 MB     14  156.9 MB     24  138.4 MB
  5  184.0 MB     15  156.9 MB     25  138.4 MB
  6  184.0 MB     16  156.9 MB     26  138.4 MB
  7  184.1 MB     17  156.9 MB     27  138.5 MB
  8  156.8 MB     18  156.9 MB     28  138.9 MB
  9  156.9 MB     19  156.9 MB     29  138.9 MB
  10 156.9 MB     20  157.0 MB     30  138.9 MB

  growth           -54.8 MB over 29 dictations (-1.9 MB each)
  never fell back  no
  allowance        33.6 MB
  verdict          CLEAN
```

Memory does not climb. It steps *down* three times as the allocator returns pages,
ending 54.8 MB below where it started. The ten-dictation run agrees: −34.4 MB.

The verdict is decided by rules stated in code, not by reading the column:

- **clean** — total growth stayed inside the allowance (32 MiB over the run, which is
  about 3 MB per dictation, or a third of a gigabyte for someone dictating a hundred
  times in a working day).
- **suspect** — grew past the allowance but fell back at least once. Could be a
  long-lived cache settling; only a longer run tells.
- **leaking** — grew past the allowance and never once fell back.
- **undetermined** — fewer than three readings. Two points are a line whatever they are.

### What `leaks` reports on the running app

`leaks $(pgrep -x Uttrflow)` on a release build (#411) found three groups, none of them growing
with time: 3,420 leaked nodes and 583 KB at one minute, the same at 92 minutes.

| Group | Size | Owner | State |
|---|---|---|---|
| `OnboardingFlow` cycle | 2.4 KB per onboarding controller | ours | fixed |
| `mlx::core::array::ArrayDesc` cycles | 0.4–1.7 MB on the first load only | MLX | reloads fixed here, first load upstream |
| `NSXPCConnection` cycles (AppIntents daemon) | 4.7 KB | the system | not ours |

**The onboarding cycle.** `OnboardingModel` set `flow.onChange` to a closure that captured
`self` weakly but the `flow` argument strongly, so the flow held a closure that held the flow.
The app builds one controller at launch only to read `isRequired`, and every later Sign In
builds another; each leaked its flow, network probe, installer and model. The closure now
reads the flow through `self`. `WindowLifetimeTests` fails on the old code.

**The MLX cycles.** Every root is allocated in `mlx::core::affine_quantize`, reached from
mlx-swift-lm's `loadWeights` → `quantize(model:)` → `QuantizedLinear` / `QuantizedEmbedding`.
Quantizing makes three sibling arrays (weights, scales, biases) that hold each other.
`loadWeights` then replaces them, still unevaluated, with the stored weights through
`model.update(parameters:)`, which assigns through `mlx_array_set` → `array::operator=`. In
MLX up to v0.32.2 assignment skips the check in `~array` that breaks a sibling cycle, so the
three stay alive holding each other. The fix is upstream in MLX (pull request 4453, "Break the
sibling cycle when an array is released by assignment"), merged after v0.32.2 and not yet in
any mlx-swift release or branch; mlx-swift 0.31.6 and mlx-swift-lm 3.31.4, which this app
pins, are the latest releases of both.

The GPU buffers are not part of it. It is CPU bookkeeping, paid on every call to
`loadWeights` — and the idle release reloads the suggestion model after every idle window,
so it grew through a day of ordinary use.

**Reloads no longer quantise.** `ReloadableWeights` builds the modules through
`QuantizedLoad` on the first load only. A release keeps the modules and swaps every
weight for an unevaluated `zeros` placeholder of the same shape, which holds no buffer; a
reload reads the safetensors, runs the model's `sanitize`, and assigns them with
`update(parameters:verify: .all)`, so every shape is still checked. Nothing on that path makes a
sibling array, so nothing is left to leak. A release waits for any pass still using the model,
and a pass stops its decode before it ends, so no step reads a weight that was swapped out.

`uttrflow-bakeoff reload-leaks` loads Gemma 3 4B, then releases and reloads it in one process,
running `leaks` on itself at 1, 5 and 20 reloads (Release build, 48 GB Apple silicon):

| | leaks | leaked bytes | median reload | footprint after the last release |
|---|---|---|---|---|
| before, first load | 12,181 | 2.35 MB | 5.8 s (first) | — |
| before, 1 reload | 18,100 | 3.43 MB | 4.95 s | 347 MB |
| before, 5 reloads | 47,656 | 9.01 MB | 4.74 s | 390 MB |
| before, 20 reloads | 144,034 | 27.14 MB | 4.96 s | 640 MB |
| after, first load | 3,609 | 0.70 MB | 4.9 s (first) | — |
| after, 1 reload | 3,609 | 0.70 MB | 3.75 s | 337 MB |
| after, 5 reloads | 3,609 | 0.70 MB | 3.91 s | 341 MB |
| after, 20 reloads | 3,608 | 0.70 MB | 3.93 s | 343 MB |

Before, each reload added about 6,400–7,400 leaks and 1.2–1.4 MB, and the footprint left after a
release crept up with them. After, the count stays at what the first load leaves, a reload is
about a second faster because no module is built, and the same fixed prompt gives the same answer
after every reload. MLX's active memory after a release is still 0 MB (`gpu-memory --release`).

**The first load does not quantise either.** `QuantizedLoad` creates the model from the same
type registry, reads the safetensors headers, and swaps each linear layer that the snapshot stores
with scales in a floating type, and that the configuration quantizes, for a `QuantizedLinear` of
unevaluated zeros before `loadWeights` runs; any other layer is left to the library, so the quantiser
skips it and the stored weights replace the zeros with the same shape checks. It then evaluates
MLX's global random key, which every random initial weight split lazily into a chain of siblings.
Only the embedding still goes through the quantiser, because `QuantizedEmbedding` has no
initializer that takes arrays. The clean-up model loads through the same path. Measured on top of
the table above, with the same command:

| | leaks | leaked bytes | footprint after the last release |
|---|---|---|---|
| reloadable weights alone, first load | 10,808 | 2.06 MB | 364 MB |
| reloadable weights alone, 5 reloads | 10,950 | 2.09 MB | 365 MB |
| with `QuantizedLoad`, first load | 75 | 14 KB | 339 MB |
| with `QuantizedLoad`, 5 reloads | 75 | 14 KB | 340 MB |

The same fixed prompt gives the same answer throughout.

Other ways round it, and why they were not taken. Evaluating the quantised arrays before they are
replaced would break the cycle, but `loadWeights` gives no moment between the two, and evaluating
them would quantise the randomly initialised full-precision weights — gigabytes of work thrown
away. No loader option skips the quantiser: `LLMModelFactory` always passes the configuration's
quantisation to `loadWeights`, and without it the stored `scales` fail verification, which is why
`QuantizedLoad` builds the quantized layers itself instead. Releasing
less often would only slow the growth, and would hold 3 GB longer on the small Macs the idle
release exists for.

**The step after visiting every page.** The 125-minute reading rose to 5,224 nodes and
914 KB. The whole rise was one more `ArrayDesc` cycle of 311 KB plus a few nodes on existing
roots; no Swift object from any page appeared in the report. Between those two readings the
suggestion card was also driven, so the new root is a model graph and not a page. Its stack
was not captured. `WindowLifetimeTests` draws every main-window page and Settings section
five times and checks that each window's model is released.

## Latency

Median and slowest of three runs each, with the model already loaded.

```
  length   audio   runs  end-to-end          transcription       transformation
  ───────────────────────────────────────────────────────────────────────────────
  short    3.42    3     1.68      2.23      0.54      1.39      0.85      1.15
  medium   13.91   3     2.41      3.31      1.06      1.07      1.33      2.25
  long     58.10   3     7.36      8.74      4.07      5.14      3.29      3.61
```

Every length is faster than the 23 August run — the medium case by a third — and that is
a real gain rather than a quieter machine, because this run was taken on a *busier* one
(load average 24 against an idle Mac in August). Clean-up moved most: 2.06 s to 1.33 s on
the medium passage.

Capture and insertion are **not measured** here and are not shown as zero: this harness
reads audio off disk, so there is no capture to time, and it never types into another
app. Capture in the real product is bounded by how long the speaker talks; insertion is
a paste.

**The microphone opening is the exception, and it is now timed in the product.** Pressing the
shortcut builds the audio graph, queries the input format, installs a tap and starts the engine
before a single sample exists — and the user is already speaking while that runs. It is charged to
`microphoneOpen`, a stage of its own rather than part of `capture`, which times the ending of a
recording. **No figure is recorded here yet**: taking one needs a Mac that can run
`uttrflow-dev record` and compare the first sample's timestamp against key-down, and it should be
written down here when somebody does. Whether the opening swallows a syllable or is imperceptible
decides whether anything about the audio graph's lifetime is worth changing — and the obvious
change, keeping an input graph alive between recordings, is a privacy question before it is a
latency one.

Dictionary correction and snippet expansion are not here either, for a different reason:
this table predates them. Both are now timed in the product and appear on the Diagnostics
page, and this harness will show them at the next run. Correction's cost is known from
elsewhere — `CorrectionEngineTests` measures a 39-word dictation against 10,000 dictionary
entries at **0.72 ms**, and asserts a 25 ms bound as an order-of-magnitude guard. Snippet
expansion has never been timed, so it has no budget: proposing one before measuring it
would be inventing a number, which is the thing this document exists not to do.

The doubtful-word candidate step is budgeted at under 5 ms a piece (`Docs/cleanup-design.md`)
and measures around 2 ms on a quiet Mac, but **its test does not time it**: a wall-clock bound
failed under a sanitizer build and a busy machine on changes that never touched it (#136, #373).
`DoubtfulWordsTests` counts Double Metaphone encodings instead, through
`DoubleMetaphone.tally`, and fails when ten times the screen words costs more than one encoding
each, or a doubtful run costs more than four — the shape of re-reading the screen once per run,
which is what made the step slow. A number for the step belongs in this table from a profile
run, not in a gate.

A fifteen-second dictation is finished 3.6 seconds after the speaker stops — about
4× real time. Roughly 40% of that is transcription and 55% is Apple's clean-up pass.

### Cost does not grow evenly — transcription steps every 30 seconds

*Measured on 23 August 2026. The 28 August run re-confirmed the verdict —* superLinear
*for transcription, linear for clean-up — but did not repeat the boundary timings below.*

Marginal cost, in extra seconds of work per extra second of speech:

```
  end-to-end        short→medium 0.142   medium→long 0.162   linear
  transcription     short→medium 0.069   medium→long 0.093   superLinear
  transformation    short→medium 0.070   medium→long 0.070   linear
```

Clean-up is flat: 0.070 either side, so the language model costs the same per second of
speech whether the utterance is short or long. Transcription is not — the last stretch
of the long passage costs 35% more per second than the first.

It is a **step, not a curve**, and the step is Whisper's thirty-second window. Timed
either side of the boundary, three runs each:

| audio | transcription |
|---|---|
| 24.96 s | 2.12 / 2.14 / 2.15 s |
| 33.75 s | 3.22 / 3.25 / 3.28 s |

Those 8.8 extra seconds of speech cost 1.14 s, against the 0.61 s that the within-window
rate of 0.069 s/s predicts. The extra ≈0.5 s is a second encoder pass over a window that
is mostly padding. A 31-second dictation therefore costs about the same as a 59-second
one, and a two-minute dictation costs four encoder passes.

**What this means in practice**: a fifteen-second test does predict a thirty-second
dictation, and does not predict a two-minute one. Fitting the figures above, a dictation
costs roughly **1.6 s fixed, plus 0.14 s per second of speech, plus 0.5 s for every
thirty-second window after the first**. Most of the fixed 1.6 s is the clean-up model
starting work (1.1 s of it) rather than the recogniser (0.55 s). That predicts 10.4 s for
the 58-second passage against the 10.74 s measured.

## First run against warm

```
  first load in this process    148.31 s      21.64 processor-seconds · 0.15 cores
  warm load, same process       8.88 s
```

**The first load in that run was the cold one, and it took two and a half minutes.** This
was not planned — the earlier run measured 4.23 s and recorded that "the genuinely cold
first run is not measured" as a gap. It has now measured itself, because a freshly built
binary does not inherit the Neural Engine's compiled copy of the model.

The shape of it is the whole story. Of 148 seconds, the app's own process spent **21.6
processor-seconds — 0.15 of a core.** It was not working; it was waiting. The work was in
`ANECompilerService`, a system daemon, measured at **88% of a core** (26.3 processor-seconds
per 30 s of wall clock) for the duration. Nothing in the app's own figures would ever show
this, which is why it went unnoticed for a week.

Once that compile is cached, a second load in the same process is 8.88 s, and the earlier
run's four separate processes agree that later loads land around 4 s. So there are three
different numbers hiding behind "loading the model", and quoting the wrong one describes a
wait nobody has:

| | seconds | who pays it |
|---|---|---|
| Neural Engine compile cache empty | ~148 | first launch after install, and after anything that changes the binary or the OS |
| a fresh process, cache warm | 4–9 | every login |
| a second recogniser in a live process | 4–9 | nobody — the app builds one and keeps it |

**There is no meaningful warm-up saving within a process.** Loading is CoreML preparing
four `.mlmodelc` bundles and it pays that every time a recogniser is constructed, so the
recogniser must be constructed **once** and kept. It already is — `BackedSpeechEngine`
loads once and guards it.

## Reading a terminal line for its prompt

`ShellPrompt.input` runs on the main actor each suggestion turn in a terminal, so its cost is
bounded rather than left to the length of the line. It reads the line once, carrying forward
what each terminator needs to know about the text before it, and looks for a prompt only in
the first `ShellPrompt.searchLimit` (4,096) characters, since a prompt is short and a pasted
line need not be. A terminator past that point is not taken for a prompt.

Release build, a line of `ab# ` repeated, best of 20 runs (one run at 100 KB and over), on a
machine at load average 100 to 275, so the old column is inflated and its growth is not:

| line | before | after |
|---|---|---|
| 1 KB | 0.32 ms | 0.05 ms |
| 10 KB | 27 ms | 0.20 ms |
| 100 KB | 15.3 s | 0.37 ms |
| 1 MB | not run (quadratic, extrapolated at about 25 minutes) | 0.36 ms |

`ShellPromptScalingTests` counts characters read through `ShellPrompt.tally` rather than
timing: the previous reading took 2,004,000 reads for a 4,000-character line.

## Disk

```
  speech model                  648.4 MB
  application                   22.5 MB
  total                         671.0 MB
```

The model is measured on disk (645.7 MB across 4 `.mlmodelc` bundles plus two JSON
files), not taken from the catalogue. The application is the signed bundle from
`make app`. A fresh install is therefore **660 MB**, of which 98% is the speech model
and all of it is downloaded on first launch rather than shipped.

## Showing what a formatter changed

The formatting sheet diffs the clip against the formatter's output once per presentation, on
the main actor, and a kept clip may be 2 MB. `TextDiff` finds the fewest changed lines with a
edit-distance search over layers of furthest-reaching points, as in the O(n × d) algorithm,
whose memory grows with the changes rather than with the product of the two texts' lengths. It
then walks from the top choosing at each change exactly what the full table did: equal lines
first, and a removal before an addition whenever both are shortest. The walk needs the layers
deepest first, so every 32nd layer is kept and each stretch of 32 is rebuilt from it. That
costs about one more pass, and the kept layers grow with the square of the changes, about
d² / 64 integers: 2 MB at the 4,000-change limit. Every public entry point goes through that
limit.

`TextDiff.compare` refuses up front a text over 20,000 lines or 1 MB, and stops looking past
4,000 changed lines; the sheet then states both line counts instead of a diff.

Release build, best single run, peak footprint from `/usr/bin/time -l`, on a machine at load
average 80 to 250. "Every line" indents all of them, "one in fifty" indents every fiftieth:

| lines | shape | before | after |
|---|---|---|---|
| 100 | every line | 0.3 ms, 2.0 MB | 0.8 ms, 2.1 MB |
| 1,000 | every line | 12 ms, 10.6 MB | 13 ms, 6.9 MB |
| 1,999 | every line, 3,998 changes | 42 ms, 36 MB | 53 ms, 12.7 MB |
| 5,000 | every line | 1.16 s, 308 MB | 34 ms, 6.9 MB, too large |
| 20,000 | every line | 9.9 s, 3.9 GB | 38 ms, 14 MB, too large |
| 1,000 | one in fifty | 9.8 ms, 10.3 MB | 0.6 ms, 2.3 MB |
| 5,000 | one in fifty | 231 ms, 341 MB | 3.0 ms, 3.5 MB |
| 20,000 | one in fifty | 7.3 s, 4.1 GB | 14 ms, 10 MB |

Both columns are what one sheet costs: before, that was two runs of the table.
`TextDiffScalingTests` counts steps through `TextDiff.tally` rather than timing, and compares
the diff with the table on 20,000 random small pairs.

## AI suggestions under Low Power Mode and thermal pressure

A suggestion pass is the most expensive thing tab-to-complete does. Measured with
`uttrflow-bakeoff complete --fixtures --model gemma3`, release build, under `/usr/bin/time -l`:
30 fixtures cost 22.96 processor-seconds and one cost 4.09, so each pass past the first is
**0.65 processor-seconds and 11.3 G instructions** on this machine, p50 784 ms. Scaled to an M1's
performance cores that is about 1.1 processor-seconds per paused line. A debug build costs twice
that, so measure this in release.

It is also discretionary: the corpus still offers what it remembers without it. So the app hands
`SuggestionCoordinator` its model wrapped in `DiscretionaryGenerator`, which:

- runs every pass in a utility task, resumed through a continuation so the awaiting turn does not
  raise the pass back to its own priority, with the caller's cancellation passed on;
- reports itself not ready, and starts no pass, while `EnergyConditions.current()` says the Mac is
  in Low Power Mode or at serious or critical thermal pressure.

Scoring a remembered candidate is left as it was: it is one forward pass, raced against a deadline,
and slowing it would turn a slow answer into a refused candidate.

## Dictation end to end: the words and the wait

`uttrflow-dev bench` plays clips through `DictationPipeline` exactly as a held key would — the
shipping router, early transcription, the piece joiner — and prints one JSON line per dictation:
the text, how long the wait after key-up was, each recognition and each tidy with its own start
and end, processor seconds, and the peak footprint sampled every 20 ms.
`Scripts/dictation_bench.py` builds the corpus, writes the jobs and scores a run. Everything
below is one run of the commands under [re-running it](#re-running-it), taken on
**14 September 2026** at `1cfd688`, Release build, the same M5 Pro, load average 6–30.

**One process loads the recogniser once and plays every clip.** Separate processes, one per clip,
stall each other: every one of them compiles for the Neural Engine at the same moment, and a
freshly built binary does not inherit the compiled copy — 205 s for this run's first load, and
527–882 s on the same day under a load average of 100–200. `uttrflow-dev dictate` is one clip per
process, which is why it cannot run a corpus.

**The corpus is synthetic and invented.** `say` voices for US, UK and Indian English and for
Hindi; 139 clips and 30.6 minutes of speech: replies of one to four words, passages of 5 s to
2 min (with a 0.9 s breath every third sentence from 30 s up, and one 60 s passage without), numbers,
email addresses on `example.com`, code identifiers, invented proper nouns with and without a
vocabulary, Hinglish read in the Latin alphabet, spoken punctuation, self-corrections, the committed
`TranscriptionCorpus` passages, and ten clips again with brown noise at 20 and 10 dB SNR, 24 dB
quieter and 12 dB hotter (clipping). No recording of a person is involved.

**Two word error rates.** *Raw* is the recogniser's pieces joined, against what was said; *final*
is the inserted text, against what should be typed. Both lower-case, drop punctuation, spell
numerals, and split identifiers and addresses into words, so "3.5%" and "three point five percent"
agree; neither sees capitals or punctuation. Hindi is scored against the Devanagari passage and the
romanised one, whichever is closer.

### Word error rate

Each clip run all at once, with the shipping router.

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
| `TranscriptionCorpus`, Hindi | 6 | 9.0% | 9.0% |
| `TranscriptionCorpus`, Hinglish | 6 | 33.9% | 33.9% |
| Hinglish read in the Latin alphabet | 3 | 169.8% | 62.8% |

| voice | clips | raw | final |
|---|---|---|---|
| US English | 31 | 2.1% | 2.2% |
| UK English | 27 | 2.3% | 2.4% |
| Indian English | 26 | 3.5% | 3.3% |

| audio, over the same ten clips | raw | final |
|---|---|---|
| as synthesised | 2.4% | 2.4% |
| brown noise, 20 dB SNR | 2.1% | 2.1% |
| brown noise, 10 dB SNR | 2.7% | 2.9% |
| 24 dB quieter | 2.9% | 2.9% |
| 12 dB hotter, clipping | 3.4% | 3.4% |

What the rows say, read against the clips rather than the percentages:

- **A vocabulary is worth what it costs.** Invented names go from 28% to none wrong when they are
  in the prompt. The cost is below.
- **Hinglish loses to the alphabet, not to the words.** The recogniser writes Hinglish in
  Devanagari, "deploy" and "issue" included, so a Latin-alphabet reference scores it as nearly all
  wrong while the words are right. The tidier romanises it when Apple's model accepts the passage,
  which takes 170% to 63%; it declined most Hindi passages outright (issue 445), which was measured
  before the rules romanised too (`Docs/latin-output.md`).
- **Numbers and names are the English errors.** "4,250 dollars and 75 cents" is written "$4,250.75"
  (fair, but counted); "Jaxvale" becomes "Jack's Vale". Code identifiers are written as the
  recogniser chose to join them; "src" is heard as "source".
- **Noise barely registers** at these levels on synthetic speech. One exception is a pattern
  rather than a rate: "Ship it" at 10 dB SNR came back "Shit is." in one run and as nothing in
  the next, on the same audio.
- **The tidier changed the words of 2 of 120 English clips.** It removed a stray quotation mark
  the recogniser left, and turned "thick" into "theek" in a noisy clip. A third clip differed
  because the recogniser heard it differently on the two runs (the "Ship it" above). Every other
  English dictation came out identical to the rules pinned alone, which is what issue 447 acts on
  for replies.

### The wait

**All at once** hands the whole file over and releases the key: every piece is recognised and
tidied after key-up, which is what a retry does and the worst case for a dictation. **Real time**
plays the file at speaking pace, so early transcription works ahead while the key is held. The wait
is key-up to the words being ready; recognising and tidying are each dictation's total across all
its pieces, early ones included, so in real time they can exceed the wait.

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
  measured. Issue 447.
- **Processor time is 0.03 s per second of speech** for anything over five seconds, inside the
  0.1 budget above. A reply costs more per second (0.11) because the encoder always reads a full
  30-second window.
- **Peak footprint stays under 400 MB**, the dictation budget above; the highest was 372 MB, during
  a two-minute real-time dictation.

### What the recognising time is made of

WhisperKit measures its own stages and reports them in `TranscriptionResult.timings`. Read with a
temporary print over 528 decodes of the same corpus, not part of the harness:

- **Decoder steps are about four fifths of it**, one Neural Engine call per token, 20 ms each on a
  quiet machine and 37 ms under a load average of 100–200. The encoder is about a sixth, roughly
  0.28 s per 30-second window.
- **Everything on the processor around the steps is under 5%** together: the key-value cache copy,
  logits filtering, sampling and word timestamps.
- **The temperature fallback never fired** in 528 decodes, so the fallback settings cost nothing on
  this corpus and cannot be tuned against it.
- **A vocabulary costs one decoder step per prompt token, every piece.** Four or five invented names
  are 20–26 tokens and took the median recognition of a 4.6 s clip from 1.61 s to 2.50 s under load;
  at 20 ms a step a full 111-token prompt is about 2.2 s more for every piece, before the first word.

### Launch

| | seconds | processor seconds | footprint once loaded |
|---|---|---|---|
| first load of a freshly built binary, load average 8–80 | 205–254 | 25–26 | 156–222 MB |
| a later process, compiled copy cached, WhisperKit's prewarm on (shipping) | 2.2–2.5 | 2.2 | 109 MB |
| the same without prewarm | 1.2–1.3 | 1.2 | 95 MB |

The first dictation after a warm launch waited 1.05 s against 1.02–1.03 s for the next two, so
prewarm buys nothing a warm launch can see. What it buys on a cold one — WhisperKit prewarms to
keep the compile's peak memory down — was not measured, so it stays on.

### Measured and not taken

- **The GPU for the encoder and decoder.** Recognition was about 30% faster (a 15 s clip 0.95 s
  against 1.33 s) and the footprint was **3.4 GB** against 250 MB, with a first recognition after
  launch of 2.4–8.1 s while shaders warmed. Twelve times the memory budget on an 8 GB Mac.
- **Skipping Apple's model for longer dictations.** Identical to the rules on 117 of 120 synthetic
  English clips, and that tidier time is most of the all-at-once wait. Synthetic speech has none of
  the pauses, fillers and slips a person's does, so this is not evidence that real dictation would
  come out the same; it wants the recorded corpus.
- **A shorter vocabulary prompt.** The cost above is real and so is the accuracy it buys; trading
  one for the other wants measuring on vocabularies of the size people keep.

## What these numbers are not

Stated rather than estimated around, because an invented figure in a performance
document is worse than a gap.

- **Not a release build.** `make bakeoff` builds debug, which is what the Makefile
  prescribes and what anyone re-running this will get. Model inference is unaffected —
  it happens inside CoreML and MLX — but the Swift around it is unoptimised, so the
  fixed per-dictation overhead is a ceiling rather than a measurement.
- **One Mac, and a fast one.** Everything here is an M5 Pro. The figures that transfer to
  a Mac nobody measured are the processor-seconds and the instruction counts, because the
  work is the same work; the wall-clock seconds do not, because most of a dictation is
  Neural Engine time and a smaller Neural Engine is slower by a factor this document
  cannot state. Re-run `make bakeoff ARGS="profile"` on the target Mac rather than
  scaling these.
- **The download is not measured.** The first run a real user meets is dominated by
  fetching 648 MB, which is network-bound and says nothing about the machine.
- **Capture and insertion are not timed.** No microphone is touched here by design.
- **Correction and snippet expansion are not in the table above.** They are measured in
  the product; this harness has not been re-run since they were added.
- **The local MLX language model is not profiled.** None is installed on this Mac, and
  the shipping router reaches Apple's on-device model first, which is what was measured.
  `uttrflow-bakeoff footprint` is the command that answers "do both models fit at once",
  and it downloads a model to do so.
- **Three runs per length is a small sample.** The medians are stable to about ±5% across
  repeat invocations; treat differences smaller than that as noise. The leak check is the
  one figure with a real sample behind it.
- **The machine was busy.** The 28 August profile ran at a load average between 7 and 24,
  because other work was building on the same Mac. That inflates the wall-clock column
  and leaves the processor-seconds column almost alone — work is work — which is part of
  why the two are reported separately. The idle measurements were taken on a quiet
  machine (load 2–4) and each is a full minute of the process's own cumulative processor
  time, so they are the most trustworthy figures here.
- **The idle figures are of the real, signed application**, watched from outside with
  `ps`, not of the harness. Nothing else in this document is.
- **Synthesised speech is not human speech.** It is more evenly paced and cleaner, which
  makes transcription slightly easier and slightly faster than reality. It is used
  because it is repeatable; the word error rate against real recorded speech is
  Phase 8's job, not this document's.
- **Peak is sampled, not continuous.** Polling every 20 ms can miss a spike shorter than
  that. The two peak figures are each their own maximum and may come from different
  instants.

## Re-running it

```
make bakeoff ARGS="profile"                          # the standard run
make bakeoff ARGS="profile --app dist/Uttrflow.app"   # include the bundle in the disk figure
make bakeoff ARGS="profile --dictations 30"          # a longer leak check
make bakeoff ARGS="profile --transcribe-only"        # transcription without the clean-up pass
make bakeoff ARGS="gpu-memory --passes 40"           # the suggestion model's GPU memory, pass by pass
make bakeoff ARGS="gpu-memory --typing --show"       # processor a pass while a reply is typed, and every line
make bakeoff ARGS="reload-leaks --checkpoints 1,5,20" # leaks, footprint and time across reloads in one process
```

The speech model must already be installed (`uttrflow-dev models install`). Audio is
synthesised on the first run and cached; change a passage or the voice and it is
re-spoken, so a stale clip can never be reported under a changed passage.

Every figure printed is read off a `PerformanceReport` built by `PerformanceProfiler` in
`UttrflowEval`, where the phase order, the leak rules and the scaling verdict are covered
by tests. `uttrflow-bakeoff` contributes the arguments, the audio and the table.

The end-to-end word error rate and wait, as in [the section above](#dictation-end-to-end-the-words-and-the-wait):

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release --product uttrflow-dev
python3 Scripts/dictation_bench.py corpus                                  # .build/bench, about a minute
python3 Scripts/dictation_bench.py jobs --cleaners shipping,rules > .build/bench/jobs-fast.tsv
python3 Scripts/dictation_bench.py jobs --mode rt --clean-only \
    --categories reply,dur5,dur15,dur30,dur60,dur120 > .build/bench/jobs-rt.tsv
cat .build/bench/jobs-fast.tsv .build/bench/jobs-rt.tsv > .build/bench/jobs.tsv
.build/release/uttrflow-dev bench .build/bench/jobs.tsv > .build/bench/run.out
python3 Scripts/dictation_bench.py score .build/bench/run.out
```

The corpus names each clip's audio by its voice and words, so changing either speaks it again. Run one `bench` at a time: two processes compete for the Neural Engine and each other's compile.
The run above took about half an hour, its first load included.


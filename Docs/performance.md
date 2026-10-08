# What Uttrflow costs a Mac

Processor, memory, latency and disk, measured rather than estimated, while Uttrflow works and while
it does not. The budget is `ResourceBudget` (`Sources/UttrflowEval/ResourceBudget.swift`) and is
enforced from source by `Scripts/perf_budget_audit.py`; the measurements come from
`uttrflow-bakeoff` (`Sources/uttrflow-bakeoff/`, `profile`, `gpu-memory`, `reload-leaks`,
`complete`) through `PerformanceProfiler` in `UttrflowEval`, and from `uttrflow-dev bench` with
`Scripts/dictation_bench.py`. This page holds the budget, the method and the headline readings;
the detail is split by subject:

- [`performance-dictation.md`](performance-dictation.md) — latency, word error rate and the wait
  after key-up, model load and launch.
- [`performance-suggestions.md`](performance-suggestions.md) — the suggestion model's memory,
  release and reload, and what a suggestion pass costs.
- [`performance-idle.md`](performance-idle.md) — the app while nobody uses it: animation, the
  clipboard poll, classifying a copy, diffs.
- [`performance-leaks.md`](performance-leaks.md) — the leak check and what `leaks` reports.

How the readers work is in [`eval-profiling.md`](eval-profiling.md); why the harness is shaped as
it is, in [`bakeoff-method.md`](bakeoff-method.md).

Every figure was taken on one machine:

| | |
|---|---|
| chip | Apple M5 Pro — 6 performance cores, 12 efficiency |
| memory | 48 GB |
| macOS | 26.5.1 (build 25F80) |
| speech model | `openai_whisper-large-v3-v20240930_turbo_632MB` (`SpeechModel`) |
| clean-up | Apple's on-device foundation model |
| build | `make bakeoff` builds Debug; figures marked Release came from a release build — see [limits](#what-these-numbers-are-not) |

**Three headlines, in the order they matter.**

**A dictation is nearly free, and it is free in the surprising direction.** A fifteen-second
dictation costs **0.76 processor-seconds** and finished in 2.4 s in the historical profile
(commit `8b07c12e9`, 2026-08-29; current latency is [below](#latency-budget-per-stage)). It never holds even half a core,
because the work is on the Neural Engine and the app spends most of a dictation waiting. So the
answer to "what Mac does this need" is not about cores or clock speed.

**Sitting still costs almost nothing.** With its window covered or hidden the app uses about 0.1%
of a core. The home page's demonstration moves only in the window in use, and the clipboard poll
wakes the process 1.7 times a second ([`performance-idle.md`](performance-idle.md)).

**Dictation alone, with AI suggestions off, is nearly free on memory too.** Peak footprint 379 MB,
peak resident 536 MB, with clean-up on, and ten consecutive dictations left the process smaller
than it started. AI suggestions on is a separate, multi-gigabyte mode — up to 3.0 GB between
passes and 3.5 GB at a pass's peak, close to half of memory on an 8 GB Mac — covered in "The
memory budget" below; this headline does not cover it.

## The energy budget

Uttrflow runs all day, from login, on laptops. The Mac to design for is the smallest it supports:
an 8 GB M1 Air, which has no fan and slows itself when hot. Nothing here has been measured on
one, so the budget is written in quantities that do not depend on the machine — wakeups, work per
event, priority — and the measured column names the Mac it came from. A per-Mac processor or
wall-clock limit waits for a measurement on that Mac; none is estimated from this one.

| state | budget | measured |
|---|---|---|
| idle: menu bar only, windows closed, suggestions off | ~0% of a core; at most 2 timer wakeups a second from the app's own code | clipboard poll 1.7 wakeups a second at `PasteboardWatcher.pollInterval` (500 ms) with a fifth of it as tolerance |
| idle with tab-to-complete on | nothing beyond the line above after 12 s with no keystroke, click or switch and no drawn ghost; while a ghost remains, one coalescible read every 5 s until it disappears | `SuggestionTicking`: a 1 s tick (`interval`), each an Accessibility read of the frontmost app, for `CommitDetector.idleInterval` + 4 = 12 s after activity; a visible ghost keeps a 5 s read (`ghostInterval`); a redraw of what is already on screen does no layout and no placement |
| typing, suggestions on | the tap callback does one atomic load; a turn per keystroke, coalesced to one running and one waiting; a model pass only after 120 ms of quiet (`generationDebounceInMilliseconds`), cancelled by the next key | as budgeted |
| a model suggestion pass | at utility priority; none in Low Power Mode or at serious thermal pressure | `DiscretionaryGenerator`; 0.17 processor-seconds a pass here |
| a copy | classified at utility priority, off the main thread | 0.085 processor-seconds here for the costliest 2 MB clip measured |
| between dictations, the tidier | no prewarmed model session that nothing will use | one warm at key-down; one after each piece tidied while the key is held; none after the last piece (`DictationPipeline`) |
| animation | none continuous while nobody can see it; none decorative under Reduce Motion, Low Power Mode or serious thermal pressure | `MotionBudget` and `WindowAttention`; nothing runs continuously while hidden |

The source gate uses these limits for the key path (the limits are parsed by `perf_budget_audit.py`):

- `keystrokeReadsPerTurn`: 1 primary Accessibility read per turn
- `keystrokeCallbackAXCalls`: 0 Accessibility calls on the key callback
- `keystrokeCallbackAllocations`: 0 allocations on the key callback
- `sameSuggestionDrawsPerKey`: 0 duplicate panel draws for an unchanged suggestion

These are source-level guards; live Accessibility message counts and wall-clock latency need an
instrumented app run. Each gate has an injected regression in the audit's self-test.

How the measured column was taken, on a machine at a load average of 50–240 from other builds, so
processor-seconds are the figures to trust and wall clock is pessimistic:

- **Model pass.** `uttrflow-bakeoff complete --fixtures --model gemma3`, Release, under
  `/usr/bin/time -l`, over every fixture (1,154 in that run) back to back: 192 processor-seconds,
  0.17 a pass, p50 207 ms. A Debug build costs about twice as much, so this is measured in
  release. The pass's tokenizer cost is in [`performance-suggestions.md`](performance-suggestions.md).
- **Speech.** `uttrflow-bakeoff profile --transcribe-only`, Release: 0.15, 0.51 and 2.19
  processor-seconds for 3.4, 13.9 and 58.1 seconds of speech — 0.04 per second of audio, 0.27 G
  instructions per second of audio.
- **Clipboard poll.** A stand-alone loop sleeping and reading `NSPasteboard.changeCount`, its own
  wakeups read with `proc_pid_rusage` ([`performance-idle.md`](performance-idle.md)).
- **A copy.** `ClipKindDetector.kind(of:)` timed in a Release build over nine kinds of clip
  ([`performance-idle.md`](performance-idle.md)).
- **The tick.** Counted from the code, not measured.

## The method

`uttrflow-bakeoff profile` drives one process through the app's life and reads memory at each
named moment. The order is fixed, because the order is the measurement:

1. read memory with nothing loaded;
2. load the speech model, timed, and read again;
3. one dictation that is **thrown away** — the first of a process pays for buffers every later one
   reuses, and counting it would make warm-up look like a leak;
4. ten (`--dictations`, default 10) consecutive dictations of the same paragraph, reading memory
   after each — the leak check;
5. each of the three utterance lengths, timed `--repetitions` times (default 3);
6. a second, independent load of the speech model, last, so a second recogniser held beside the
   first cannot inflate any figure above it.

While each dictation runs, memory is polled every 20 ms (`PeakMemory.defaultInterval`), the only
way to catch a spike that has settled by the next named moment.

Two memory figures are reported throughout, because for a product that memory-maps a 648 MB
CoreML model they are very different:

- **footprint** (`phys_footprint`) — Activity Monitor's Memory column, and what a memory limit is
  enforced against. Dirty and compressed pages only.
- **resident** (`resident_size`) — every page in physical RAM, the model's mapped weights
  included. Larger, and evictable under pressure, so it overstates the cost.

Neither alone is honest: the footprint alone looks as though 200 MB of model went missing, and the
resident size alone suggests pressure that clean file-backed pages do not create. Watching
`ps -o rss` from outside through a run put the peak at 463 MB against the 362 MB the process
reported for itself; `ps` counts shared framework pages differently, and the two are the same
order.

### The speech

Three passages, read by the system synthesiser (`say -v Samantha`, `--voice`) into 16 kHz mono
WAV and cached under `.build/profile-audio`. Synthesised so two commits can be compared rather than
two takes; nothing touches the microphone. The passages are ordinary work dictation with fillers,
a mid-sentence restart, a port number, a version string and an Indian name.

| length | words | audio |
|---|---|---|
| short | 12 | 3.42 s |
| medium | 46 | 13.91 s |
| long | 191 | 58.10 s |

## Memory

One `profile` run, Debug, with clean-up on:

```
  moment                        footprint   resident    change
  idle, nothing loaded          11.1 MB     50.5 MB     —
  speech model loaded           229.8 MB    459.8 MB    +218.8 MB
  after one dictation           295.5 MB    525.1 MB    +65.6 MB
  after 10 dictations           267.8 MB    517.9 MB    -27.7 MB
  after the length sweep        148.0 MB    510.2 MB    -119.7 MB
  peak, mid-dictation           379.4 MB    535.7 MB
```

- **The 648 MB model does not cost 648 MB of memory.** It adds 219 MB of footprint and 409 MB of
  resident size, because CoreML maps the weight files rather than reading them into anonymous
  memory. Under pressure macOS can drop those pages and re-read them.
- **The peak is the number that matters: 379 MB.** A dictation transiently costs about 84 MB over
  the settled figure — activations and the clean-up model's working set.
- **The signed app, watched from outside with `ps`, sits at 300–310 MB resident** from a minute
  after login, whether or not anybody dictates (below).
- Of the 11.1 MB idle figure, about 4.8 MB is the three decoded audio clips the harness reads
  before anything is measured. A real idle app carries no audio, so its idle floor is about 6 MB.

### What is paid before anybody speaks

`AppDelegate` calls `loadSpeechModel()` at launch, so every login pays 4–9 seconds of loading and
holds 219 MB of footprint / 409 MB resident for the session, whether or not the user ever
dictates. The load is not required — the engine loads on demand if nobody prepared it — so loading
at launch trades that memory for a first dictation 4–9 seconds faster. The model is released only
under memory pressure (below).

## The memory budget

Uttrflow runs all day on Macs with far less memory than the one above, so what it holds is
budgeted against the smallest Mac it supports: an 8 GB MacBook Air, where macOS and a browser
already claim most of the memory.

### What holds memory, and when

Measured on Release builds with `/usr/bin/time -l` and MLX's own counters.

| holder | loaded when | released when | cost |
|---|---|---|---|
| speech model, Whisper large-v3 turbo on CoreML | launch, `loadSpeechModel()` | memory pressure or quit | +114 MB footprint loaded, 267 MB peak footprint and 340 MB peak resident mid-dictation; the weights are file-mapped, so macOS can drop them itself |
| suggestion model, Gemma 3 4B QAT on MLX | launch or the moment AI suggestions is turned on, only for somebody who turned it on | AI suggestions turned off; no query for `IdleRelease.tight` (3 minutes) on a Mac under 16 GB, `IdleRelease.roomy` (10 minutes) otherwise; memory pressure; or quit | 2,485 MB of GPU memory, 3,036 MB at a pass's peak, 3,464 MB peak process footprint; anonymous, so nothing but a release frees it |
| MLX's buffer cache | during a pass | the end of every pass | capped at 256 MB (`GPUBufferCache.limit`), 0 MB between passes |
| the last pass's prompt in a KV cache | the end of a suggestion pass | the next pass trims it, or the weights are dropped | 91 MB of GPU memory over one typed reply |
| the recording | the shortcut | the end of the dictation | at most 15 MB: 240 s (`DictationLimit`) at 16 kHz in 4-byte samples |
| clipboard thumbnails | the panel is drawn | least recently used first | at most 32 MB (`ClipboardBudget.standard.images`), see [`clipboard-budget.md`](clipboard-budget.md) |
| clipboard, history, dictionary and suggestion stores | launch | quit | under a megabyte of text each at measured sizes; the prediction corpus queries in-memory SQLite and writes encrypted snapshots to disk |

Clean-up runs in Apple's model process, not this one, and is not counted here. How the suggestion
model is released, reloaded and kept off a Mac under pressure is in
[`performance-suggestions.md`](performance-suggestions.md).

### The budget

| state | 8 GB Mac | 16 GB Mac and up |
|---|---|---|
| idle, suggestions off | **≤ 300 MB** footprint | ≤ 300 MB |
| peak during a dictation, suggestions off | **≤ 400 MB** | ≤ 400 MB |
| suggestions on, between passes | ≤ 3.0 GB, and none of it under memory pressure | ≤ 3.0 GB |
| suggestions on, peak of a pass | ≤ 3.5 GB | ≤ 3.5 GB |
| after turning suggestions off | back to the idle line within a second | same |

The speech model fits inside the first two lines with room to spare, so it stays loaded between
dictations. `AppDelegate` lets the recogniser go under memory pressure unless a dictation is under
way; the next key-down loads it again, which costs 2–9 s with the Neural Engine compile cached,
and the app shows the model as loading until it is ready. A critical reading always releases it.
A warning releases it only once the last reload has held for the wait of the same
`ModelMemoryPressure` policy the suggestion model uses (120 s, doubling to 1,800 s while reloads
keep being followed by pressure), so frequent warnings cannot make every dictation pay a reload.

The suggestion model is what the budget is about: on an 8 GB Mac its 3 GB is close to half of all
memory, so nothing loads it for somebody who never asked, and turning the feature off gives it
back (one second after `release()`: 0 MB of MLX active memory, 190 MB process footprint).

## How the budget is enforced

Both budgets above are checked, not only stated. `make perf-budget` runs in `make verify`, needs
no build, no model and no window, and reads the source for the ways a budget can be broken.
`Scripts/perf_budget_audit.py` holds the rules and prints every allowance with its reason:

| check | fails when |
|---|---|
| wakeups | a repeating `Timer` (including one whose `repeats` is passed in), repeating `DispatchSource` timer, display link, sleeping loop, or function that delays (`asyncAfter`, `perform(_:with:afterDelay:)`, a sleep, a one-shot `Timer`) and then calls itself, in product code has an interval under 500 ms, or one the audit cannot resolve, and is not listed with the reason it is not an idle cost |
| priority | the suggestion and local-model modules ask for more than utility priority, detach a task without one, or the app uses the suggestion model outside a `Discretionary` wrapper |
| motion | a `TimelineView`, `repeatForever`, phase or keyframe animator or repeating symbol effect reads neither `MotionBudget` nor `WindowAttention`, is paused by a literal, or never reads `WindowAttention` outside the dock and menu bar panels, which never become key |
| cache | a model pass (`perform`, `generate`, `TokenIterator`, `ChatSession`) sits in no function that caps MLX's cache and clears it on exit, a `release()` does not clear it, or the cap is over 256 MB |
| counters | `ResourceBudget`'s limits differ from the memory or disk budget table |
| suggestions | the key-path limits above differ from what `SuggestionCoordinator` and `SuggestionPanelController` do |
| latency | the table under "Latency budget per stage" has no rows, or a row whose budget is not its p95 plus 20% |

`--self-test` injects one violation per check into the tree as read and fails unless the audit
catches it, so a rule that has stopped matching the code is found rather than trusted. A known
breach is listed with the reason, and fails as stale once it is gone.

The wakeup check reads one file at a time and follows no calls, so it does not see a loop whose
sleep sits in a function the loop calls, two functions that schedule each other, or a timer whose
interval comes from another file's caller. Only a measurement catches every shape, and
`make idle-wakeups` is its complement: it launches the built `dist/Uttrflow.app` in a throwaway
`UTTRFLOW_TEST_CONTAINER` (onboarding finished, menu bar only, updates off), waits
`SETTLE_SECONDS`, then reads `ri_interrupt_wkups`, `ri_pkg_idle_wkups` and processor time with
`proc_pid_rusage` over `WINDOW_SECONDS` — no root needed — and fails above `WAKEUPS_PER_SECOND`
or `CPU_PERCENT` in `Scripts/idle_wakeups.py`. It first proves itself on a 20 Hz loop whose sleep
sits in a called function, which must fail, and a process that only sleeps, which must pass. It
is not in `make verify`, which builds no bundle, and not yet in CI: the counters are the whole
process's, AppKit's threads included, and a build of 7 September read 8.35 wakeups a second and
0.77% of a core idle on an Apple M5 Pro, over a line drawn for the app's own timers. It measures
the menu-bar state only, since no window can yet be opened without a display.

Memory can only be read with the models loaded, so `make perf-budget-models` runs
`uttrflow-bakeoff gpu-memory --passes 12 --release` and `uttrflow-bakeoff profile --dictations 10`,
and each exits non-zero when a reading is over its line: every settled moment of a profile against
the idle line, its peak against a dictation's, each pass's peak and settled footprint against the
suggestion lines, and the footprint a second after a release against the idle line. The profile
also reads the support folder against the disk budget. `ResourceBudget` is the one judge both use.

## Latency budget per stage

Each stage's budget is its measured p95 plus 20%: `LATENCY_HEADROOM` in
`Scripts/perf_budget_audit.py` is the one place that figure lives, and the source audit fails a row
whose budget is not its p95 times it. A run comes from `uttrflow-dev bench` with the shipping tidier,
clean audio, played at speaking pace (`rt`), and is judged by the same `percentile` that
`Scripts/dictation_bench.py score` prints.

| stage | what it times |
|---|---|
| `wait:<category>` | key release to the words being ready, one row per dictation length; insertion is not in it |
| `asr:<field>` | one piece's recognition and its sub-stages, from the `asr` events `bench` writes |
| `clean` | one tidy by the shipping tidier |

This is the current latency of the app; every other latency figure in these pages is historical
and is labelled with the commit that recorded it. A re-measurement replaces both tables below and
names its commit, which the source audit requires.

| measured at | hardware | build | load average | mode |
|---|---|---|---|---|
| commit `cfb11bf73` | Apple M5 Pro, 48 GB | Release | 225–374 | real time, early transcription, clean audio, shipping tidier, 2 repeats of `dur5`, `dur30`, `dur120` |

**These numbers were measured on a loaded Mac and are to be re-measured on an idle one.** The load
came from other builds, so they are several times the quiet-Mac waits recorded earlier in
[`performance-dictation.md`](performance-dictation.md#the-wait).

| stage | p95 s | budget s | samples |
|---|---|---|---|
| `asr:decodeSeconds` | 8.269 | 9.923 | 78 |
| `asr:decoderSetupSeconds` | 0.031 | 0.038 | 78 |
| `asr:encodeSeconds` | 0.637 | 0.765 | 78 |
| `asr:melSeconds` | 0.574 | 0.689 | 78 |
| `asr:recognitionSeconds` | 11.813 | 14.176 | 78 |
| `asr:wordTimingSeconds` | 0.574 | 0.689 | 78 |
| `clean` | 5.557 | 6.669 | 75 |
| `wait:dur120` | 38.950 | 46.740 | 6 |
| `wait:dur30` | 13.985 | 16.782 | 6 |
| `wait:dur5` | 9.518 | 11.422 | 6 |

The source audit checks only the table. Timing needs the models and a quiet Mac, so it is not in
`make verify` or CI; a release candidate runs it, and `--measure` prints the rows above for a new run:

```
python3 Scripts/dictation_bench.py jobs --mode rt --clean-only --cleaners shipping \
    --categories dur5,dur30,dur120 --repeat 2 > .build/bench/jobs-rt.tsv
.build/release/uttrflow-dev bench .build/bench/jobs-rt.tsv > .build/bench/run.out
python3 Scripts/perf_budget_audit.py --measure .build/bench/run.out
make perf-budget-latency RUN=.build/bench/run.out
```

It exits 1 when any stage's p95 is over its budget or has fewer than 3 samples. `--self-test`
proves a run within budget passes, the same run 50% slower fails every stage, and a budget loosened
past its p95 plus headroom fails the table check.

### Recognition split per piece length

`asr` events name every recognition sub-stage, so the split is read straight off a bench run. The
decode loop (`DecodeSession`) counts its steps in two kinds: `promptSteps` feed a forced prompt token
and `promptStepSeconds` is their decoder-model time, a part of `decodeSeconds`; `timestampSteps` are
the sampled steps that chose a timestamp. `prefillSeconds` is the recogniser's cache prefill before
the loop, and `decodeOverheadSeconds` is the filtering, sampling and cache writes between model
calls. `unattributedSeconds` is what is left of `recognitionSeconds`.

A reduced run, measured at commit `d9fd8724a` on an Apple M5 Pro under a load average of 33 to 60,
with a debug build and synthetic speech from the system voice (no recorded human speech), one pass
per row, mode `fast`. Seconds per piece; "rest" is `decodeSeconds` minus `promptStepSeconds`:

| clip | audio s | mel | encode | setup | prefill | prompt steps (n) | rest of decode | overhead | word timing | sampled steps | timestamp steps | recognition | unattributed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| reply, no prompt | 1.7 | 0.031 | 0.287 | 0.005 | 0.000 | 0.030 (3) | 0.112 | 0.338 | 0.010 | 9 | 1 | 0.896 | 9.3% |
| reply, 20-token prompt | 1.7 | 0.003 | 0.286 | 0.003 | 0.000 | 0.247 (23) | 0.104 | 0.911 | 0.009 | 9 | 1 | 1.636 | 4.5% |
| reply, 111-token prompt | 1.7 | 0.009 | 0.285 | 0.003 | 0.000 | 1.049 (103) | 0.105 | 3.225 | 0.009 | 9 | 1 | 4.759 | 1.6% |
| 5 s, no prompt | 4.0 | 0.007 | 0.287 | 0.003 | 0.000 | 0.030 (3) | 0.168 | 0.528 | 0.012 | 15 | 1 | 1.112 | 7.0% |
| 5 s, 20-token prompt | 4.0 | 0.008 | 0.287 | 0.003 | 0.000 | 0.227 (23) | 0.157 | 1.087 | 0.013 | 15 | 1 | 1.857 | 4.1% |
| 5 s, 111-token prompt | 4.0 | 0.005 | 0.287 | 0.003 | 0.000 | 1.040 (103) | 0.160 | 3.411 | 0.013 | 15 | 1 | 4.993 | 1.5% |
| 15 s, no prompt | 13.1 | 0.008 | 0.292 | 0.003 | 0.000 | 0.031 (3) | 0.541 | 1.534 | 0.030 | 50 | 3 | 2.512 | 2.9% |
| 15 s, 20-token prompt | 13.1 | 0.009 | 0.298 | 0.003 | 0.000 | 0.232 (23) | 0.521 | 2.126 | 0.033 | 50 | 3 | 3.302 | 2.4% |
| 15 s, 111-token prompt | 13.1 | 0.010 | 0.297 | 0.003 | 0.000 | 1.032 (103) | 0.514 | 4.353 | 0.029 | 50 | 3 | 6.316 | 1.2% |
| 30 s, no prompt | 28.3 | 0.008 | 0.281 | 0.003 | 0.000 | 0.034 (3) | 1.256 | 3.658 | 0.070 | 117 | 9 | 5.388 | 1.4% |
| 30 s, 20-token prompt | 28.3 | 0.009 | 0.297 | 0.004 | 0.000 | 0.229 (23) | 1.224 | 4.217 | 0.066 | 115 | 7 | 6.124 | 1.3% |
| 30 s, 111-token prompt | 28.3 | 0.014 | 0.572 | 0.005 | 0.000 | 2.183 (206) | 1.688 | 11.492 | 0.112 | 155 | 8 | 16.229 | 1.0% |

What it shows, within the limits below:

1. **The prompt is paid one decoder step per token.** The cache prefill model does no work
   (`prefillSeconds` 0), so a 111-token prompt costs about 1.0 s of model time and about 2.9 s of
   overhead before the first word, on every window and every fallback; the 30 s clip with the long
   prompt fell back once and paid it twice (206 prompt steps).
2. **Overhead between model calls is the largest sub-stage** in this debug build, two to three times
   the model time. A release build is needed before ranking it as a lever.
3. Timestamp steps are a small share: 1 to 9 per piece.
4. The sub-stages sum to recognition within 5% for every row with a prompt or 15 s of audio or more;
   the two shortest unprompted rows leave 7% and 9%, which is the recogniser's windowing outside
   the decode.

**Limits.** Debug build, loaded Mac, one pass, synthetic speech. The full run, a release build on an
idle Mac with repeats, replaces this table; it is the same jobs file with `--repeat` and
`.build/release/uttrflow-dev`.

### Whole-text passes after release

After key release the pieces are joined (`PieceJoiner.join`), the message-wide passes run once over
the joined text (`CleaningPipeline.message`, from `TransformerRouter.finishMessage`), and the Latin
check runs over the result. None has a deadline, and their cost grows with the dictation, not with
the last piece. `WholeTextCostProbeTests` times them over invented 12-word pieces, one per 5 s of
speech, document destination, median of 7 runs, and prints one `WHOLETEXT` line per length.

| speech | words | join ms | message passes ms | Latin check ms |
|---|---|---|---|---|
| 30 s | 73 | 13.4 | 11.7 | 0.13 |
| 120 s | 292 | 44.9 | 46.5 | 0.20 |
| 300 s | 730 | 75.7 | 145.5 | 0.47 |

Measured on Apple M5 Pro, 48 GB, debug test build (`swift test --filter WholeTextCostProbe`), so the
absolute figures overstate a release build; the growth with length is the finding. At 300 s the two
whole-text stages add about 0.22 s after release, ten times the 30 s cost, so a new whole-text pass
must keep running state across pieces rather than run once over everything at the end.

### The last piece at key-up

The audio left to decode after release is the last window `SpeechWindowing.standard` cuts, so its
length depends on the speaker's pauses. `uttrflow-eval final-piece` renders word timings as loud
words and quiet gaps, runs the shipped windowing over 20, 30, 60, 90 and 120 s dictations, and
reports the last window's length at key-up. Without `--alignments` it uses 20 invented speakers per
group, words 0.25 to 0.45 s, word gaps 0.03 to 0.12 s, a sentence pause every 8 to 16 words.

| speakers | dictations | p50 s | p95 s | over 5 s | over 10 s |
|---|---|---|---|---|---|
| sentence pauses 0.3 to 0.75 s | 100 | 14.8 | 29.6 | 80% | 66% |
| sentence pauses 0.9 to 1.4 s | 100 | 4.5 | 8.3 | 43% | 1% |

A speaker who never pauses as long as the 0.8 s sentence pause leaves a last piece of 15 s typical
and up to the 30 s window, because a shorter pause ends a window only after 15 s. Tail figures
measured on speech with long pauses therefore understate the wait for fluent speakers. The same run
on public read speech with word alignments takes `--alignments <file>` (group, speaker, utterance,
word, start, end, tab-separated, fetched at measurement time and never committed).

## Processor

Memory answers "will it fit"; this answers what it costs to run. A dictation that finishes in 2.4
seconds having held four cores busy has spent ten processor-seconds, and that figure decides
whether the fans come on and what the battery does.

```
  length   audio   cpu s    cores   cpu s/audio s  kernel   instructions
  ──────────────────────────────────────────────────────────────────────
  short    3.42    0.28     0.16    0.08           13%      3.5 G
  medium   13.91   0.76     0.28    0.05           12%      8.8 G
  long     58.10   3.04     0.39    0.05           11%      35.0 G
```

**A dictation barely touches the processor.** Across the whole profiling run — model load,
thirteen dictations, memory polled every 20 ms — the process averaged **0.21 of a core over 221
seconds**. Whisper runs on the Neural Engine through CoreML and the clean-up model is Apple's, in
another process; `cores` never reaching 0.4 is the app waiting for them. A dictation needs a Neural
Engine far more than it needs cores, and every Apple silicon Mac has one.

The counters are printed with the arithmetic left in: the run implied **4.10 GHz at 3.82
instructions per cycle**, the right clock for this chip's performance cores. A figure nothing like
it would mean the times and the counters disagree.

### A slower processor barely matters

**Historical, recorded by commit `8b07c12e9` (2026-08-29).** `taskpolicy -b` runs the profile at
background priority, which confines it to the efficiency
cores. The implied clock falls from **4.10 GHz to 1.87 GHz**, and the instruction counts come back
identical to three significant figures (3.5, 8.8, 35.1 G against 3.5, 8.8, 35.0 G), so the same
work ran on a slower processor.

| length | performance cores | efficiency cores only | slower by |
|---|---|---|---|
| short, 3.4 s of speech | 1.68 s | 1.67 s | — |
| medium, 13.9 s | 2.41 s | 3.11 s | 1.29× |
| long, 58.1 s | 7.36 s | 10.55 s | 1.43× |

**Less than half the clock speed costs between nothing and 43%.** If wall-clock time tracked
processor speed the long passage would have taken 16 seconds; it took 10.6. This answers only the
processor half: a smaller Neural Engine, which is what genuinely differs between an Air and a Pro,
is not measured here.

### Processor time that is not the app's

Two costs sit outside the process, and no figure taken from inside it shows them:

- **`ANECompilerService`, at 88% of a core for about two and a half minutes**, the first time the
  model is compiled for the Neural Engine on a Mac and OS
  ([`performance-dictation.md`](performance-dictation.md)).
- **`WindowServer`**, which handles every Core Animation transaction the app commits. An animation
  committing one every display frame cost it 35–49% of a core, which is one reason animation stops
  where nobody can see it ([`performance-idle.md`](performance-idle.md)).

## Disk

```
  speech model                  648.4 MB
  application                   64.9 MB
  total                         713.3 MB
```

The model is measured on disk (648.4 MB across 4 `.mlmodelc` bundles plus two JSON
files), not taken from the catalogue. The application is the signed bundle from `make app`, its
regular files summed the way `Profile.bytes(under:)` sums them (`FileManager` resource values,
symlinks excluded) — mostly the 57.9 MB executable and the 3.8 MB MLX Metal library. All three are
decimal MB (10^6 bytes). A fresh install is therefore **713.3 MB**: the speech model is downloaded
on first launch, the application ships in the bundle, and the total is both added together.

### The disk budget

The support folder grows with use, so each part of it has a line. `ResourceBudget` holds the same
numbers, and `make perf-budget-models` prints every part's size beside its line and fails when one
is over. Each store entry in `LocalStoreInventory` counts against exactly one part, so a new store
cannot go unbudgeted. These are binary MB (2^20 bytes), like the memory budget.

| part | line | why that line |
|---|---|---|
| speech model, on disk | ≤ 768 MB | the installed model is 618 MB; a superseded revision or a staged download beside it is over |
| recordings waiting for a retry | ≤ 256 MB | the cap `RecordingStore` prunes to, about 33 recordings of 240 s as 16-bit WAV |
| dictation history | ≤ 64 MB | 1,000 records at most |
| clipboard, with its pictures | ≤ 1024 MB | the pictures' own cap is 10^9 bytes, plus the list, saved clips and preferences |
| diagnostics | ≤ 16 MB | the speech model's load log and the 30-day network ledger |
| other stores | ≤ 64 MB | the dictionary, snippets, predictions, consent, key and lock |

Read from the support folder of an Apple M5 Pro in daily use: speech model 618 MB, clipboard 9 MB
(8.5 MB of it pictures), other stores 5 MB (the prediction database and its write-ahead log),
history 0.1 MB, recordings 0 MB, diagnostics 0 MB.

## Delivery budget

What it costs to build, check and download Uttrflow, as opposed to what it costs to run. The
limits are in `Scripts/size_budget.json`; `Scripts/size_budget.py` checks them, `Scripts/bundle.sh`
runs it on every bundle it builds (so `make app` and `make app-preflight` fail over budget), and
`make size-budget` checks the resolved package count in `make verify`. Raising a limit is a
reviewed change to the JSON file whose pull request says what grew and why.

| Measure | Measured | Limit | How it was measured |
|---|---|---|---|
| `Uttrflow.app`, bytes of regular files | 93,681,331 | 125,000,000 | `make app` on the machine above, local mode, `size_budget.py --app` |
| `Uttrflow.app` as a `ditto` zip | 26,918,478 | 32,000,000 | the same bundle, `ditto -c -k --keepParent` |
| Resolved Swift packages | 16 | 16 | `pins` in `Package.resolved` |
| `make verify` on the CI image | median 11.9 min, p90 14.7, max 17.5 | 20 min | the `Verify` step of the last 60 successful `CI` runs, read with `gh api` from each run's jobs |

The application figure is larger than the one under [Disk](#disk) because the bundle has grown
since that reading; both sum regular files and exclude symlinks. The `make verify` job as a whole
(checkout, cache, verify, app bundle) took median 19.4 min, p90 23.6, max 25.8 over the same 60
runs, and building the app bundle took median 6.0 min. Timing is read from CI rather than a local
build because a local build shares the machine with whatever else is running. CI writes each
run's `make verify` time to the job summary; the time limit is read there rather than enforced,
because one slow runner is not a regression.

Adding a 35 MB file under `Resources` puts the bundle at about 129 MB and fails the app check.
The package limit has no headroom on purpose: a dependency added by hand or by dependabot
changes `Package.resolved` and fails `make size-budget` until the limit is raised in review. The
disk image is not budgeted here; it is built by the release path, not by `bundle.sh`.

## What these numbers are not

Stated rather than estimated around, because an invented figure in a performance document is worse
than a gap.

- **Not a release build, unless marked.** `make bakeoff` builds Debug. Model inference happens
  inside CoreML and MLX and is unaffected, but the Swift around it is unoptimised, so the fixed
  per-dictation overhead is a ceiling.
- **One Mac, and a fast one.** The figures that transfer to another Mac are processor-seconds and
  instruction counts; wall-clock seconds do not, because most of a dictation is Neural Engine time
  and a smaller Neural Engine is slower by a factor this page cannot state. Re-run
  `make bakeoff ARGS="profile"` on the target Mac rather than scaling.
- **The download is not measured.** A real first run is dominated by fetching 648 MB, which says
  nothing about the machine.
- **Capture and insertion are not timed by the profile.** It reads audio off disk and types into
  nothing. The app times them, with correction and snippet expansion, as `PipelineStage`s on the
  Diagnostics page.
- **The local MLX clean-up model is not profiled.** No app build assembles it
  ([`bakeoff.md`](bakeoff.md)); `uttrflow-bakeoff footprint` measures it beside the speech model.
- **Three runs per length is a small sample.** The medians are stable to about ±5% across repeat
  invocations; smaller differences are noise. The leak check has the larger sample.
- **The machine was busy.** The profile ran at a load average of 7–24, which inflates wall clock
  and leaves processor-seconds almost alone. The idle readings were taken at load 2–4, each a full
  minute of the process's own cumulative processor time.
- **The idle figures are of the signed application**, watched from outside with `ps`, not of the
  harness.
- **Synthesised speech is not human speech.** It is more evenly paced and cleaner, which makes
  transcription slightly easier and faster. Accuracy against recorded speech is
  [`measuring-accuracy.md`](measuring-accuracy.md)'s subject.
- **Peak is sampled.** Polling every 20 ms can miss a shorter spike, and each peak field is its own
  maximum, possibly from different instants.
- **No peak here is machine-wide.** Each is this process's `phys_footprint`, so work handed to a
  system daemon — `ANECompilerService` during a cold compile, Apple's model process during
  clean-up — is absent from all of them.

## Re-running it

```
make bakeoff ARGS="profile"                           # the standard run
make bakeoff ARGS="profile --app dist/Uttrflow.app"   # include the bundle in the disk figure
make bakeoff ARGS="profile --dictations 30"           # a longer leak check
make bakeoff ARGS="profile --transcribe-only"         # transcription without the clean-up pass
make bakeoff ARGS="profile --no-prewarm"              # load with WhisperKit's prewarm off
make bakeoff ARGS="gpu-memory --passes 40"            # the suggestion model's GPU memory, pass by pass
make bakeoff ARGS="gpu-memory --typing --show"        # processor a pass while a reply is typed, and every line
make bakeoff ARGS="gpu-memory --release"              # memory before and after a release
make bakeoff ARGS="reload-leaks --checkpoints 1,5,20" # leaks, footprint and time across reloads in one process
make perf-budget                                      # the source audit
make perf-budget-models                               # the memory budget, with both models installed
```

The speech model must already be installed (`uttrflow-dev models install`). Audio is synthesised
on the first run and cached; a changed passage or voice is spoken again. Every figure printed is
read off a `PerformanceReport` built by `PerformanceProfiler`, where the phase order, the leak
rules and the scaling verdict are covered by tests. The end-to-end bench is in
[`performance-dictation.md`](performance-dictation.md).

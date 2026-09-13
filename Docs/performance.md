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
| a model suggestion pass | at utility priority; none in Low Power Mode or at serious thermal pressure; ≤ 1 processor-second per pass on M1 | user-initiated, ungated (#376); 0.65 processor-seconds per pass here, so ≈ 1.1 on M1 |
| dictation | speech ≤ 0.1 processor-seconds per second of audio on M1; finished within 0.5× the audio's length on M1 | 0.04 here, which scales to ≈ 0.07; 0.20× wall clock here on a loaded machine |
| animation | none continuous while nobody can see it; none decorative under Reduce Motion, Low Power Mode or serious thermal pressure | #359, #377 |

How the rows were measured, on 13 September 2026, on a machine at a load average of 50–180 from
other builds, so wall-clock figures are pessimistic and processor-seconds are the ones to trust:

- **Model pass.** `uttrflow-bakeoff complete --fixtures --model gemma3`, release build, under
  `/usr/bin/time -l`: 30 fixtures cost 22.96 processor-seconds and one cost 4.09, so each pass
  past the first is 0.65 processor-seconds and 11.3 G instructions, p50 784 ms. A debug build
  costs twice that (1.28 s), which is why this row is measured in release.
- **Speech.** `uttrflow-bakeoff profile --transcribe-only`, release: 0.15, 0.51 and 2.19
  processor-seconds for 3.4, 13.9 and 58.1 seconds of speech — 0.04 per second of audio, 0.27 G
  instructions per second of audio.
- **Clipboard poll.** A stand-alone loop that sleeps and reads `NSPasteboard.changeCount`, its
  own wakeups read with `proc_pid_rusage`: 4.8 wakeups a second at 200 ms, 1.7 at 500 ms with a
  100 ms tolerance, 1.0 at 1 s. Processor time is under 0.05% of a core in every case; the
  wakeups are the cost.
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
suggestions off or leaving the Mac idle leaves the weights and at most the capped cache —
in practice nothing. The weights themselves stay loaded until the app quits.

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
  only the panel rising (0.9 s) and going (0.6 s) move continuously, and those still get an
  instant every 1/120 s. The typed line wakes once per character, and everything else is a
  still state that wakes once, at its boundary. That is 228 wakes a loop instead of 960 at
  120 Hz. `ClipboardDemonstrationMomentsTests` checks that the instant drawn matches what the
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
of wakes, which is why the schedule is the lever and the frame rate during motion is not
lowered.

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

## Suggestions under Low Power Mode and thermal pressure

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
```

The speech model must already be installed (`uttrflow-dev models install`). Audio is
synthesised on the first run and cached; change a passage or the voice and it is
re-spoken, so a stale clip can never be reported under a changed passage.

Every figure printed is read off a `PerformanceReport` built by `PerformanceProfiler` in
`UttrflowEval`, where the phase order, the leak rules and the scaling verdict are covered
by tests. `uttrflow-bakeoff` contributes the arguments, the audio and the table.

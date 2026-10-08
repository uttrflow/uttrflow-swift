# Launching, and loading the speech model

At launch `AppDelegate` asks `DictationPipeline.prepare()` (`Sources/UttrflowPipeline/`) to load
the speech model into memory, and dictation cannot start until that load ends. The first load
after a restart takes minutes, so every surface says so: the words live in `SpeechModelLoad` and
the pacing in `SpeechModelLoadEstimate` (`Sources/UttrflowCore/Models/`), readiness in
`SpeechModelReadiness` (`Sources/UttrflowUX/MenuBarPresentation.swift`), and the load itself in
`WhisperKitBackend` (`Sources/UttrflowSpeech/`). Related: [`app-dock.md`](app-dock.md) for the
floating button, [`app-main-window.md`](app-main-window.md) for Home.

## Ready means loaded, not installed

The menu bar's readiness comes from the pipeline's own `isReady`, not from the model store's
`isInstalled`. `isInstalled` asks whether the model's *files are on disk*; whether the model has
been **loaded into memory and can transcribe** is the question the user is asking, and between
launch and the end of the load the first answer is yes and the second is no. A menu bar saying
"Ready" over a model that cannot transcribe is worse than saying nothing. The clipboard panel's
microphone (`PanelDictation`) asks the same question.

`SpeechModelReadiness` has these states: `ready`, `downloading`, `loading`, `loadFailed`,
`loadFailedAgain`, `incomplete` (the folder lacks a file a load reads) and `notInstalled`.

## How long a load takes

Measured with the default model (`SpeechModel.default`,
`openai_whisper-large-v3-v20240930_turbo_632MB`), from the `speech model loaded in` line
`WhisperKitBackend` logs:

| | time to load |
|---|---|
| first load after boot, cold page cache | 154 s |
| every load after that, warm | 2.1 s |

The model is already on disk, so none of this is download: it is CoreML specialising the encoder
and decoder and paging 632 MB of weights in, and the lever is the model, not this code. The same
log line breaks the load into WhisperKit's own timings (prewarm, encoder and decoder
specialisation, encoder and decoder load, the tokenizer). Read it cold, after a reboot and before
anything else has touched the model folder; a warm reading is the 2.1 s row and says nothing about
the cold case.

```
log show --last 10m --predicate 'subsystem == "com.uttrflow.Uttrflow" && category == "speech"'
```

### The load's task priority

The launch load runs at the default priority. `uttrflow-dev load-priority --runs 5` loads the
model warm at default and at `.utility`, alternating, after one untimed load:

| priority | median wall | median processor | one-minute load average |
|---|---|---|---|
| default | 2.66 s | 2.54 s | 56–79 |
| utility | 2.55 s | 2.48 s | 56–79 |

Apple M5 Pro, 48 GB, debug `uttrflow-dev`, on a Mac busy with other builds. At this load a utility
load is no slower to ready, because the work is Core ML's, on its own threads, not the calling
task's. What it costs the user's other login items, a cold load at each priority, and a run near
load average 10 are not measured yet, so the launch load keeps the default priority.

## `prepare()` always runs

`applicationDidFinishLaunching` starts watching for the shortcut before it asks the pipeline to
prepare, so a quick user can already be dictating when `prepare()` is called. The load runs
regardless; only the move to the `failed` state is withheld while a dictation is under way, because
failing a live recording would be wrong. `DictationPipeline.startRecording` declines while the
pipeline's own load is running (`isLoading`) and says so with the `stillLoading` failure; a
pipeline nobody prepared still records and loads on demand.

A load that never returns is a failed load too. `prepare()` waits at most
`StageTimeout.speechModelLoad`, 300 seconds, about twice the cold load measured above, and then
fails with `modelLoadFailed`. It stops waiting instead of cancelling and waiting for the cancel,
because a blocked recogniser load does not answer a cancel. The abandoned load finishes whenever it
can, and a load that finishes late is ignored.

## What a person is told during the load

The menu bar is only seen when somebody opens it, so the load is also said wherever a person would
try to dictate. Every surface reads the same `SpeechModelReadiness`, turned into `SpeechModelLoad`,
the one home for the words and for when the minutes are said.

| `SpeechModelLoad` | `title` (a window's heading) | `line` (floating button) | `status` (Home's ring) | `recovery` |
| --- | --- | --- | --- | --- |
| `loading` | "Loading the speech model…" | "Loading speech model…" | "Loading speech model" | none |
| `failed` | "The speech model didn’t load" | "Speech model didn’t load" | "Speech model didn’t load" | `retry` |
| `broken` (failed twice, or incomplete) | "The speech model is damaged" | "Speech model is damaged" | "Speech model is damaged" | `downloadSpeechModel` |
| `missing` | "The speech model isn’t downloaded" | "Speech model not downloaded" | "Speech model not downloaded" | `downloadSpeechModel` |

| Where | While loading | After a failed load |
| --- | --- | --- |
| Home (`HomeModelStatus.load`) | "Getting ready…" over a sliding bar, "Loading the speech model" under it | "Try again" after the first failure, "Download again" once it is broken |
| Floating button | `line` and `detail` | `line`, "Dictation can’t start without it" |
| Shortcut or button pressed | "Speech model still loading…" (`SpeechModelLoad.refusal`) through the notice every dictation failure uses; the microphone never opens | dictation starts, and the recogniser tries the load again on demand |
| Clipboard panel microphone | off: "Speech model still loading" | off, as for a model that is not ready |
| Menu bar status | "Getting ready…", then the estimate | "Speech model didn't load", with **Try again**; "Download again" once broken |

A model that is not on disk at all shows on Home as "Speech model not installed" with **Download
speech model** (`HomeModelStatus.missing`), and the menu bar reads "Speech model not downloaded".
Home's resting status is "Ready"; it never says "Listening", which on the menu bar and the floating
button means the microphone is open.

**Download again** on a broken load deletes the model that will not load and opens setup to fetch it
again; closing setup loads whatever it installed. A model counts as installed only when every file
a load reads is there, so a load that still fails is damage the store cannot see from outside, and
a fresh copy is the repair. When the load ends, the refusal's notice is cleared and every surface
goes back to what it drew before.

## The estimate

Nothing reports how far a load has got; the app knows only how long it has run. So the bar is a
guess paced to a typical cold load:

| Value | Constant | Meaning |
| --- | --- | --- |
| 5 s | `SpeechModelLoad.estimateAfter` | the minutes are said only once a load has run this long; a warm load is over in about two |
| 150 s | `SpeechModelLoadEstimate.typicalColdLoad` | the one number that paces the estimate, from the 154 s cold load measured above |
| 0.9 | `SpeechModelLoadEstimate.ceiling` | the share the bar eases towards and holds at until the model is ready |
| 90 s / 45 s | `twoMinutesAbove`, `oneMinuteAbove` | the time left that reads as about two minutes, then about one |
| 1 s | `redrawInterval` | how often a surface redraws while a load runs |

- **Tune `typicalColdLoad`, not the curve.** A slower Mac overruns it and holds at 90 % for
  longer; a faster one jumps to done early.
- **The bar eases out** from 0 to 90 % over that time (`0.9 × (1 − (1 − t)²)`, with `t` the share
  of the typical load gone), so it moves quickly at first, slows as it nears the ceiling, and never
  goes backwards. It then holds at 90 % until the model is really ready.
- **The time left is said in four phrases** (`timeLeft`): "about 2 min left", "about 1 min left",
  "less than a minute left", and once holding "almost ready". The floating button uses the short
  form (`shortTimeLeft`: "~2 min", "~1 min", "<1 min", "almost"), and VoiceOver hears the minutes
  written out (`spokenTimeLeft`).

| Where | Past five seconds |
| --- | --- |
| Home | "Getting ready · about 1 min left", under it "Only after a restart. Everything else already works.", and the bar filled to the estimate. Holding: "Almost ready…" |
| Floating button | a ring filled to the estimate, and the short time left |
| Menu bar | the same heading as Home over a bar filled to the estimate |
| A dictation refused during the load | "Speech model still loading…", and under it the time left |

The floating button and the menu bar redraw once a second while the load runs, from `AppDelegate`'s
`speechLoadTicker`, which starts at `estimateAfter` and ends with the load; nothing ticks once the
model is ready. Home is not redrawn by that ticker, because redrawing the main window rebuilds every
page from the whole history. Its status block in `HomeHeroView` carries the load's start and runs
its own `TimelineView` (`HomeLoadSchedule`), so only that block redraws: once a second while its
window is in use, and every `restingInterval` (15 s) while it is not. The bars ease between ticks,
and under Reduce Motion they step instead.

## The menu-bar item

The menu-bar item shows the Uttrflow mark, as a template image, while nothing is happening, and an
SF Symbol for the state as soon as something is (`MenuBarIcon.mark` / `.symbol`). A state that
needs attention is drawn tinted rather than as a template, because there the colour is the message
(`MenuBarController.icon(for:)`). A dot over the icon marks clipboard capture as on, so it stays
visible while another activity owns the icon.

## From process start to the shortcut being heard

As a login item the app starts while the whole session does, and the shortcut is the product, so
the launch is measured to the moment the dictation shortcut is first armed or refused.

- **What marks it.** `ShortcutArming` tells `LaunchMilestone` its first outcome, once. The time is
  `ProcessAge`, read from the kernel's start time for this process, so work before `main` counts.
  A later re-arming from Settings is not the launch and is not recorded.
- **Where it is said.** One line under the `launch` category, and a `ShortcutSettled` signpost
  carrying the same line, so Instruments places it on the launch timeline:

```
log show --last 10m --predicate 'subsystem == "com.uttrflow.Uttrflow" && category == "launch"'
```

  `LaunchReport` is the one home for that line, written by the app and read back by the harness.
  A start time the kernel did not give is said as `unknown`, never as a number.
- **How to measure it.** `uttrflow-dev launch --app dist/Uttrflow.app --runs 5` starts the built
  bundle against a fresh temporary container (signed in, onboarded, no login item), waits for the
  line, quits the app, and prints each run with the minimum, median and maximum.
  A refusal ends the wait as well, and the line says `refused`: a bundle without
  Accessibility is refused, and the time to that refusal is still the launch's.

No launch-time budget is enforced.

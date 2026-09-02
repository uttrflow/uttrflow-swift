# Launching, and the minute before the app can dictate

## What users saw

Open Uttrflow, press the shortcut straight away, speak, let go — and nothing happens for
a long time, or nothing happens at all. The menu bar said **Ready** the whole time.

## Why

Two separate mistakes, both of which made the app claim to be working before it was.

### The menu bar answered a different question

`MenuBarState.speechModel` was computed as:

```swift
speechModel: modelStore.isInstalled(.default) ? .ready : .notInstalled
```

`isInstalled` asks whether the model's *files are on disk*. Whether the model has been
**loaded into memory and can transcribe** is a different question, and it is the one the
user is asking. Between launch and the end of the load, the answer to the first is yes
and to the second is no.

That gap is not small. Measured on this Mac with the shipping model
(`openai_whisper-large-v3-v20240930_turbo_632MB`):

| | time to load |
|---|---|
| first load after boot, cold page cache | **154 s** |
| every load after that, warm | 2.1 s |

Two and a half minutes of a menu bar saying Ready is the whole bug report. The
presenter was always able to say otherwise — `SpeechModelReadiness` has a
`downloading` case, `statusLine` renders it, and `canStartDictation` refuses while it is
not `ready`, with a comment saying *"a 'Ready' that cannot dictate is worse than saying
nothing at all"*. It was simply never told.

There is now a `loading` case, and the app reports it from the pipeline's own
`isReady` rather than from the file system. The clipboard panel's dictation button asked
the same wrong question and now asks the same right one.

### `prepare()` dropped itself when the user was quick

```swift
public func prepare() async {
    guard !isBusy else { return }      // ← silently does nothing, and never retries
```

`applicationDidFinishLaunching` starts watching for the shortcut *before* it asks the
pipeline to prepare. Press the shortcut in that window and the pipeline is already
recording, so `prepare()` returned immediately, having done nothing, and nothing ever
called it again. The model was then loaded inside the first transcription, by
`BackedSpeechEngine.transcribe`'s own fallback — during which the user is holding a key
and looking at a menu bar that says Ready.

The guard was there to protect the state machine, not the loading: `prepare` transitions
to `failed` on error, and doing that over a live recording would be wrong. So the guard
now covers only the transition. The load itself always runs, and can run *while* the
user speaks — which is strictly better, because it warms the model during the one moment
the app knows a transcription is coming.

## What is still true

A cold load is still 154 seconds. Nothing here makes it faster; it makes the app honest
about it. Making it faster is a separate question — the load is CoreML compiling and
paging in a 632 MB model, and the lever is the model, not this code.

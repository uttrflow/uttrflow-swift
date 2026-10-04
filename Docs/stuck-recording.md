# The recording that never stops

A dictation must always end: if it does not, the menu bar stays lit, the shortcut does nothing,
and the only way out is to force-quit. Three unrelated causes can keep one running, and each has
its own guard. The key-state reconciliation is in `Sources/UttrflowInput/ActivationMonitor.swift`,
`CarbonHotkeyMonitor.swift` and `RealKeyState.swift`; the stage limits are in
`Sources/UttrflowCore/Support/StageTimeout.swift`; the length cap is `DictationLimit`
(`Sources/UttrflowCore/Support/DictationLimit.swift`), enforced by `DictationController`.

## 1. The release event never arrives

The pipeline leaves `.recording` only when it is told the key came up, so any path that loses the
release would wedge the app, and both monitors have one:

- **`ActivationMonitor`**, over `SystemKeyboard`'s session event tap, watches the dictation
  shortcut. The system can disable the tap while the key is held, and **secure input** — any
  password field in any application, including the login window — withholds key-up and
  flags-changed events from it. The press gets through and the release does not.
- **`CarbonHotkeyMonitor`**, used by every other shortcut, relies on `kEventHotKeyReleased`, which
  `RegisterEventHotKey` does not always send: lifting the modifier before the key loses it, and so
  does a window server that drops the registration.

`HeldModifierEdge.isDown` would then stay `true`, with no other way to close the microphone.

So neither monitor trusts the event. While a press is outstanding, each compares against the real
key state every 250 ms (`reconciliationMilliseconds`) — `ActivationMonitor` through
`SystemKeyState`, which reads `CGEventSource.flagsState` and `keyState` for the binding, and
`CarbonHotkeyMonitor` through `CGEventSource.keyState` for its registered key — and feeds the answer
to the same recogniser an event would. A release that is never delivered is noticed within a
quarter of a second. The poll is the source of truth and the event is the fast path.

**The poll runs only while a press is outstanding.** It starts when a monitor reports a press and
stops when it reports or reconciles the release. A timer running while no press is outstanding
would wake an idle app four times a second for its whole life, and one left behind by a monitor
dropped without `stop()` would keep firing for the life of the process — long enough to keep a test
binary alive after every test has passed. A monitor released mid-hold cancels its own timer.

## 2. A stage never returns

Every stage of a dictation runs somebody else's code — a CoreML decode, an on-device language
model, an Accessibility round trip into another application — and none of it promises to return.
A stage that hangs would leave `DictationState.isBusy` true, and `startRecording()` refuses while
`isBusy`, so every later dictation would be refused: the same symptom as a lost release, from a
different direction.

So every stage runs under `withStageTimeout`, with these limits:

| Stage | Limit | On timeout |
|---|---|---|
| Loading the speech model | `StageTimeout.speechModelLoad`, 300 s | the load fails with `modelLoadFailed` and can be retried; see [startup.md](startup.md) |
| Stopping capture | `StageTimeout.quick`, 15 s | the dictation fails, and the pipeline returns to idle |
| Transcription | `StageTimeout.transcription`, 120 s | the dictation fails, and the pipeline returns to idle |
| Reading the screen | `StageTimeout.quick`, 15 s | the dictation goes on with no context |
| Tidying | `StageTimeout.transformation`, 30 s, as a backstop | each engine has its own allowance inside it — `StageTimeout.engine` (20 s) for a model, `StageTimeout.rules` (2 s) for the deterministic floor — and the router spends them in turn, so a model that hangs costs its own turn and the floor still answers; only if the floor is starved too do the words go in untidied |
| Correction, snippet expansion | `StageTimeout.quick`, 15 s | the stage is skipped and the words go in as they were |
| Insertion | `StageTimeout.quick`, 15 s | the dictation fails with `insertionTimedOut`, carrying the transcript so it can still be offered |

A timeout does not have to produce a good outcome; it has to produce one, so the next dictation can
start. `withStageTimeout` cancels the work when the limit wins, not only its timer, because
abandoned work would go on having effects nobody is waiting for: an application that stops
answering Accessibility for longer than the limit could otherwise receive the words after the user
was told the dictation failed. Each irreversible act on an insertion route therefore checks
`Task.isCancelled` immediately before it happens — the Accessibility write, the clipboard write
before a paste, and the clipboard floor. The floor included: the words are already kept under
Recent, and the clipboard is the user's.

A transcript that reaches the screen with no tidying pass run over it is recorded as `.untidied`,
not as `.rules`, so it is not mistaken for one the deterministic engine wrote.

## 3. Nobody let go at all

Neither guard above helps a recording started hands-free and then left: nothing was pressed, so
there is no release to reconcile, and no stage is hanging. `DictationController` holds every
dictation to `DictationLimit.default`:

| `DictationLimit` field | Value | What happens |
|---|---|---|
| `warnAfter` | 180 s | the menu bar and the floating button count down: "Listening… 1 min left", then every `countdownStep` (10 s), "50 sec left" to "10 sec left" |
| `stopAfter` | 240 s | the dictation finishes itself, and is transcribed and inserted |

It is a soft cap. Reaching it keeps everything said; a hard cut would lose the last sentence spoken
and say so afterwards. The minute of warning lets a speaker end their own sentence rather than have
it ended for them. The limit is not a setting.

A dictation that is listening also ends when the screen locks, the user session resigns, the
displays sleep or the Mac is about to sleep (`DictationSessionEndObserver`).
`DictationController.endForSessionEnding()` finishes it through the normal stop path, so the
captured words are still transcribed, and since capture ends before sleep, no cap is left to fire
on wake.

The first dictation after wake starts from a clean gesture state, which `DictationControllerTests`
checks with an injected session end in place of a real sleep:

| Before the session end | First gesture after wake | Outcome |
|---|---|---|
| Toggle dictation recording | one press | opens the microphone; it does not close a stale one |
| Hold in progress | the late release, then a new hold | the release inserts nothing; the new hold dictates |
| Hands-free dictation | a hold | an ordinary hold, not the end of hands-free |
| Nothing recording, notice sent twice | a toggle dictation | dictates once |

These run against fakes, so they say nothing about the audio route, the speech model, the event
tap or Accessibility trust after wake, nor where a dictation still transcribing at sleep inserts:
`endForSessionEnding()` only stops one that is listening, so one past that point inserts into
whatever is frontmost when it finishes. Those need a real sleep, lock and display-sleep cycle.

## Testing a timeout without hanging the suite

The tests that drive `StageTimeout` hold a `ManualClock` and must move it at exactly the right
moment: a stage's deadline can only be expired once that stage has installed it. Polling for a
sleeper and then advancing is two steps — the count is read, the lock is released, and the advance
happens later against a clock that may have changed. If the sleeper that satisfied the check
belonged to the previous stage and was torn down in between, the clock moves with nothing
installed, the next stage installs a deadline nothing ever reaches, and the test awaits a value
that cannot arrive. Under Swift Testing's concurrency the run then stops producing output and never
finishes. The race is timing-dependent: it survives a fast machine and appears on a loaded one.

So the wait and the advance are one step. `ManualClock.advanceWhenSomethingIsWaiting(by:)` parks the
request when nothing is sleeping yet, and `sleep` carries it out inside the same lock acquisition
that installs the sleeper. `ManualClock` exposes no sleeper count, because one cannot be read
without inviting the two-step back.

Atomicity does not pick the right deadline on its own: when a stage begins, the previous stage's
deadline can still be installed, and advancing then expires that one instead. The `expire` helper
in `Tests/UttrflowPipelineTests/DictationStageTimeoutTests.swift` therefore advances until the
pipeline leaves the stage rather than exactly once; firing an already-resolved deadline is
harmless, because its race already has an outcome and ignores a second answer.

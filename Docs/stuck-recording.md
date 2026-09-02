# The recording that never stops

## What users saw

Hold the shortcut, let go, and the app stays listening. The menu bar stays lit, the
shortcut does nothing from then on, and the only way out is to force-quit. Sometimes it
happens on the first dictation after launch; sometimes after hours of working fine.

## There are two causes, and they are unrelated

### 1. The release event never arrives

The pipeline leaves `.recording` when it is told the key came up. Nothing else moves it.
So any path that loses the release wedges the app, and both monitors have one:

- **`HeldModifierMonitor`** watches `NSEvent` monitors, and macOS stops calling them
  while **secure input** is enabled — which is any password field, in any application,
  including the login window and 1Password. It also tears them down if Accessibility is
  revoked while the app is running. The press gets through, the release does not.
- **`CarbonHotkeyMonitor`** relies on `kEventHotKeyReleased`, which
  `RegisterEventHotKey` does not always send: lifting the modifier before the key loses
  it, and so does a window server that drops the registration.

`HeldModifierEdge.isDown` then stays `true` for ever, and there is no second way to
close the microphone.

**The fix is to stop trusting the event.** Both monitors now compare against the real
key state every 250 ms — `NSEvent.modifierFlags` for a held modifier,
`CGEventSource.keyState` for a registered key — and feed the answer to the same
`HeldModifierEdge` an event would. A release that is never delivered is noticed within a
quarter of a second, which is under what anybody perceives as a hang.

Reading the hardware rather than waiting to be told is the whole idea. The poll is the
source of truth and the event is the fast path.

**The poll runs only while a key is down.** It starts on the press and stops on the
release, which is what the guarantee actually needs — secure input turning on *during* a
hold is the case that loses a release, and by then the press has already started the
timer. A timer running the rest of the time would wake an idle menu-bar app four times a
second for its whole life, and a monitor dropped without `stop()` would leave one firing
for the life of the process. That second half is not hypothetical: it kept a CI runner's
test binary alive for forty minutes after every test had passed.

### 2. A stage never returns

Every stage of a dictation runs somebody else's code — a CoreML decode, an on-device
language model, an Accessibility round trip into another application — and none of it
promises to return. There were **no timeouts anywhere** in the pipeline, the speech
layer or the AI layer.

A stage that hangs leaves `DictationState.isBusy` true. `startRecording()` guards on
`isBusy`, so **every later dictation is refused** — the shortcut is dead for the rest of
the process's life, with no hotkey involved at all. This is the same symptom from a
completely different direction, which is why fixing the monitors alone would not have
been enough.

**The fix is `withStageTimeout`**, applied to every stage. The limits are in
`StageTimeout`. What happens on expiry follows §19 — the user's words are never lost:

| Stage | On timeout |
|---|---|
| capture, transcription | the dictation fails, and the pipeline returns to idle |
| tidying, correction, expansion | the stage is skipped and the words go in untidied |
| insertion | the dictation fails, carrying the transcript so it can still be offered |

The point is not that a timeout produces a good outcome. It is that it produces *an*
outcome, so the next dictation can start.

### 3. Nobody let go at all

Neither fix above helps a recording that is running because the user started one in
toggle mode and walked away. Nothing was pressed, so there is no release to reconcile
against, and no stage is hanging.

`DictationLimit` is the answer and was **specified, tested and wired to nothing** — every
reference to it was its own definition or its own test. It is now wired into
`DictationController`:

| at | what happens |
|---|---|
| 3 minutes | the menu bar and the floating button count down — "Listening… 1 min left" |
| 4 minutes | the dictation **finishes itself**, and is transcribed and inserted |

It is a soft cap, and the distinction is the whole point. Reaching it keeps everything
said; a hard cut would lose the last sentence somebody spoke and tell them afterwards,
which is the worst moment to find out. The minute of warning between the two is what
lets a speaker end their own sentence rather than have it ended for them.

The limits are `DictationLimit.default` and nothing reads them from settings yet.

## Testing a timeout without hanging the whole suite

The tests that drive `StageTimeout` hold a `ManualClock` and have to move it at exactly
the right moment: a stage's deadline can only be expired once that stage has installed
it. The obvious way to arrange that is to poll:

```swift
while clock.sleeperCount == 0 { await Task.yield() }   // something is waiting
clock.advance(by: limit)                               // so expire it
```

**That is two steps, and it is wrong.** The count is read, the lock is released, and the
advance happens later against a clock that may have changed. Instrumenting the tidying
test caught the window open on 1 run in 25:

```
PROBE advance stage=tidying limit=30.0s sleepers=0 now=0.0s
```

Non-zero when the loop exited, zero by the time the advance ran. The sleeper that
satisfied the guard belonged to the *previous* stage and was torn down in between.

The cost of losing that race is not a failed test. The clock moves to 30s with nothing
installed; the tidying stage then installs its deadline at 60s; nothing ever advances
again; `withStageTimeout` never returns, so `finishRecording()` never returns, so the
test awaits a value that cannot arrive. Swift Testing runs tests concurrently, so the
run stops producing output and never finishes — no failure, no summary, just an idle
process until CI kills the job at its 45-minute cap. That happened on `main` and on a
pull request branch, and cost two runner-hours before it was tracked down.

It is timing-dependent, so it survives a fast machine — 40 stress runs under CPU load
did not reproduce it — and bites a loaded runner, where these tests took 11 seconds
each instead of the whole suite taking three.

**So the wait and the advance are one step.** `advanceWhenSomethingIsWaiting(by:)` parks
the request when nothing is sleeping yet, and `sleep` carries it out inside the same
lock acquisition that installs the sleeper, where nothing can come apart in between.
`sleeperCount` is gone rather than deprecated: it cannot be read without inviting the
same two-step back.

One thing the atomicity does not fix on its own is picking the *right* deadline. When a
stage begins, the previous stage's deadline can still be installed, and advancing then
expires that one instead. `expire` therefore advances until the pipeline leaves the
stage rather than exactly once; firing an already-resolved deadline is harmless, because
the race it belonged to has an outcome and ignores a second answer.

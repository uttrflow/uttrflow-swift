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

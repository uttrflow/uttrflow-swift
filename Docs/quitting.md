# Quitting

When macOS asks Uttrflow to quit, `AppDelegate.applicationShouldTerminate` answers
`.terminateLater` and `AppQuitCoordinator.finish` (`Sources/Uttrflow/AppQuitCoordinator.swift`)
lets the dictation in flight land before the process exits, within a fixed budget, then replies.
A dictation's words exist only in memory until they are inserted (the audio kept for a retry is
described in [`recordings.md`](recordings.md)), so quitting mid-dictation without waiting would
lose them silently.

If a clipboard write failed during this run, the app asks whether to quit anyway before starting
that pipeline. Cancel keeps the app open so a later clipboard write can save the in-memory history;
quitting confirms that recent copies which were not persisted will be lost.

## What it does, in order

All of it runs inside `AppDelegate.quitBudget`, 15 seconds from the quit request:

1. Flush the clipboard's held uses (`ClipboardStore.flushUse`), so the eviction order survives the
   quit; see [`clipboard-store.md`](clipboard-store.md#what-fails-quietly-and-what-does-not).
2. Finish the completion store's pending writes.
3. If a dictation is still recording, finish it (`finishRecording`).
4. Wait until the pipeline leaves its busy state: transcription, clean-up and insertion.
5. Stop the dictation controller.

Then, on every path, including the budget running out, flush telemetry and reply
`reply(toApplicationShouldTerminate: true)`.

## A recording is finished, not waited on

A recording is waiting on the user, not on the app: in toggle mode, or with a recording stuck for
any of the reasons in [`stuck-recording.md`](stuck-recording.md), nothing is going to end it, so
waiting for `DictationState.isBusy` to clear would wait for ever and leave Force Quit as the only
way out. Finishing the recording keeps the words, which is the whole point of waiting at all.

## The wait is bounded

The reply is sent on every path, because an unanswered `.terminateLater` is an application that
cannot be quit, which is a worse failure than the one the wait exists to prevent.

The cost: a dictation still transcribing when the fifteen seconds run out is lost. That is a very
long recording quit almost immediately after it ended; an ordinary dictation transcribes in about a
second. The trade is deliberate: the words matter, and an app that will not quit matters more.

# Quitting

## The promise, and what it cost

Quitting mid-dictation used to take the audio, the transcript and the cleaned text with
it, silently. Nothing is written to disk until the words land, so the only way not to
lose them is not to exit until they have somewhere to go. `applicationShouldTerminate`
therefore answers `.terminateLater` and waits.

**It waited for ever.** The condition was `DictationState.isBusy`, and `isBusy` includes
`.recording` — so the app was waiting for a key the user might never lift:

- **Toggle mode.** Press the shortcut, start dictating, walk away, then quit from the
  menu or the Dock. Nothing is going to end that recording, so nothing is going to
  release the quit.
- **A recording that is stuck** for any of the reasons in `Docs/stuck-recording.md`.
  The app was then unquittable as well as unusable.

Either way macOS eventually offers Force Quit, which is what users reported doing.

## What it does now

**A recording is finished rather than waited on.** It is waiting on the user, not on the
app, and finishing it keeps the words — which is the whole point of waiting at all.

**The wait is bounded**, at fifteen seconds, and the reply is sent on every path. An
unanswered `.terminateLater` is an application that cannot be quit, which is a worse
failure than the one the wait exists to prevent.

## What that costs

A dictation still transcribing when the fifteen seconds run out is lost. In practice that
is a very long recording quit almost immediately after it ended — an ordinary dictation
transcribes in about a second. The trade is deliberate: the words matter, and an app that
will not quit matters more.

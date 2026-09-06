# How a gesture becomes a dictation

`DictationController` turns key presses, floating-button clicks and menu items into calls on the
pipeline. The two activation modes (hold-to-talk and press-to-toggle) differ only here, so neither
the hotkey monitor below nor the pipeline above knows there is more than one way to start.

## One queue for every source

- `handle(_:)` suspends: it awaits the pipeline while the microphone opens. An actor is
  reentrant across that suspension, so a press and a release delivered as two independent tasks
  can interleave: the release runs first, sees a pipeline that is not listening yet, and returns;
  the press then completes and the recording is left running with nothing able to stop it.
- The shortcut never hit this because its events arrive down one sequential stream. The floating
  button did, and on first launch it hit it every time: the microphone prompt makes `start()`
  take seconds, so the release always lost.
- So every gesture from every source goes through one `AsyncStream` and is handled one at a
  time. `submit(_:)` returns immediately and the work queues behind whatever is in flight; the
  shortcut's own stream is forwarded into the same queue rather than handled directly.

## Rebinding the shortcut

- `start(binding:)` is called again whenever the user changes the shortcut, and it now only
  rebinds the monitor. The monitor's `events` is one stream for the life of the monitor, and an
  `AsyncStream` has room for one reader: two consumers would each get whichever keypress they
  happened to be waiting for, so roughly every other press would vanish.
- So the controller reads that stream exactly once, in `init`, and never cancels it. Cancelling
  and recreating it per rebind was the earlier answer, and it was wrong twice over: the new
  reader could start before the cancelled one had finished, and `stop()` cancelled the reader a
  line before `monitor.stop()` yielded the release it owes for a hold in progress — the one
  event that keeps a stuck microphone from staying open.

## A click has no release

Both ways of pretending otherwise were broken. Sending `.pressed` and `.released` together made
a hold shorter than the slip threshold, so the recording was cancelled the instant it began, or,
when the microphone was slow to open, ran a whole dictation on a couple of milliseconds of audio.
Sending `.pressed` alone opened the microphone with nothing in hold-to-talk able to close it: the
next real hold was refused as busy, and its release finished the abandoned recording instead,
inserting everything the microphone had heard in between.

So `toggleFromControl()` toggles, whatever the shortcut is set to, using the same two branches
`pressToToggle` already uses. What starts a dictation this way is a control, and the control is
still there to stop it.

## The minimum hold

A hold shorter than 200 ms is a slip, not a dictation. Tapping the shortcut by accident would
otherwise start and instantly stop a recording, and the user would be told their speech was too
short to transcribe: an error for something they never meant to do. Cancelling silently is the
honest response. The controller is generic over its clock so this rule tests exactly and
instantly.

## The cue

The start cue plays only once the pipeline is listening, so a refused microphone does not make a
sound as though everything had worked. `Docs/audio-capture.md` measures what the cue does to the
recording.

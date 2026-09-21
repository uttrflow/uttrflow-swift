# How a gesture becomes a dictation

`DictationController` turns key presses, floating-button clicks and menu items into calls on the
pipeline. The two activation modes (hold-to-talk and press-to-toggle) and the double tap that
leaves the microphone open all differ only here, so neither the hotkey monitor below nor the
pipeline above knows there is more than one way to be recording.

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
- A click from the floating button or a menu item is queued the same way. `toggleFromControl()`
  waits for its turn and returns once the click has been handled, so a caller that awaits it still
  sees the dictation it started or finished.

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

## Changing the activation mode

- `setActivation(_:)` is queued behind every other gesture, like a click, and returns once the
  new mode is in force. Run beside the queue, it could land while a press was still waiting for
  the microphone to open, see nothing recording, and let that press finish opening it under rules
  it was never given.
- A change to a different mode **finishes** any dictation under way and keeps its words. A
  recording belongs to the gesture that started it, and after the change that gesture no longer
  has a way to end: a hold switched to press-to-toggle ignores its release, and a toggle switched
  to hold-to-talk waits for a hold nobody is making. Left alone, the microphone stays open until a
  stray press or the cap closes it.
- Finishing, not cancelling, matches the two other ends nobody pressed a key for: a rebind
  mid-hold delivers the owed release, which finishes the hold (`Docs/shortcuts.md`), and the cap
  finishes and keeps the words (`Docs/stuck-recording.md`). Speech from before opening
  Settings is inserted rather than lost.
- The change also forgets a modifier press still settling, a pending first tap and hands-free, so
  a release that arrives after the change opens nothing and the next press starts clean.
- Setting the mode the controller already has changes nothing, so a settings write that touches
  another field cannot stop a dictation.

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

A slip is cancelled only when it is neither half of a pair nor made while hands-free — see below,
because the same 200 ms that decides a slip is what makes a tap countable.

A binding made only of modifiers waits out the same 200 ms before a press opens anything, so
another app's shortcut on those modifiers can arrive first and withdraw it. See
`Docs/shortcuts.md`. A tap that ends inside that wait is still counted as a tap below; it just
never opens the microphone to be cancelled.

## Two taps, and the microphone stays open

Holding a key to talk is the right gesture for a sentence and the wrong one for a paragraph. So
two taps in quick succession leave the microphone open, and two more close it. `endHold()` is
where all of it happens.

A tap is a hold shorter than `minimumHold` — 200 ms, the same threshold the slip rule uses. Two
taps whose ends fall within `doubleTapWindow` — 450 ms — are one double tap. The first turns
hands-free on; the next pair turns it off, as does any of the ends listed below.

That makes three ways to be recording rather than two, and they do not overlap:

| gesture | starts | ends |
|---|---|---|
| hold | key down | key up |
| press to toggle | key down | the next key down |
| double tap | two taps | two more taps |

Two consequences worth stating, because both look like bugs from outside:

- **A single tap while hands-free changes nothing.** It cannot cancel, because it may yet be the
  first half of the pair that ends the session. Only the second tap decides.
- **Releasing the key does nothing while hands-free.** There is no hold to end — the gesture that
  started this was two taps, and a release the user never thinks of as one should not stop them
  mid-sentence.

### However it ends, the next gesture works

A second double tap is the gesture that ends a hands-free dictation, and it is not the only
thing that can. Each of these ends it and forgets it, so the next hold and the next double tap
open the microphone as usual:

- a second double tap;
- a click on a control: the menu bar's Stop Dictation, the panel's dictate button, Retry;
- the cap, which finishes the recording and keeps its words (`Docs/stuck-recording.md`);
- a change of activation mode;
- the pipeline ending the recording on its own, such as a cancel: the next press notices the
  microphone is closed and forgets hands-free before acting.

**It exists in hold-to-talk only**, and that is not an omission. `endHold()` is reached from
`(.holdToTalk, .released)` and nothing else — in press-to-toggle a release does nothing at all,
so no tap is ever counted. The gesture is not needed there: press-to-toggle already leaves the
microphone open until you press again, which is the thing the double tap exists to give somebody
who chose to hold. Two ways to be hands-free, one per mode, rather than one mode having both.

## The cue

The start cue plays only once the pipeline is listening, so a refused microphone does not make a
sound as though everything had worked. `Docs/audio-capture.md` measures what the cue does to the
recording.

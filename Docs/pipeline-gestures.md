# How a gesture becomes a dictation

`DictationController` (`Sources/UttrflowPipeline/DictationController.swift`) turns key presses,
floating-button clicks, menu items and system events into calls on the pipeline
([`pipeline.md`](pipeline.md)). The two activation modes (hold-to-talk and press-to-toggle) and
the double tap that leaves the microphone open differ only here, so neither the hotkey monitor
below it ([`shortcuts.md`](shortcuts.md)) nor the pipeline above it knows there is more than one
way to be recording.

| Constant | Value | What it decides |
|---|---|---|
| `DictationController.minimumHold` | 200 ms | the default hold length: a hold shorter than this is a slip, or a tap |
| `DictationController.modifierSettle` | 200 ms (`minimumHold`) | how long a modifier-only binding waits before a press counts |
| `DictationController.doubleTapWindow` | 450 ms | the default gap between two taps that makes them a double tap |
| `Settings.handsFreeDoubleTapChoices` | 450, 600, 800 ms | the gaps Settings › General › Double-tap speed offers |
| `Settings.handsFreeHoldChoices` | 200, 300, 500 ms | the hold lengths Settings › General › Hold length offers |

## One queue for every source

- `handle(_:)` suspends: it awaits the pipeline while the microphone opens. An actor is
  reentrant across that suspension, so a press and a release delivered as two independent tasks
  could interleave: the release runs first, sees a pipeline that is not listening yet, and
  returns; the press then completes and the recording is left running with nothing able to stop
  it. The microphone permission prompt on first launch makes `start()` take seconds, so a click
  would lose that race every time.
- So every gesture from every source goes through one `AsyncStream` and is handled one at a time.
  `submit(_:)` returns immediately and the work queues behind whatever is in flight; the
  shortcut's own stream is forwarded into the same queue rather than handled directly.
- A click from the floating button or a menu item is queued the same way. `toggleFromControl()`
  waits for its turn and returns once the click has been handled, so a caller that awaits it
  still sees the dictation it started or finished.
- The cap ([`stuck-recording.md`](stuck-recording.md)) is queued the same way. Its timer only
  submits "the cap was reached", and the queue closes the microphone, so the capped dictation
  ends like any other and a press made while it is processed is decided as the next section says.
  Each cap carries the generation of the dictation it was started for, and a cap that arrives
  after another dictation has begun neither finishes it nor stops that dictation's own cap.
- Sleep, screen lock and a switch of user end the dictation through the queue too
  (`endForSessionEnding()`): an open recording is finished and its words kept.

## A press made while the last dictation is processed

The queue holds a gesture only until the microphone has closed. Ending a dictation calls the
pipeline's `stopListening()`, which drains the microphone, moves the state to `.transcribing`,
and hands back a task for the rest: recognition, tidying, insertion, the paste confirmation,
counting and learning. The queue moves on while that task runs.

So a press made during those seconds is decided when it arrives, not replayed when they end: the
pipeline is busy, `startRecording()` refuses it, no cue sounds, and the release that follows finds
nothing listening and does nothing. The dock is showing the dictation still being processed, which
is what tells the user why. A press is never held until the words land and then judged by the
clock at that moment, because that turns a long hold into a slip and loses the start of a held
one.

The pipeline stays busy until the words are on screen. Counting and learning run after that, and
a press made then starts the next dictation, so those last steps read everything they need about
their own dictation before their first await.

`toggleFromControl()`, `setActivation(_:)` and `handle(_:)` return only once the words have been
inserted, without holding the queue while they wait.

## Rebinding the shortcut

- `start(binding:)` is called again whenever the user changes the shortcut, and it only rebinds
  the monitor. The monitor's `events` is one stream for the life of the monitor, and an
  `AsyncStream` has room for one reader: two consumers would each get whichever keypress they
  happened to be waiting for, so roughly every other press would vanish.
- So the controller reads that stream exactly once, in `init`, and never cancels it. A reader
  created per rebind is not used, for two reasons: the new reader could start before the
  cancelled one had finished, and cancelling the reader before `monitor.stop()` loses the release
  the monitor yields for a hold in progress, the one event that keeps a microphone from staying
  open. `stop()` calls `monitor.stop()` last for the same reason.

## Changing the activation mode

- `setActivation(_:)` is queued behind every other gesture, like a click, and returns once the
  new mode is in force. Run beside the queue, it could land while a press was still waiting for
  the microphone to open, see nothing recording, and let that press finish opening it under rules
  it was never given.
- A change to a different mode **finishes** any dictation under way and keeps its words. A
  recording belongs to the gesture that started it, and after the change that gesture no longer
  has a way to end: a hold switched to press-to-toggle ignores its release, and a toggle switched
  to hold-to-talk waits for a hold nobody is making. Left alone, the microphone would stay open
  until a stray press or the cap closed it.
- Finishing, not cancelling, matches the other ends nobody pressed a key for: a rebind mid-hold
  delivers the owed release, which finishes the hold ([`shortcuts.md`](shortcuts.md)), and the cap
  finishes and keeps the words. Speech from before opening Settings is inserted rather than lost.
- The change also forgets a modifier press still settling, a pending first tap and hands-free, so
  a release that arrives after the change opens nothing and the next press starts clean.
- Setting the mode the controller already has changes nothing, so a settings write that touches
  another field cannot stop a dictation.

## A click has no release

`toggleFromControl()` toggles, whatever the shortcut is set to: it finishes the dictation under
way, or begins one. What starts a dictation this way is a control, and the control is still there
to stop it; the dock says "click again" (`StopGesture.clickAgain`) until it does.

Pretending a click is a key is not used, and both ways of doing it fail. Sending `.pressed` and
`.released` together makes a hold shorter than the slip threshold, so the recording is cancelled
the instant it begins, or, when the microphone is slow to open, runs a whole dictation on a couple
of milliseconds of audio. Sending `.pressed` alone opens the microphone with nothing in
hold-to-talk able to close it: the next real hold is refused as busy, and its release finishes the
abandoned recording instead, inserting everything the microphone heard in between.

A tap of the shortcut during a click-started dictation finishes it the way a release would,
rather than discarding the words.

## A spoken command says which state it wants

`toggleFromControl()` is `command(.toggle)`. Voice Control, Switch Control and the Shortcuts app
also reach `command(.start)`, `command(.stop)` and `command(.cancel)` through the App Intents in
`DictationIntents.swift`, on the same gesture queue. A toggle is right for a control whose effect
the person can see; a command spoken without looking has to name the state it wants, or a
dictation still transcribing turns "stop" into a new start. Each command is judged against the
state the queue finds and returns a `DictationCommandOutcome`: Start while listening and Stop or
Cancel while idle change nothing and say so ("Already listening", "Nothing was recording"), and
Cancel discards the words as Escape does. A cancel of a long recording is said, sounded and offered
for Restore; see [recordings.md](recordings.md#cancelled-while-recording).

## The minimum hold

A hold shorter than `minimumHold` (200 ms) is a slip, not a dictation. Tapping the shortcut by
accident would otherwise start and instantly stop a recording, and the user would be told their
speech was too short to transcribe: an error for something they never meant to do. Cancelling
silently is the honest response. The controller is generic over its clock so this rule tests
exactly and instantly.

A slip is cancelled only when it is neither half of a pair nor made while hands-free (see below),
because the same 200 ms that decides a slip is what makes a tap countable. With hands-free switched
off there is no pair, so every short tap is an ordinary slip.

A binding made only of modifiers waits out `modifierSettle` before a press opens anything, so
another app's shortcut on those modifiers can arrive first and withdraw it; see
[`shortcuts.md`](shortcuts.md). A tap that ends inside that wait is still counted as a tap below;
it just never opens the microphone to be cancelled.

## Escape cancels

Escape pressed with no modifier held cancels the dictation under way in either mode, discards its
words, and forgets hands-free. Escape still reaches the frontmost app. It is accepted in every busy
state: once the key is released, Escape during transcribing, tidying or inserting returns the
pipeline to rest, nothing is written after it, and the recording is kept for a retry
([recordings.md](recordings.md)). A write already handed to the application cannot be recalled.

## Two taps, and the microphone stays open

Holding a key to talk is the right gesture for a sentence and the wrong one for a paragraph. So
two taps in quick succession leave the microphone open, and two more close it. `endHold()` is
where all of it happens.

A tap is a hold shorter than `minimumHold`. Two taps whose ends fall within the double-tap window
are one double tap. The window is 450 ms by default; Settings › General › Double-tap speed sets it
to 450, 600 or 800 ms (`Settings.handsFreeDoubleTapMilliseconds`), and the controller takes a new
value through `setDoubleTapWindow(_:)`. The first double tap turns hands-free on; the next turns it
off, as does any of the ends listed below.

The hold length is 200 ms by default; Settings › General › Hold length sets it to 200, 300 or
500 ms (`Settings.handsFreeHoldMilliseconds`), and the controller takes a new value through
`setMinimumHold(_:)`. A tap that pairs with nothing but ends within twice the double-tap window of
the last one is a near miss: `onNearMissTap` fires and VoiceOver says "Tap too slow, double-tap
faster", so the tap is not discarded in silence.

That makes three ways to be recording, and they do not overlap:

| gesture | starts | ends |
|---|---|---|
| hold | key down | key up |
| press to toggle | key down | the next key down |
| double tap | two taps | two more taps |

Two consequences look like bugs from outside:

- **A single tap while hands-free changes nothing.** It cannot cancel, because it may yet be the
  first half of the pair that ends the session. Only the second tap decides.
- **Releasing the key does nothing while hands-free.** There is no hold to end: the gesture that
  started this was two taps, and a release the user never thinks of as one should not stop them
  mid-sentence.

### However it ends, the next gesture works

Each of these ends a hands-free dictation and forgets it, so the next hold and the next double
tap open the microphone as usual:

- a second double tap;
- a click on a control: the menu bar's Stop Dictation, the panel's dictate button, Retry;
- the cap, which finishes the recording and keeps its words;
- a change of activation mode;
- switching Hands-free off in Settings, which finishes the recording and keeps its words;
- sleep, screen lock or a switch of user, which finish the recording and keep its words;
- pressing Escape, which cancels the recording and discards its words;
- the pipeline ending the recording on its own, such as a cancel: the next press notices the
  microphone is closed and forgets hands-free before acting.

**It can be switched off.** Settings › General › Hands-free is `Settings.handsFreeEnabled`, on by
default, and reaches the controller through `setHandsFreeEnabled(_:)`, queued like a change of
mode. Off, `endHold()` never pairs two taps and `endTapThatNeverOpened()` does nothing, so a
double tap is two slips and the microphone never stays open.

**It exists in hold-to-talk only.** `endHold()` is reached from `(.holdToTalk, .released)` and
nothing else; in press-to-toggle a release does nothing at all, so no tap is ever counted. The
gesture is not needed there: press-to-toggle already leaves the microphone open until the next
press, which is what the double tap gives somebody who chose to hold. Settings shows the
Hands-free and Double-tap speed rows only while the mode is hold-to-talk.

## The cue

The start cue plays only once the pipeline is listening, so a refused microphone does not make a
sound as though everything had worked. [`audio-capture.md`](audio-capture.md) measures what the
cue does to the recording.

# Watching for the shortcut

One keyboard source, one rule for deciding a shortcut is down, and one place that says what
each shortcut is for. Everything below is what the alternatives cost when they were tried.

## `NSEvent` cannot see Fn

`NSEvent.addGlobalMonitorForEvents(.flagsChanged)` is the obvious way to watch a held
modifier, and on macOS 26 it is **never told about Fn**. Measured side by side against a
`CGEventTap` over the same keypresses: the tap saw 23 events, `NSEvent` saw 0. The same
blindness applies to the polled sources — `NSEvent.modifierFlags` does not report Fn, and
neither does `CGEventSource.flagsState(.combinedSessionState)`.

This cost real time twice, because a monitor that reports nothing is indistinguishable from
a user whose keyboard is broken, and the second guess was to blame the hardware. It is not
the hardware. Anything that must see Fn goes through a tap.

## One tap: `SystemKeyboard`

A single `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .listenOnly)` on its own
`.userInteractive` thread, listening to `flagsChanged`, `keyDown` and `keyUp`. Listen-only, so
every key keeps doing whatever it did before. It is the only window-server code on this path,
and it is where flags are decoded into a `KeyStroke` — once, so nothing downstream reads a raw
flag word.

A tap on a starved thread is a tap macOS disables, which is why it gets a thread of its own.

## The field a flags change does not have

A `flagsChanged` event names one key and reports every modifier still held *after* it moved.
It does not say whether that key went down or up, and the first version of this threw the
question away: `KeyStroke` carried the key code and the resulting modifier set and nothing
else.

Releasing ⌥ while ⌘ was still held therefore looked exactly like pressing something, and the
recorder stored `{keyCode: 58, modifiers: [command]}` — Option's key code labelled Command.
It matched ⌘, ignored ⌥ and Fn, and presented as "I set it to Fn and nothing happens".

`KeyStroke.isKeyDown` answers it, derived at the tap from the one thing that settles it:
whether the key's own modifier survived the change. Fn follows `maskSecondaryFn`; every other
modifier follows its own bit.

## A binding must not contradict itself

`HotkeyBinding.isCoherent` refuses a key code whose own modifier its modifier set does not
contain. The pair above cannot be stored, and `Settings` substitutes the default for any
binding it cannot deliver, so one already on disk repairs itself on load.

Caps Lock is refused by the same rule. It sets no modifier flag at all, so a watcher reads it
as *nothing held* and fires on every modifier release. It was never bindable; now it says so.

## One recogniser: `HotkeyRecogniser`

Every binding shape goes through one type — Fn alone, one held modifier, several held
modifiers, and a modifier with a key against it. It is a pure value with no window server in
it, so every shape is tested as a sequence of `KeyStroke`s.

**Matching is by equality, not containment.** ⌃⌥ and ⌃⌥⌘ are different holds, and matching a
superset would fire a ⌃⌥ binding on the way to every ⌃⌥⌘ shortcut.

There was once a 250 ms timer that re-read the modifier state to catch a release the monitor
had missed. It polled a source that cannot see Fn, read "up" while Fn was held, and cancelled
the dictation the instant it started. It is gone: the tap delivers clean pairs, and the one
release worth guaranteeing is the one below.

## Modifiers bound alone begin other shortcuts

A binding made only of modifiers, such as ⌃⌘⌥, is the start of every shortcut on those
modifiers: ⌃⌘⌥K in another app holds exactly the chord before K arrives. The tap only listens,
so that app still gets K; what this app must not do is dictate as well.

`HotkeyRecogniser` withdraws such a press. A key typed while any modifier is held, or a modifier
the binding does not have, marks the hold as used by another shortcut: a press already reported
becomes `HotkeyEvent.cancelled` rather than `.released`, and nothing counts again until every
modifier is up. So ⌃⌥⇧⌘K on a ⌃⌘⌥ binding reports one press and one withdrawal, not a press for
each time ⇧ comes and goes. It applies only to holds of modifiers; Fn is read from its own flag
and a combination such as ⌥Space or ⇧⌘V already names its key.

A withdrawal alone would still open the microphone and play the start cue before K arrives, so
`DictationController` also holds such a press back for `modifierSettle` — the same 200 ms as the
minimum hold — before acting on it:

- **Withdrawn inside the settle:** nothing happens at all. No microphone, no cue, no insertion.
- **Held past the settle:** the press counts, measured from when the keys went down, so the
  minimum hold and the double tap keep their meaning.
- **Released inside the settle:** in hold-to-talk it is a tap, counted towards a double tap
  without opening the microphone; in press-to-toggle it toggles on the release.
- **Withdrawn after the settle:** the dictation that press opened is cancelled and nothing is
  inserted. A press that closed a toggled dictation has already finished it and is not undone.

The cost is that a modifier-only binding starts up to 200 ms later than it did. Bindings with a
key, and Fn, start as they always have.

## The release nobody else will send

`ActivationMonitor.stop()` yields a release when it is stopped mid-hold, because a hold
interrupted by a rebind would otherwise leave the microphone open forever — the worst failure
this product has.

That release is easy to lose. `DictationController.stop()` used to cancel its event forwarder
one line *before* calling `monitor.stop()`, so the release was yielded into a stream nobody
was reading. The controller now reads the monitor's stream **once, for its life**, which also
removes the second hazard: an `AsyncStream` has room for one reader, and creating a new one
per rebind meant two consumers splitting keypresses between them.

## Carbon, only where a key must be swallowed

`CarbonHotkeyMonitor` stays for ⇧⌘V. `RegisterEventHotKey` **consumes** the combination, which
a listen-only tap cannot do, and without that the clipboard panel would open *and* the app
underneath would paste without formatting. It is kept for that one property; it cannot bind a
held modifier or Fn at all.

So delivery is a property of the shortcut: most are **observed** through the tap, and one is
**claimed** through Carbon.

## Re-registering a claimed shortcut

Carbon refuses a combination this process already holds, with `-9878`
(`eventHotKeyExistsErr`), and does not refuse one another process holds. Measured from a test
process: registering ⇧⌘V twice answers `0` then `-9878`, and `0` again once the first is
unregistered. A refused registration is not consumed, so the key reaches the frontmost app —
for ⇧⌘V, a paste without formatting.

Every change to the shortcuts, and every activation while one is unarmed, stops all the
claimed monitors and registers them again. On the main thread `stop()` unregisters before it
returns, so that sequence cannot collide with itself. Off the main thread `stop()` takes the
registration out at once and queues the Carbon call for the main thread; the next
registration runs that queue before it registers. Without the queue, a rebind that ran before
the hop was refused with `-9878`, and the hop then removed the old registration too, leaving
the key held by nobody. `CarbonHotkeyLifecycleTests` drives both orders through the real
monitor.

Whether a registration that succeeded is delivered is a window-server question no test here
can answer: a key event posted from a test process did not fire a Carbon hot key even with a
single registrant, so delivery is checked by pressing the key on a real build.

## Secure keyboard entry hides the shortcut

While any process has secure event input on, macOS stops passing key down and key up events to
event taps. A password field turns it on while it has focus; a terminal's "secure keyboard entry"
option turns it on while that terminal is frontmost, or for as long as the option is on; and an
app that forgets to turn it off leaves it on for every app. The tap is not disabled, so nothing
re-enables it and nothing is logged by the tap itself.

What it affects is every dictation binding with a key in it, such as the default ⌥Space. A binding
made only of held modifiers is read from modifier changes rather than key presses, but the notice is
shown whatever the binding, because the check says only that secure input is on. The Carbon hot keys the clipboard and other
claimed shortcuts use are delivered anyway, so the clipboard panel can open while dictation cannot.
Start Dictation in the menu bar and the floating button still work, because neither goes through
the tap.

`SecureInputWatch` asks `IsSecureEventInputEnabled()` when another app becomes active and when the
menu bar menu opens — never on a timer, which the energy budget in `Docs/performance.md` rules
out. When the answer changes, the menu shows the reason under its status line and the floating
button's hover hint says it in place of the keycap, until a later check finds it off again. An app
that turns secure input on a moment after it becomes active is caught by the next menu open
rather than by the switch.

## What a shortcut is for

`ShortcutSet` holds every binding by `ShortcutAction`, and is what `Settings` stores. A file
written before it — with `hotkey` and `clipboardHotkey` as separate fields — is read once
through `LegacyShortcutKeys` and migrated; the three-way distinction those fields had is kept,
so an absent clipboard shortcut still means the default and an explicit `null` still means off.

`ShortcutRegistry` names each action and explains it, and the settings screen is generated
from it. Adding a shortcut is adding an entry there, not a settings field, a monitor and a row.

`hotkeyActivation` is still stored, and now outlives the condition it was given. A double tap on
the dictation key has meant hands-free since 0.5.0, which was the thing this was waiting for — but
removing the setting would still take press-to-toggle away from everyone using it, and the double
tap does not replace it: it is reached from `(.holdToTalk, .released)` only, and gives somebody
who chose to hold what press-to-toggle already gave everybody else. See
`Docs/pipeline-gestures.md`.

## What is testable

Everything that decides anything. `HotkeyRecogniser`, `SettingsShortcutRecorder`, `ShortcutSet`
and the settings decoding are pure values driven by `KeyStroke` sequences, with no window
server involved. `SystemKeyboard` and `ActivationMonitor` are on the coverage exclusion list
because they only create the tap and pass strokes on — what is made of those strokes is tested
against every shape of binding. How a stroke is passed on is tested too: `Delivery` holds the sink
as a struct around the closure, never the bare closure, because a closure read out of a `Mutex` is
re-wrapped on every read and the stack deepened by each keystroke until the tap's thread overflowed.
`SystemKeyboardDeliveryTests` checks that the 500th stroke, and the release after it, cost no more
stack than the first.

The parts that cannot be unit-tested are exercised by posting synthetic `CGEvent`s at the real
app and watching the recording window appear. That proves the tap, the Accessibility grant and
the UI agree; it proves nothing about what was said, which is `uttrflow-dev dictate`'s job.

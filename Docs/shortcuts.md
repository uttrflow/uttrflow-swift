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

## What a shortcut is for

`ShortcutSet` holds every binding by `ShortcutAction`, and is what `Settings` stores. A file
written before it — with `hotkey` and `clipboardHotkey` as separate fields — is read once
through `LegacyShortcutKeys` and migrated; the three-way distinction those fields had is kept,
so an absent clipboard shortcut still means the default and an explicit `null` still means off.

`ShortcutRegistry` names each action and explains it, and the settings screen is generated
from it. Adding a shortcut is adding an entry there, not a settings field, a monitor and a row.

`hotkeyActivation` is still stored. It will go when a double tap on the dictation key means
hands-free, and not before — removing it first would silently take press-to-toggle away from
everyone using it.

## What is testable

Everything that decides anything. `HotkeyRecogniser`, `SettingsShortcutRecorder`, `ShortcutSet`
and the settings decoding are pure values driven by `KeyStroke` sequences, with no window
server involved. `SystemKeyboard` and `ActivationMonitor` are on the coverage exclusion list
because they only create the tap and pass strokes on — what is made of those strokes is tested
against every shape of binding.

The parts that cannot be unit-tested are exercised by posting synthetic `CGEvent`s at the real
app and watching the recording window appear. That proves the tap, the Accessibility grant and
the UI agree; it proves nothing about what was said, which is `uttrflow-dev dictate`'s job.

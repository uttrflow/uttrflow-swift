# Watching for the shortcut

Uttrflow has one keyboard source, one rule for deciding a shortcut is down, and one list that
says what each shortcut is for. The event tap is `SystemKeyboard`
(`Sources/UttrflowInput/SystemKeyboard.swift`); the dictation shortcut is watched by
`ActivationMonitor` and decided by `HotkeyRecogniser` (`Sources/UttrflowCore/Keyboard/`); the
shortcuts that must swallow their keys are registered by `CarbonHotkeyMonitor`; and the list of
shortcuts is `ShortcutRegistry` (`Sources/UttrflowUX/ShortcutRegistry.swift`). What happens to a
press after that is [`pipeline-gestures.md`](pipeline-gestures.md).

## The shortcuts and how each is delivered

| Action | Default | Delivery |
|---|---|---|
| Dictate | ⌃⌥ held (`HotkeyBinding.controlOptionHold`) | observed through the tap |
| Clipboard | ⇧⌘V | claimed through Carbon |
| Paste last transcript | ⌃⌘V | claimed through Carbon |
| Copy last transcript | ⌃⌘C | claimed through Carbon |
| Edit command | ⌃⇧ held (`HotkeyBinding.controlShiftHold`) | observed through a second tap; see [`commands.md`](commands.md) |

The defaults are `ShortcutSet.default`. An **observed** shortcut is watched through the one event
tap, which sees Fn and leaves the key doing what it did. A **claimed** shortcut is registered as a
hot key, which swallows the combination so nothing else acts on it too (`ShortcutDelivery`).

## `NSEvent` cannot see Fn

`NSEvent.addGlobalMonitorForEvents(.flagsChanged)` is the obvious way to watch a held modifier,
and on macOS 26 it is **never told about Fn**. Measured side by side against a `CGEventTap` over
the same keypresses: the tap saw 23 events, `NSEvent` saw 0. The polled sources are blind to it
too: `NSEvent.modifierFlags` does not report Fn, and neither does
`CGEventSource.flagsState(.combinedSessionState)`.

A monitor that reports nothing is indistinguishable from a broken keyboard, so the symptom points
at the hardware. It is not the hardware. Anything that must see Fn goes through a tap.

## One tap: `SystemKeyboard`

A single `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, …)` on its own
`.userInteractive` thread, listening to `flagsChanged`, `keyDown` and `keyUp`. The shortcut
monitor asks for `.listenOnly`, so every key keeps doing whatever it did before; only a caller
that passes `consumeKeyDown: true` gets a `.defaultTap` that can swallow its key-downs. It is the
only window-server code on this path, and it is where flags are decoded into a `KeyEvent`, once,
so nothing downstream reads a raw flag word. Events Uttrflow posts itself (`SyntheticEvent`) are
passed over.

A tap on a starved thread is a tap macOS disables, which is why it gets a thread of its own.

## When macOS switches the tap off

macOS disables a tap that is slow to answer (`tapDisabledByTimeout`) or on user input
(`tapDisabledByUserInput`). The callback turns it back on, unless it has been disabled
repeatedly in a short time:

| Constant | Value | Meaning |
|---|---|---|
| `TapDisableWindow.windowNanoseconds` | 60 s | two disables closer than this count as one fault, so sleep and wake do not add up |
| `TapDisableWindow.limit` | 2 | disables inside the window before the tap is left off |
| `ActivationMonitor.defaultRestSeconds` | 90 s | how long the monitor rests before rebuilding a tap that gave up |

When the tap gives up, `ActivationMonitor` delivers the release owed for any hold in progress,
logs it under the `shortcuts` category, rests, and rebuilds the tap with the same binding. A
refused tap is reported as `HotkeyError.observationNotPermitted` when Accessibility is off and
`.accessibilityNeedsRefresh` when it is on but the system still refuses.

## The field a flags change does not have

A `flagsChanged` event names one key and reports every modifier still held *after* it moved. It
does not say whether that key went down or up. A stroke that kept only the key code and the
resulting modifiers would read releasing ⌥ while ⌘ is still held exactly like pressing
something, and a recorder would store `{keyCode: 58, modifiers: [command]}`: Option's key code
labelled Command, which matches ⌘ and ignores ⌥ and Fn.

`KeyEvent.isKeyDown` answers it, derived at the tap from the one thing that settles it: whether
the key's own modifier survived the change. Fn follows `maskSecondaryFn`; every other modifier
follows its own bit.

## A binding must be deliverable

`HotkeyBinding.isDeliverable` is the one test a binding passes before it is stored or watched:

- **Coherent** (`isCoherent`): a modifier key code whose own modifier its modifier set does not
  contain is refused, so the pair above cannot be stored. Caps Lock is refused by the same rule:
  it sets no modifier flag, so a watcher would read it as *nothing held* and fire on every
  modifier release.
- **Usable** (`isUsable`): it has a modifier, or is a hold of modifiers. A single modifier held
  alone, such as ⌘, is refused (`isBareModifier`), because it would also fire on every shortcut
  that uses that key.
- A key code above `HotkeyBinding.highestKeyCode` is not from a keyboard and is refused.

`ShortcutSet` drops any binding that fails, so nothing undeliverable is ever held. A settings file
that bound an action only to a bare modifier is read with that action's default back, and the
Shortcuts row says so ("This was a key held on its own, which also fired on every shortcut using
that key, so it is back to the default.").

## One recogniser: `HotkeyRecogniser`

Every binding shape goes through one type: Fn alone, one held modifier, several held modifiers,
and a modifier with a key against it. It is a pure value with no window server in it, so every
shape is tested as a sequence of `KeyEvent`s.

**Matching is by equality, not containment.** ⌃⌥ and ⌃⌥⌘ are different holds, and matching a
superset would fire a ⌃⌥ binding on the way to every ⌃⌥⌘ shortcut.

**Escape** pressed with no modifier held is reported as `HotkeyEvent.escapePressed`, which cancels
the dictation under way.

Both hotkey monitors start a 250 ms reconciliation poll (`reconciliationMilliseconds`) when they
report a press and stop it when they report or reconcile the release; it checks the real key state
only during that hold. See [`stuck-recording.md`](stuck-recording.md) for the lost-release cases it
covers.

## Modifiers bound alone begin other shortcuts

A binding made only of modifiers, such as ⌃⌥, is the start of every shortcut on those modifiers:
⌃⌥K in another app holds exactly the chord before K arrives. The tap only listens, so that app
still gets K; what this app must not do is dictate as well.

`HotkeyRecogniser` withdraws such a press. A key typed while any modifier is held, or a modifier
the binding does not have, marks the hold as used by another shortcut: a press already reported
becomes `HotkeyEvent.cancelled` rather than `.released`, and nothing counts again until every
modifier is up. So ⌃⌥⇧K on a ⌃⌥ binding reports one press and one withdrawal, not a press for
each time ⇧ comes and goes. The same rule applies to Fn: a key pressed while Fn is held withdraws
the Fn press. Fn is read from its own flag, so an arrow key's Fn flag alone does not start a hold;
a combination such as ⌥Space or ⇧⌘V already names its key.

A withdrawal alone would still open the microphone and play the start cue before K arrives, so
`DictationController` holds modifier-only presses back for `modifierSettle` (200 ms, the same as
the minimum hold) before acting on them. The pipeline opens the microphone at key-down while the
press settles (`beginModifierPress`), so speech from the first instant is kept and only the
dictation itself waits:

- **Withdrawn inside the settle:** the microphone closes and nothing else happens. No cue, no
  insertion.
- **Held past the settle:** the press counts, measured from when the keys went down, so the
  minimum hold and the double tap keep their meaning.
- **Released inside the settle:** in hold-to-talk it is a tap, counted towards a double tap
  without opening a dictation; in press-to-toggle it toggles on the release.
- **Withdrawn after the settle:** the dictation that press opened is cancelled and nothing is
  inserted. A press that closed a toggled dictation has already finished it and is not undone.

Bindings with a key, and Fn, are not held back.

## Sticky Keys: not yet measured

Sticky Keys latches a modifier after one press and releases it after the next key. The recogniser
reads a hold as over when the modifier's own flag clears, so if a latched flag stays set after the
finger lifts, hold-to-talk would record until the next key, and that key would read as another
shortcut and cancel the dictation. Whether the tap sees that is not known yet, and no change is
made to the recogniser until it is.

`uttrflow-dev probe modifiers` measures it. It opens the same `SystemKeyboard` tap the app uses,
feeds every stroke to a `HotkeyRecogniser` on the default dictation binding, and prints one row
per stroke (time, phase, key code, `isKeyDown`, modifiers, Fn, event) plus whether the system
reports Sticky Keys on. It only reads the setting. Quit the app first so its tap is not also
running.

```bash
swift build --product uttrflow-dev
.build/debug/uttrflow-dev probe modifiers --seconds 30
```

Run it once with Sticky Keys off and once with it on (System Settings › Accessibility ›
Keyboard), and in each run do three gestures, a few seconds apart:

1. Press ⌃⌥ once, hold about a second, release.
2. Press ⌃⌥ twice quickly.
3. Press ⌃⌥, release, then type `a`.

Paste both logs here. If the rows match, the recogniser needs nothing and the issue closes with
them. If they differ, the rows become replay fixtures in `HotkeyRecogniserTests`, and the change
is the smallest one those rows require.

## The release nobody else will send

`ActivationMonitor.stop()` yields a release when it is stopped mid-hold, because a hold
interrupted by a rebind would otherwise leave the microphone open forever. The controller reads
the monitor's stream **once, for its life**, and stops the monitor last, so that release always
has a reader; see [`pipeline-gestures.md`](pipeline-gestures.md).

## Carbon, only where a key must be swallowed

`CarbonHotkeyMonitor` registers the claimed shortcuts. `RegisterEventHotKey` **consumes** the
combination, which a listen-only tap cannot do; without that, ⇧⌘V would open the clipboard panel
*and* the app underneath would paste without formatting. Carbon is kept for that one property; it
cannot bind a held modifier or Fn at all.

## Re-registering a claimed shortcut

Carbon refuses a combination this process already holds, with `-9878` (`eventHotKeyExistsErr`),
and does not refuse one another process holds. Measured from a test process: registering ⇧⌘V
twice answers `0` then `-9878`, and `0` again once the first is unregistered. A refused
registration is not consumed, so the key reaches the frontmost app; for ⇧⌘V, a paste without
formatting.

Every change to the shortcuts, and every activation while one is unarmed, stops all the claimed
monitors and registers them again. On the main thread `stop()` unregisters before it returns, so
that sequence cannot collide with itself. Off the main thread `stop()` takes the registration out
at once and queues the Carbon call for the main thread; the next registration runs that queue
before it registers. Without the queue, a rebind that ran before the hop would be refused with
`-9878`, and the hop would then remove the old registration too, leaving the key held by nobody.
`CarbonHotkeyLifecycleTests` drives both orders through the real monitor.

Whether a registration that succeeded is delivered is a window-server question no test here can
answer: a key event posted from a test process does not fire a Carbon hot key even with a single
registrant, so delivery is checked by pressing the key on a real build.

## A dictation shortcut that could not be armed

When `controller.start(binding:)` throws, because another app holds the combination or
Accessibility access is off, `ShortcutArming` keeps the error as its own state. It is not a
dictation, so it never goes through `render(_:)`: nothing is counted in telemetry, nothing is
logged as a failed dictation, no sweep runs, and nothing dismisses it after a few seconds. The menu
bar popover's header and the floating button's hover hint show the reason, the same places that
report secure keyboard entry, and they keep showing it until an arming works. Secure input is
shown first when both apply, since it blocks every binding. Arming is retried each time Uttrflow
becomes active, and turning dictation off forgets the failure. A recording already under way keeps
its own presentation, because the popover shows an unheard shortcut only while nothing is being
dictated.

## Secure keyboard entry hides the shortcut

While any process has secure event input on, macOS stops passing key down and key up events to
event taps. A password field turns it on while it has focus; a terminal's "secure keyboard entry"
option turns it on while that terminal is frontmost, or for as long as the option is on; and an
app that forgets to turn it off leaves it on for every app. The tap is not disabled, so nothing
re-enables it and nothing is logged by the tap itself.

It affects every dictation binding with a key in it, such as ⌥Space. A binding made only of held
modifiers is read from modifier changes rather than key presses, but the notice is shown whatever
the binding, because the check says only that secure input is on. The claimed shortcuts are
delivered anyway, so the clipboard panel can open while dictation cannot. Talk in the menu bar
popover and the floating button still work, because neither goes through the tap.

`SecureInputWatch` asks `IsSecureEventInputEnabled()` when another app becomes active and when the
menu bar popover opens, never on a timer, which the energy budget in
[`performance.md`](performance.md) rules out. When the answer changes, the popover shows the reason
in its header and the floating button's hover hint says it in place of the keycap, until a later
check finds it off again. An app that turns secure input on a moment after it becomes active is
caught by the next popover open rather than by the switch.

## What a shortcut is for

`ShortcutSet` holds every binding by `ShortcutAction`, and is what `Settings` stores. An action can
have more than one binding, or none. A settings file that has `hotkey` and `clipboardHotkey` as
separate fields instead is read once through `Settings.LegacyShortcutKeys` and migrated; the
three-way distinction those fields had is kept, so an absent clipboard shortcut means the default
and an explicit `null` means off.

`ShortcutRegistry` names each action and explains it, and the settings screen is generated from
it. Adding a shortcut is adding an entry there, not a settings field, a monitor and a row.

`hotkeyActivation` (Settings › General › How holding works) chooses hold-to-talk or
press-to-toggle. The double tap does not replace press-to-toggle: it is reached from
`(.holdToTalk, .released)` only, and gives somebody who chose to hold what press-to-toggle already
gives. See [`pipeline-gestures.md`](pipeline-gestures.md).

## The dictation shortcut a new install gets

A new install dictates with ⌃⌥ held: `HotkeyBinding.controlOptionHold`, a hold of two modifiers
that `HotkeyRecogniser` reads like any other and that settles for `modifierSettle` before it
counts. An install onboarded while ⌥Space was the default keeps it: `ShortcutSet.earlierDefault`.

The settings file is what tells the two apart, and settings are saved only when something is
changed, so an install whose user never opened Settings has none. At launch, before the first
read, `UserDefaultsSettingsStore.pinDefaults(onboarded:)` saves one when it is missing or is not a
JSON object: `Settings.earlierInstall` (⌥Space and a week of transcripts) when the onboarding
record says onboarding finished, the current defaults otherwise. A later change of default
therefore never moves anybody. A saved file that names no dictation shortcut is read with ⌥Space
for the same reason. Reset in Settings gives back ⌃⌥, the current default, to everybody.

## What is testable

Everything that decides anything. `HotkeyRecogniser`, `SettingsShortcutRecorder`, `ShortcutSet`
and the settings decoding are pure values driven by `KeyEvent` sequences, with no window server
involved. `SystemKeyboard` and `ActivationMonitor` are on the coverage exclusion list because they
only create the tap and pass strokes on; what is made of those strokes is tested against every
shape of binding. How a stroke is passed on is tested too: `Delivery` holds the sink as a struct
around the closure, never the bare closure, because a closure read out of a `Mutex` is re-wrapped
on every read and the stack deepens with each keystroke until the tap's thread overflows.
`SystemKeyboardDeliveryTests` checks that the 500th stroke, and the release after it, cost no more
stack than the first.

The parts that cannot be unit-tested are exercised by posting synthetic `CGEvent`s at the real app
and watching the recording window appear. That proves the tap, the Accessibility grant and the UI
agree; it proves nothing about what was said, which is `uttrflow-dev dictate`'s job.

## The clipboard panel's own keys

The global shortcut opens the panel; everything after that is the panel's, and all of it works
without the pointer. The row chords live in one table, `PanelRowAction.chord`
(`Sources/UttrflowUX/PanelShortcuts.swift`), which the key handler, the ⋯ menu's labels and this
list all read, so none of the three can drift from the others.

| Key | What it does |
|---|---|
| ↑ ↓ | Move the highlight one row |
| Page Up / Page Down | Move a screenful |
| Home / End | The first row, the last row |
| ⏎ | Paste the highlighted clip |
| ⌘⏎ | Paste it without its formatting |
| esc | Close the sheet, or the panel |
| ⌘1–⌘9 | Browse a collection, by the number printed beside it |
| ⌘Z | Put back the clip the last delete removed |
| ⌘R | Reveal a masked clip |
| ⌘⇧C | Copy it to the clipboard |
| ⌘P | Pin it, or unpin it |
| ⌘N | Name it, or rename it |
| ⌘M | File it into a collection |
| ⌘⇧F | Format it |
| ⌘⇧I | Re-indent it |
| ⌘⇧T | Make it a note |
| ⌘⇧⌫ | Delete it |

A chord does nothing where the highlighted row does not offer that action, because the handler
reads the row's own action list rather than a second copy of the rules: Format is offered only
where a formatter exists for the clip's language, and Reveal only on a masked clip.

⌫ and ⌘⌫ are left to the search field, which is why Delete takes ⇧ as well; ⌘C is the field's
copy, so the row's is ⌘⇧C. A chord that acted on a row only while the field was empty would be a
trap, so none of them does. ⌘Z undoes typing in the search field first, unless a restore is on
offer; ⇧⌘Z stays Redo.

The panel takes its row chords before the main menu sees them (`QuickPanel.performKeyEquivalent`).
Window ▸ Minimise is also ⌘M, and the menu swallows a key equivalent even when its item is
disabled, so without that ⌘M would never reach Move. See [`panel.md`](panel.md).

Row chords and ⌘Z match the Latin letter the active keyboard layout produces. When a layout
produces no Latin letter, the panel falls back to the US key position so shortcuts remain usable
with Cyrillic and other non-Latin layouts.

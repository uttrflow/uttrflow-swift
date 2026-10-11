# Shortcut bindings: what `HotkeyBinding` decides and why

`HotkeyBinding` in `Sources/UttrflowCore/Protocols/HotkeyMonitoring.swift` is a key code and a set
of modifiers, and it decides whether macOS can ever deliver that combination. The same file holds
`HotkeyError` and the `HotkeyMonitoring` protocol. `CarbonHotkey`
(`Sources/UttrflowInput/CarbonHotkeyTranslation.swift`) translates a binding for registration,
`SettingsEditor.rejection(forShortcut:for:)` (`Sources/UttrflowUX/SettingsEditor.swift`) is the one
gate a shortcut passes to be saved, and `ShortcutSet` (`Sources/UttrflowCore/Keyboard/ShortcutSet.swift`)
holds every action's bindings. [`shortcuts.md`](shortcuts.md) covers the monitors that watch for
them; this page covers the decisions baked into the binding type.

## The shipped shortcuts

| Action | Default | Constant | Delivery |
|---|---|---|---|
| Dictate | ⌃⌥ held | `HotkeyBinding.controlOptionHold` | `.observed` |
| Clipboard panel | ⇧⌘V | `HotkeyBinding.shiftCommandV` | `.claimed` |
| Paste last dictation | ⌃⌘V | `HotkeyBinding.controlCommandV` | `.claimed` |
| Copy last dictation | ⌃⌘C | `HotkeyBinding.controlCommandC` | `.claimed` |

`ShortcutSet.default` holds these. An install that finished onboarding before ⌃⌥ held became the
default keeps ⌥Space (`HotkeyBinding.optionSpace`, `ShortcutSet.earlierDefault`). Delivery is
`ShortcutRegistry`'s: an observed shortcut is watched through the event tap and leaves the key doing
what it did; a claimed one is registered as a Carbon hot key, which swallows the combination.

## ⇧⌘V for the clipboard panel

Many apps bind ⇧⌘V to "paste without formatting" (macOS's own binding for that is ⌥⇧⌘V, which
stays untouched). A global hot key shadows those, and that is a trade made on purpose: the panel
it opens can paste any clip without its formatting with ⌘↩ (`PanelKey.returnPlain`), not only the
most recent one. Anyone who disagrees can rebind it; every shortcut is a stored `HotkeyBinding`,
not a constant.

`RegisterEventHotKey` accepts ⇧⌘V, and also accepts plain ⌘V. A successful registration says only
that no other Carbon hot key holds the combination, never that the combination is free; an app's
own menu-key handling is invisible to it. So shadowing cannot be tested for. It is a decision.

## A held modifier is watched, not registered

The window server accepts a modifier registered as a hot key and then never fires it. A binding
whose key code is one of `HotkeyBinding.modifierKeyCodes` is therefore a *hold*, delivered by
watching flag changes: `heldModifier` returns it, and it is kept off the registered path. Fn is
the one key whose code carries no modifier flag of its own, so it is the one case where
`modifiers` is legitimately empty (`HotkeyBinding.functionHold`, `isFunctionHold`).

Any combination of modifiers is allowed as a hold, and so is Fn on its own. **⌘, ⌥, ⌃ or ⇧ on its
own is not** (`isBareModifier`). A key that is part of every shortcut using it cannot also mean
"dictate": a held ⌘ would fire on every ⌘C, a held right ⌥ would end a dictation at ⌥→ (the arrow
carries the function flag and breaks the match) and begin another at ⌥A, left and right would not
be told apart, and two quick ⌘-shortcuts could meet the double-tap rule and switch hands-free on.
Fn is the exception because `HotkeyRecogniser` reads it only from its own flags-changed event,
which no other shortcut sends.

A bare modifier fails `isUsable`, so it is not `isDeliverable` either. The recorder and
`SettingsEditor` refuse it with `SettingsEditor.bareModifier`, which names the two ways out (add a
key or another modifier, or hold Fn). A settings file that already holds one returns that action
to its default when it is read, unless another action has taken the default keys, and records the
action in `Settings.shortcutsReturnedToDefault`; the shortcut's row then says why
(`SettingsPresenter.returnedToDefault`) until the user chooses again. See
[`settings-decoding.md`](settings-decoding.md).

The codes, held as a set rather than a range because the range they occupy is a coincidence of the
layout tables:

| Code | Key | Code | Key |
|---|---|---|---|
| 54 | ⌘ right | 59 | ⌃ left |
| 55 | ⌘ left | 60 | ⇧ right |
| 56 | ⇧ left | 61 | ⌥ right |
| 57 | Caps Lock | 62 | ⌃ right |
| 58 | ⌥ left | 63 | Fn (`functionKeyCode`) |

## When a binding is undeliverable

The window server refuses none of these and then never fires any of them:

| Binding | Answered by |
|---|---|
| no modifier and not a held key: a bare letter fires while typing | `isUsable` |
| ⌘, ⌥, ⌃ or ⇧ held on its own | `isUsable` (via `isBareModifier`) |
| key code above `0x7F` (`highestKeyCode`), which no keyboard sends | `isDeliverable` |
| key code and modifiers disagree: a held modifier whose own flag is missing, Fn alongside a modifier, or Caps Lock, which names no modifier and is never seen held | `isCoherent` |

`isDeliverable` answers the whole question as a yes or no; the settings store uses it to decide
whether a stored shortcut can be honoured, and `ShortcutSet` drops any binding that fails it.

The rules are stated twice, in `HotkeyBinding` and in `CarbonHotkey`, because `UttrflowCore` cannot
import the Carbon headers the translator names its key codes from.
`CarbonHotkeyTranslationTests.deliverabilityMatchesTranslation` holds the two to the same answer
for every key code from 0 to 300. The translator does not use `isUsable`, so its refusal of a bare
modifier is `.modifierUsedAsKey` rather than `.noModifiers`.

## One more refusal, only for a claimed action

`isDeliverable` accepts a held-modifier combination, because for `ShortcutDelivery.observed` it is
watched through flag changes. For `ShortcutDelivery.claimed` it cannot be: `CarbonHotkey.init`
refuses every binding whose key code is itself a modifier with `.modifierUsedAsKey`, because
`RegisterEventHotKey` accepts that registration and then never fires it.
`SettingsEditor.rejection(forShortcut:for:)` is delivery-aware for this: it refuses a held chord
for a claimed action with `SettingsEditor.heldChordNotClaimable` before it reaches the registry, so
Dictate accepts held chords and the three claimed actions never store one they cannot arm.

## `start(binding:)` is main-actor isolated

A system-wide shortcut is delivered on the run loop of the thread that asked for it, and the main
thread is the only one this process runs a run loop on. Registering from an actor's executor
succeeds and then never fires, which nothing can detect afterwards, so the requirement is stated in
the protocol (`@MainActor func start(binding:) throws(HotkeyError)`) and callers hop once before
asking. Whether it worked is known before `start` returns; a monitor that answered asynchronously
would have nowhere to put a refusal.

## Every hotkey error is blocking

A shortcut that never fires means no dictation at all; there is no second way into the product.
So all three `HotkeyError` cases declare `.blocking` severity:

| Case | Recovery |
|---|---|
| `observationNotPermitted` | `.openSystemSettings(.accessibility)` |
| `accessibilityNeedsRefresh` | `.retry` |
| `shortcutUnavailable` | `.retry` |

`observationNotPermitted` asks for the same Accessibility pane as several genuinely degraded
failures, which is why severity is declared rather than read off the recovery action.

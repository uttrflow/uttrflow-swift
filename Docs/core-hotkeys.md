# Shortcut bindings: what `HotkeyBinding` decides and why

`Docs/shortcuts.md` covers the two monitors. This page covers the decisions baked into
the binding type itself.

## ⇧⌘V for the clipboard panel

Chrome, Slack, VS Code and most Electron apps bind ⇧⌘V to "paste without formatting"
(macOS's own binding for that is ⌥⇧⌘V, which stays untouched). A global hot key shadows
those, and that is a trade made on purpose: the panel it opens can paste any clip as
plain text with ⌘↩, not only the most recent one. Anyone who disagrees can rebind it;
every shortcut is a stored `HotkeyBinding`, not a constant.

Measured: `RegisterEventHotKey` accepts ⇧⌘V, and also accepts plain ⌘V. A successful
registration says only that no other Carbon hot key holds the combination, never that
the combination is free; an app's own menu-key handling is invisible to it. So shadowing
cannot be tested for. It is a decision.

## A held modifier is watched, not registered

The window server accepts a modifier registered as a hot key and then never fires it. A
binding whose key code is one of `HotkeyBinding.modifierKeyCodes` is therefore a *hold*,
delivered by watching flag changes, and is admitted by `heldModifier` while being excluded
from the registered path. Fn is the one key whose code carries no modifier flag of its
own, so it is the one case where `modifiers` is legitimately empty.

Any modifier combination is allowed as a hold, ⌘ on its own included. ⌘ alone fires on
every ⌘C; that is the owner of the Mac's decision, not the type's. What is refused is only
what cannot be delivered: see `isDeliverable`.

The codes, held as a set rather than a range because the range they occupy is a
coincidence of the layout tables:

    54 ⌘ right · 55 ⌘ left · 56 ⇧ left · 57 Caps Lock · 58 ⌥ left
    59 ⌃ left · 60 ⇧ right · 61 ⌥ right · 62 ⌃ right · 63 Fn

## Three ways a binding is undeliverable

The window server refuses none of them and then never fires any: a shortcut with no
modifier, a key code above `0x7F` that no keyboard can send, and a modifier held on its
own. `isUsable` answers only the first, because the monitor's translator reports the three
apart to say which one is wrong; `isDeliverable` answers the whole question for a yes or
no, chiefly the settings store deciding whether a stored shortcut can be honoured.

The rules are stated twice, in `HotkeyBinding` and in the translator, because
`UttrflowCore` cannot import the platform headers the translator names its key codes from.
A test holds the two to the same answer.

## `start(binding:)` is main-actor isolated

A system-wide shortcut is delivered on the run loop of the thread that asked for it, and
the main thread is the only one this process runs a run loop on. Registering from an
actor's executor succeeds and then never fires, which nothing can detect afterwards, so the
requirement is stated in the type and callers hop once before asking. Whether it worked is
known before `start` returns; a monitor that answered asynchronously would have nowhere to
put a refusal.

## Both hotkey errors are blocking

A shortcut that never fires means no dictation at all; there is no second way into the
product. `observationNotPermitted` asks for the same Accessibility pane as several
genuinely degraded failures, which is why severity is declared rather than read off the
recovery action.

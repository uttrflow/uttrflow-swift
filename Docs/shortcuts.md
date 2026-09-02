# Watching for the shortcut

Two mechanisms, because macOS offers no one way to do both. `ActivationMonitor` chooses
between them and callers never know which answered.

## A combination: `CarbonHotkeyMonitor`

`RegisterEventHotKey` needs no permission at all, delivers the release as well as the
press — which hold-to-talk is built on — and was measured here at well under a tenth of
a millisecond.

A `CGEventTap` was the alternative and is worse: a tap sees nothing until the user has
granted Accessibility, so the app would have to ask permission to read every keystroke
in every app merely to learn when to start listening, before it has ever done anything
useful.

The price is that Carbon swallows the keystroke — there is no pass-through option —
which for a shortcut reserved for dictation is what we want anyway.

**One handler for the process, not one per monitor.** `InstallEventHandler` refuses the
same handler function on the same target twice (`eventHandlerAlreadyInstalledErr`,
−9866). The clipboard panel has a shortcut of its own, so a per-instance install meant
whichever monitor registered second silently got nothing. The handler dispatches on
`EventHotKeyID.id`, so one install has always been able to serve any number of
shortcuts.

**The handler must be installed on the same event target the hot key is registered
against.** Pairing `GetApplicationEventTarget()` with `GetEventDispatcherTarget()`
returns `noErr` from both calls and then never fires. Both say
`GetEventDispatcherTarget()`, and must keep saying the same thing.

## A held modifier: `HeldModifierMonitor`

The window server accepts a hot key whose key *is* a modifier and then never fires it.
So Fn is watched instead: the flags change when it goes down and again when it comes up,
and those two are the press and the release.

**Two `NSEvent` monitors, because one is not enough.** A global monitor sees every app
except this one; a local monitor sees only this one. Uttrflow is a menu-bar app people
dictate *into other applications* from, so the global monitor is the one that matters —
but without the local one the shortcut would be dead in Uttrflow's own windows, which is
exactly where somebody tries it first after turning it on.

**Matching is by equality, not containment.** ⌃⌥ and ⌃⌥⌘ are different holds, and
matching a superset would mean a ⌃⌥ binding firing on the way to every ⌃⌥⌘ shortcut.

**This cannot suppress what macOS does with Fn.** An `NSEvent` monitor observes; it
cannot consume. If the Mac is set to show the emoji picker or start Apple's own
dictation on Fn, that still happens and both fire alongside this. The setting is in
System Settings → Keyboard → "Press 🌐 to", and the honest thing is to say so where the
shortcut is chosen rather than let it look like a bug.

## Neither is trusted to deliver the release

Both reconcile against the real key state every 250 ms. See `Docs/stuck-recording.md`.

## What is testable

Almost none of either file: what is left once a shortcut has been translated is a
registration with the window server. Both are excluded from the coverage gate, and every
decision they make lives in `CarbonHotkey` and `HeldModifierEdge`, which are covered.

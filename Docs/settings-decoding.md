# Settings: why decoding is forgiving, field by field

`Settings` (`Sources/UttrflowSettings/SettingsStore.swift`) is every choice the user has made, as
one value. `UserDefaultsSettingsStore` (`Sources/UttrflowSettings/UserDefaultsSettingsStore.swift`)
keeps it as one JSON blob under one `UserDefaults` key, `com.uttrflow.settings.v1`, so a save is
whole and needs no migration step. What that costs is decoding, and `Settings.init(from:)` pays it
deliberately: one unreadable value costs the user that value and nothing else.

## One value rather than a scattering of keys

A screen can be handed the whole configuration, compare it, and write it back in a single step, so
a half-applied change is not representable. Nothing in it leaves the Mac. The key is versioned so
that a shape too different to read field by field can live beside this one.

`load()` answers `Settings.default` when the blob is absent or is not a JSON object. At launch,
`pinDefaults(onboarded:)` saves the first settings over a missing or unreadable blob, so a later
change to a default moves nobody who already has one: an install that finished onboarding on an
earlier build gets `Settings.earlierInstall` (⌥Space for dictation, transcripts kept for a week),
and a new one gets `Settings.default`.

## Synthesised decoding is all-or-nothing, and that is the wrong trade

With synthesised decoding, one field a newer build added, or one a hand-edited preferences file
mangled, and the user loses every other choice they ever made. Settings are worth less than the
confidence that they survive, so a field that cannot be read is treated as the field the user
never changed: each one is read with `try? decodeIfPresent` and falls back to the same field of
`Settings.default`.

The engine, profile and suggestion groups (`EngineConfiguration`, `UserProfile`,
`SuggestionPreferences`) follow the same rule for their own fields. Within their arrays and
app-keyed dictionaries, `ReadableSetting` (`Sources/UttrflowCore/Support/ReadableSetting.swift`)
drops only an element that cannot be decoded, preserving the readable choices and their order. A
missing or unreadable collection, or one whose every element is unreadable, uses its field
default (`KeyedDecodingContainer.readableElements`), so corruption never becomes a different
setting such as an empty language list; an explicitly empty collection stays
empty. `ShortcutSet` drops an unknown action or an unreadable binding the same way.

The same forgiveness runs the other way. A key this build has no case for, such as
`recordingRetentionDays`, is a key keyed decoding is never asked for, so a blob an older build left
behind still yields every choice that still means something. A dropped key is also a door left
open: a hostile value stored under one must not come back in through it.

## Absent, `null` and unreadable mean three things

The settings file written before shortcuts became a `ShortcutSet` held two fields, `hotkey` and
`clipboardHotkey` (`Settings.LegacyShortcutKeys`), which are read once so such a file still opens.
`clipboardHotkey` is optional because "no clipboard shortcut" is a position a user can hold: the
panel is still reachable from the menu bar. So it arrives in three ways that mean three things:

| On disk | Meaning | Result |
|---|---|---|
| key absent | never chosen | the default |
| `null` | chosen to have none | `nil`, honoured |
| present, unreadable | no preference this build can act on | the default |

`decodeIfPresent` answers the same `nil` for the first two, so a shortcut the user had switched
off would come back by itself on the next launch. `optionalValue(forKey:default:)` checks
`contains(key)` first, then decodes.

### The trap inside it

`try? decodeIfPresent(T.self, forKey: key)` flattens nested optionals. "It threw" and "it decoded
a `null`" collapse into the one `nil` the method exists to tell apart, silently, with the right
type and no warning. `optionalValue` catches the error by hand for that reason.

## Values that decode cleanly and are still unusable

| Field | Unusable value | Becomes |
|---|---|---|
| `transcriptRetentionDays` | zero or less | `Settings.defaultTranscriptRetentionDays`, which is `keepAlwaysDays` (keep until deleted) |
| `clipboardRetentionDays` | zero or less | `Settings.defaultRetentionDays` (7) |
| either retention | a finite period above `Settings.maximumFiniteRetentionDays` (365) | 365 |
| `handsFreeDoubleTapMilliseconds` | anything outside `handsFreeDoubleTapChoices` (450, 600, 800) | 450, via `validDoubleTapMilliseconds` |
| `handsFreeHoldMilliseconds` | anything outside `handsFreeHoldChoices` (200, 300, 500) | 200, via `validHoldMilliseconds` |
| any shortcut binding | one `HotkeyBinding.isDeliverable` refuses | dropped by `ShortcutSet.init` |

- **Retention.** Zero or less would wipe the user's history the instant the app launched, so a
  value that says so is treated as a corrupt one. Only a missing or unusable value takes the
  default; a period the user saved, 7 included, is kept as it is. Only transcripts accept the
  keep-always sentinel. See [`retention-clock.md`](retention-clock.md).
- **The dictation shortcut.** `{"keyCode": 49, "modifiers": []}` is a perfectly good
  `HotkeyBinding` and a shortcut that never fires. A file whose shortcut set binds nothing
  deliverable to Dictate is read as an earlier build's file: the legacy `hotkey` field if it is
  deliverable, otherwise ⌥Space (`HotkeyBinding.optionSpace`), with the other actions at their
  defaults. Dictation is the one action with no second way in, so it is never left unbound by a
  read.
- **The clipboard shortcut.** It has no such obligation, so an unusable one read from the legacy
  field resolves to nothing rather than to a key the user never chose and would meet by surprise
  in another app.
- **A modifier held on its own**, in either shape of file and for any action. Earlier builds let
  the user choose it, so it was a decision rather than corruption, and dropping it would leave the
  action with no shortcut and no explanation. `ShortcutSet.returnToDefault` gives the action its
  default back instead, unless another action already holds those keys, and the action is added to
  `shortcutsReturnedToDefault`. That set is stored like any other field, so the note outlasts the
  save that removed the binding and stays until the user sets that shortcut again. See
  [`core-hotkeys.md`](core-hotkeys.md).

## The clipboard-shortcut collision

Carbon accepts two registrations of one combination and then fires both, so a collision left in
place starts a dictation *and* opens the panel on one keypress. When a legacy file binds the
clipboard to the dictation shortcut, dictation keeps the key, because it is the one with no second
way in, and the clipboard shortcut resolves to nothing. In the current format `SettingsEditor`
refuses a shortcut another action already holds, naming that action.

That is also why the dictation shortcut is resolved before the clipboard one in
`Settings.shortcuts(from:default:)`: the clipboard shortcut is only valid relative to it.

Related: [`shortcuts.md`](shortcuts.md), [`core-settings-launch-at-login.md`](core-settings-launch-at-login.md).

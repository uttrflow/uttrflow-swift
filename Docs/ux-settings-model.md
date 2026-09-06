# The settings screen's model

Why the choices on the Settings and Style screens are shaped the way they are. The code is
`Sources/UttrflowUX/SettingsChoices.swift`, `SettingsPresenter.swift`, `SettingsEditor.swift`
and `SettingsReset.swift`.

## Outcomes, not engines

`SettingsTidyingLevel` and `SettingsTranscriptionQuality` are stated as outcomes — how much
help, how long a wait — never as a list of implementations. §16 of the design holds here as it
does on the floating button: the user chooses what they want, never which engine gives it to
them, so swapping an engine is never a change of screen.

## There is no "off" for tidying

The transformer preference order always ends in a floor that can handle anything, so something
always runs. Offering an "off" would promise a state the pipeline has no way to be in.

## One copy for the tidying row

`SettingsTidyingLevel.rowLabel` and `.rowExplanation` are held on the type because two screens
draw the row. When each screen held its own wording they disagreed about what Light does — one
said punctuation only, when Light does capitalisation and spacing too. A user comparing the two
screens would reasonably conclude the app has two settings.

## The preference order is normalised, not trusted

`SettingsEngines.normalised(_:)` enforces two rules rather than describing them:

- Kinds this build does not contain are dropped, so a configuration written by another build
  cannot select an engine that is not here.
- The floor (`TransformerKind.rules`) is appended last, always, so the pipeline cannot reach the
  end of the list with the text untouched. That dead end loses the user their words rather than
  merely tidying them badly. Rules can neither invent nor refuse, which is what makes it the
  only safe last entry.

## Retention offers only values that survive the round trip

The settings store treats a period of zero or less as corrupt and quietly replaces it, so a
screen offering one would show a choice, save it, and reopen showing something else.
`SettingsRetention.offeredDays` is therefore 1, 3, 7, 14, 30 and 90 days, and
`SettingsRetentionTests` proves each survives by putting it through `Settings` rather than by
restating the store's rule.

Transcripts are the only thing there is a period for: audio is never written to disk, so there
is nothing about a recording for the user to set.

## Languages are listed, not derived

`SettingsLanguage.offered` is written out rather than read from the speech profile, so a
language the user has never chosen still appears, unticked, to be chosen.

## Reading a choice back is exhaustive

`SettingsTranscriptionQuality.init(engine:)` switches over every engine rather than searching
with a fallback. A fallback would be a branch nothing could take, and it would silently mislabel
a newly added engine instead of refusing to compile until somebody said what it is for.

## The privacy copy, written once

`SettingsPresenter.privacyPromise`, `.recordingsPromise` and `.signingOutKeepsEverything` are
each written once and repeated verbatim by every screen that shows them. A promise the user
meets in three wordings is a promise they have to work out for themselves.

Each is worded to be exactly true rather than comfortable:

- The promise says audio is deleted the moment it becomes text and the transcript is the only
  thing there is a period for. It stops short of claiming Uttrflow never reaches the network —
  the speech model arrives over one — and it stops short of claiming there is no account. There
  is one. What is true, and what the sentence says, is that the text is not attached to it.
- `signingOutKeepsEverything` exists because a user who assumes signing out is a reset makes one
  of two mistakes: they sign out to clear their history and it is still there, or they avoid
  signing out on a shared Mac because they think it would erase their dictionary.

## Counts before destruction

Every destructive button on the screen states what it will take, counted, before it takes it.
"Forget 34 learned words, keeping 12 you added yourself" is a decision; "Are you sure?" is not.

- `forgetLearnedRow` names both halves of the trade, because the reason that level exists is
  that hand-added words survive it.
- `resetSentence` is built only from the parts that exist. With nothing saved, a reset really is
  only the preferences, and offering to remove "0 transcripts" both reads badly and misstates it.
- `counted(_:_:_:)` is the one place a number meets its noun, so "1 words" cannot appear.
- `.everything` is never greyed out: preferences are always there to put back, and a greyed
  reset strands the user who came here precisely to start again.

## The Fn shortcut warning

The dictation tab warns only when Fn is the shortcut, because it is the only key macOS has its
own plans for. Uttrflow watches Fn rather than registering it — nothing can register a modifier
— and watching cannot stop the emoji picker or Apple's own dictation opening on the same press.

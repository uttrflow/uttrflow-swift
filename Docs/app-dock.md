# Dock button: measurements and traps

What `Sources/Uttrflow/Dock/DockView.swift` and `DockPanelController.swift` are drawn to, and
the two things that are not obvious from the code.

## Forms and sizes

| Form | Size (points) | Notes |
| --- | --- | --- |
| Resting grip | 9 × 34 | Three dots drawn straight on the desktop; no slab, because a slab around nine points reads as a box somebody forgot to delete. Six points of invisible hoverable padding all round. |
| Hovered | orb 30 + hint 30 high | The orb keeps the grip's side so it stays under the pointer |
| Listening / working | 32 high | Identical footprint, so the panel cannot change shape at the moment the key is released |
| Quiet outcomes (inserted, nothing heard) | 26-point disc | A success needs no words: the text is already in the document |
| Copied, not typed | 28 high, 64 wide at rest | ⌘V at rest; the sentence and the Fix button under the pointer |
| Blocked | 262 × 40 | The only wide form, so after a run of discs it is unmistakably asking for something |

`noticeMaxWidth` (262) applies to the blocked form alone. A single width applied to every
form made the listening pill 286 points wide on every dictation, for a state it never entered.

## Meter

- Bars arrive at 20 Hz (`meterArrivalInterval` 0.05 s), the rate the controller polls the
  microphone. The tap hands over 4096 frames at a time, about twelve blocks a second, so
  polling faster only resamples the same number and polling much slower shows a meter that
  steps. The timer runs in `.common` mode, or a drag of the button to another corner freezes it.
- The row is redrawn on every display frame at a fractional offset from `lastArrival`, not on
  arrival: twenty sideways jumps a second reads as stepping rather than flowing.
- Meter width is fixed at 56 points; how many bars fit is a consequence of the width.
- `meterAmplitude` 0.9 keeps a loud syllable from touching the glass. `settledLevel` 0.18 is
  where the row settles when the microphone closes; zero reads as a broken panel.
- The working animation settles the row over 0.34 s and then carries a bump across it, once
  every 1.15 s, for as long as the work runs. It used to resolve instead — a 0.3 s spring
  folding the bars into a tick — on the reasoning that a loop is the animation of a wait with
  no end. The wait does have an end, but the animation reached it first: the tick landed
  0.98 s after the key came up whatever the pipeline was doing, so on any dictation longer
  than a second the panel said the words were in while they were still being transcribed. A
  tick is a claim about the words, and only ``DictationState/inserted`` may make it.

### Why the loud threshold is carried by opacity, not hue

The two teals cannot carry the threshold on their own. On a light desktop the pair is
`#067A87` against `#29C0B4` and separates at 2.24:1, which reads. On a dark desktop the
waveform teal lightens to `#00C3D0` and the pair collapses to 1.05:1 and inverts, because
the accent is then the fractionally darker of the two. So hue keeps its job and weight is
added beside it: quiet bars are drawn at `meterQuietOpacity` 0.62. It introduces no colour
the app does not already own and works on both grounds, because opacity depends on neither.

## The mark opening into a check

`MarkCheck` is one round-capped stroke: a short arm, a turn, a long arm. The mark and a
checkmark differ only in how wide the turn is and how far the arms are splayed, so the `u`
becomes a check by opening. Rotating the mark does not work, and it is the obvious thing to
try: the mark's arms are parallel, and a rotated pair of parallel arms is a hook, not a tick.
The turn radius goes 24 → 6 and its centre drops from y 55 to 64 on the mark's 100-unit grid;
the short arm swings to 44° and the long arm to −32°.

## Colours

- `dockAccent` `#128077` is capped at 29% lightness so white 13-point text clears 4.5:1 on it.
  The mark's own teal is lighter than that and never carries text.
- `dockWeightInk` is fixed, not `.primary`: the weight's disc is the same teal in both
  appearances, so ink that followed the appearance would vanish in one of them.
- The panel's own `hasShadow` is off: AppKit draws a shadow around a transparent panel's
  opaque content, and every form already carries the one the design asks for. Two shadows
  around a nine-point grip is what made the resting button look boxed.

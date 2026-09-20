# Dock button: measurements and traps

What `Sources/Uttrflow/Dock/DockView.swift` and `DockPanelController.swift` are drawn to, and
the two things that are not obvious from the code.

## Forms and sizes

| Form | Size (points) | Notes |
| --- | --- | --- |
| Resting grip | 9 × 34 | Three dots drawn straight on the desktop; no slab, because a slab around nine points reads as a box somebody forgot to delete. Six points of invisible hoverable padding all round. |
| Hovered | orb 30 + hint 30 high | The orb keeps the grip's side so it stays under the pointer |
| Listening / working | 32 high | Identical footprint, so the panel cannot change shape at the moment the key is released |
| Inserted | 26-point disc | A success needs no words: the text is already in the document |
| Nothing heard, too short | 28 high, words up to 200 wide | The struck level with its sentence, readable at rest; a too-short hold says to hold longer |
| Copied, not typed | 28 high | ⌘V and "Copied, not typed" at rest, kept up as long as a failure; the reason and the Fix button under the pointer |
| Blocked | 262 × 40 | The only wide form, so after a run of discs it is unmistakably asking for something |
| Speech model loading | 262 × 40 | The blocked form with an hourglass, in place of the resting grip for as long as the load runs. See `Docs/startup.md` |

`noticeMaxWidth` (262) applies to the blocked form alone. A single width applied to every
form made the listening pill 286 points wide on every dictation, for a state it never entered.

## Meter

- Bars arrive at 20 Hz (`meterArrivalInterval` 0.05 s), the rate the controller polls the
  microphone. The tap hands over 4096 frames at a time, about twelve blocks a second, so
  polling faster only resamples the same number and polling much slower shows a meter that
  steps. The timer runs in `.common` mode, or a drag of the button to another corner freezes it.
- The row is redrawn up to 60 times a second at a fractional offset from `lastArrival`, not on
  arrival: twenty sideways jumps a second reads as stepping rather than flowing. In Low Power
  Mode or at serious thermal pressure it drops to the 20 Hz data rate and accepts the step, per
  `MotionBudget`; see `Docs/performance.md`.
- Meter width is fixed at 56 points; how many bars fit is a consequence of the width.
- `meterAmplitude` 0.9 keeps a loud syllable from touching the glass. `settledLevel` 0.18 is
  where the row settles when the microphone closes; zero reads as a broken panel.
- Working is three dots walking left to right, in the meter's own 56 points so the pill keeps
  its width. It runs for as long as there is work left, which includes the wait for the
  application to take the words: transcribing, tidying and inserting are one wait to the
  person waiting, so they are one animation and one sentence. Under Reduce Motion the three
  dots hold still and fully lit, per `MotionBudget`.
- It used to resolve instead — 0.34 s settling the row the voice left behind, then a 0.3 s
  spring folding the bars into a tick — on the reasoning that a loop is the animation of a
  wait with no end. The wait does have an end, but the animation reached it first: the tick
  landed 0.98 s after the key came up whatever the pipeline was doing, so on any dictation
  longer than a second the panel said the words were in while they were still being
  transcribed. It was not even the right tick — an SF Symbols `checkmark`, where the finished
  state draws its own. A tick is a claim about the words, and only
  ``DictationState/inserted`` may make it.

### Why the loud threshold is carried by opacity, not hue

The two teals cannot carry the threshold on their own. On a light desktop the pair is
`#067A87` against `#29C0B4` and separates at 2.24:1, which reads. On a dark desktop the
waveform teal lightens to `#00C3D0` and the pair collapses to 1.05:1 and inverts, because
the accent is then the fractionally darker of the two. So hue keeps its job and weight is
added beside it: quiet bars are drawn at `meterQuietOpacity` 0.62. It introduces no colour
the app does not already own and works on both grounds, because opacity depends on neither.

## The tick is a tick

`Tick` is one round-capped stroke through three points on the mark's own 100-unit grid —
(20, 54), (42, 76), (82, 26) — drawn on over 0.26 s. The grid is what it keeps from the
identity: the stroke weight comes from `UttrflowMark.lineWidth(forHeight:)`, so it sits at
the same weight as everything around it.

It used to be the mark opening into a check: one stroke whose turn widened from radius 24 to
6 and whose arms splayed to 44° and −32°, on the reasoning that the `u` and a check differ
only by how far they open. Drawn at 14 points in a 26-point disc it did not read as a check.
The turn stays a turn at that size, so what arrives is a bowl — an upside-down `u` — and a
confirmation nobody reads as confirmation is not one. The identity is carried by the mark on
the pill a few points to its left; the tick's job is to be unmistakable.

## Colours

- `dockAccent` `#128077` is capped at 29% lightness so white 13-point text clears 4.5:1 on it.
  The mark's own teal is lighter than that and never carries text.
- The status colours are held to the same minimums on both desktops, measured with the WCAG
  formula against the glass over a light desktop (about `#EEEEEE`) and a dark one (about
  `#262626`), and checked by `DockContrastTests`:

  | Where | Colour | Against | Ratio | Needed |
  | --- | --- | --- | --- | --- |
  | Failure disc | `dockWarningFill` `#C25E00` | its white glyph | 4.29:1 | 3:1 |
  | Failure disc | `#C25E00` | light / dark glass | 3.70:1 / 3.53:1 | 3:1 |
  | Copied keycap text | `dockWarningInk` `#9A4E00` light, `#FFB05C` dark | light / dark glass | 5.23:1 / 8.37:1 | 4.5:1 |
  | Inserted tick | `dockSuccessInk` `#1F8A3A` light, `#34C759` dark | light / dark glass | 3.81:1 / 6.82:1 | 3:1 |

  The bright `dockWarning` `#FF8D28` and `dockSuccess` `#34C759` measure 2.31:1 under white
  and about 2:1 on light glass, so the dock never draws with them.
- `dockWeightInk` is fixed, not `.primary`: the weight's disc is the same teal in both
  appearances, so ink that followed the appearance would vanish in one of them.
- The panel's own `hasShadow` is off: AppKit draws a shadow around a transparent panel's
  opaque content, and every form already carries the one the design asks for. Two shadows
  around a nine-point grip is what made the resting button look boxed.

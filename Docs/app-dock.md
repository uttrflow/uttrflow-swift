# The floating button: forms, measurements and traps

The floating button is the small panel at the edge of the screen that starts a dictation, shows
it listening and working, and reports how it ended; it is the recorder itself, changing into its
listening form while a dictation runs, so one thing moves on screen rather than two. It is drawn
by `Sources/Uttrflow/Dock/DockView.swift` (sizes in `DockMetrics`), its speech-model setup forms
by `DockSetupView.swift` (`DockSetupMetrics`), its window by `DockPanelController.swift`, and what
it says is decided by `DictationPresenter` in `Sources/UttrflowPipeline/`. Related:
[`startup.md`](startup.md) for the speech-model forms' words,
[`app-quick-panel.md`](app-quick-panel.md#after-the-panel-has-closed) for what it reports after a
clipboard paste.

## Forms and sizes

| Form | Size (points) | Constant | Notes |
| --- | --- | --- | --- |
| Resting grip | 9 × 34 | `gripWidth`, `gripHeight` | Three 3-point dots drawn straight on the desktop; no slab, because a slab around nine points reads as a box somebody forgot to delete. |
| Hit padding | 6 all round | `gripHitPadding` | Invisible but hoverable, around every form; a nine-point strip is hard to point at. |
| Hovered | orb 30, hint 30 high | `orbSize`, `hintHeight` | The orb keeps the grip's side so it stays under the pointer. A hint saying why the shortcut cannot be heard wraps within 240 (`unheardWidth`). |
| Listening | 32 high | `listeningHeight` | The meter and a running clock on tinted glass, the clock on the anchored edge; no mark. |
| Working | 40-point orb | `workingOrbSize` | Three bars rising and settling in turn, for as long as there is work left. |
| Inserted | 26-point disc | `badgeSize` | A teal return arrow inside the ring; a success needs no words, the text is already in the document. |
| Nothing heard, too short | at least 28 high, words up to 200 wide | `clipboardHeight`, `quietTextMaxWidth` | The struck level with its sentence, readable at rest, wrapping to two lines; a too-short hold says to hold longer. |
| Copied, not typed | 28 high | `clipboardHeight` | ⌘V and "Copied, not typed" at rest, kept up as long as a failure; under the pointer, a 200-wide pill (`blockedWidth`) saying "Typing is blocked — paste it" with **Fix**. |
| Microphone off | pill | `DockSetupMetrics.warningRadius` | The warning disc, "Microphone is off" and a trailing **Fix**; the full sentence under the pointer. |
| Every other failure | 300 wide, at least 40 high | `noticeMaxWidth`, `noticeHeight` | The only wide form, so after a run of discs it is unmistakably asking for something. |
| Speech model downloading or loading | 34 high | `DockSetupMetrics.capsuleHeight` | A ring filled to the download or the load estimate (a spinner before the estimate) beside the words, in place of the resting grip. |
| Speech model failed / missing | 264 / 250 wide | `failedWidth`, `missingWidth` | The warning with its one button. |

`noticeMaxWidth` (300) applies to the wide form alone, so the listening pill is never widened for
a state it never enters.

Every form but the resting grip sits on the same glass: the system material under
`BrandPalette.Redesign.dockGlass` (`100D1E` at 72% when dark, white at 90% when light), with a
one-point `dockGlassEdge` hairline. Words and glyphs on it are `textStrong`, white when dark and
ink when light.

The wide form's message wraps to at most `noticeMaxLines` (3) lines and the form grows to hold it;
the recovery button sits under the words rather than beside them, so it never takes width the
message needs. At one line with no button the form is a 40-point capsule. `DockNoticeTextTests`
measures every failure message at the view's font and wrap width and fails when one would need a
fourth line, and the whole notice is on the pointer as a tooltip.

## Meter

| Value | Constant | Why |
| --- | --- | --- |
| 20 Hz | `meterArrivalInterval` 0.05 s, `DockPanelController.meteringInterval` | the rate the controller polls the microphone |
| 100 points | `meterWidth` | fixed; how many bars fit follows from it, and `DockBars.capacity` (28) covers it |
| 20% | `meterFade` | the first and last fifth fade up from nothing, so bars enter and leave softly |
| 0.9 | `meterAmplitude` | keeps a loud syllable from touching the glass |
| 0.62 | `meterQuietOpacity` | quiet bars; loud ones (above `DockBars.accentThreshold`, 0.5) are full strength |

- The tap hands over 4096 frames at a time, about twelve blocks a second, so polling faster only
  resamples the same number and polling much slower shows a meter that steps. The timer runs in
  `.common` run-loop mode, or a drag of the button to another corner freezes it.
- The row is redrawn up to 60 times a second at a fractional offset from `lastArrival`, not on
  arrival: twenty sideways jumps a second reads as stepping rather than flowing. In Low Power Mode
  or at serious thermal pressure it drops to the 20 Hz data rate and accepts the step, per
  `MotionBudget`; see [`performance.md`](performance.md).
- The clock beside it reads the time since the key went down as `0:04`, advanced by the meter's
  own 20 Hz arrivals so it adds no timer of its own. Once the cap is near the countdown takes its
  place, because the time left matters more than the time spent.

### The loud threshold is carried by opacity

The meter is one colour, `dockMeter`: white on the dark glass and dictation teal `#128077` on the
light. Quiet bars are drawn at 0.62 opacity and loud ones at full strength. Two teals cannot carry
the threshold by hue (a pair collapses to about 1:1 on a dark desktop), and opacity works on both
grounds because it depends on neither.

## Working

Working is a 40-point glass orb whose three bars rise to full height and settle to 40%
(`workingRest`) in turn, each `workingStagger` (0.15 s) behind the one to its left, over
`workingCycle` (one second). It runs for as long as there is work left, which includes the wait
for the application to take the words: transcribing, tidying and inserting are one wait to the
person waiting, so they are one animation. Under Reduce Motion the bars hold still at full
height, per `MotionBudget`.

The line is "Tidying up…" for every stage until the wait passes `WaitLine.stageAfter` (10 s, the
current p95 wait for a dictation of about 10 s in [performance.md](performance.md#latency-budget-per-stage)).
It then names the true stage, "Transcribing…", "Tidying…" or "Waiting for <app>…" with the app the
words are going to, and past `WaitLine.secondsAfter` (20 s) adds the seconds waited beneath it.
VoiceOver hears the stage once, at the first change. `WaitLineTests` holds these.

It does not resolve into a tick on a timer, because a timed tick lands while the words may still
be transcribing and says they are in when they are not. A tick is a claim about the words, and
only `DictationState.inserted` may make it.

## Inserted is a return arrow

`InsertedMark` draws `ReturnArrow`, a 13-point return key on a 24-unit grid (`returnGlyphSize`,
`grid`): a stroke down the right side turning left into an arrowhead, drawn on over 0.26 s in
dictation teal `dictationAccent` inside the 26-point disc. It names the key that puts words in,
which is the thing that just happened, in the teal the rest of the design uses rather than a green
success colour.

## Colours

- `dockAccent` is `Teal.deep` `#128077`, at 29% lightness so white 13-point text clears 4.5:1 on
  it (4.79:1). The mark's own teal is lighter than that and never carries text.
- The status colours are held to the same minimums on both desktops, measured with the WCAG
  formula against the glass over a light desktop (`#EEEEEE`) and a dark one (`#262626`), and
  checked by `DockContrastTests`:

  | Where | Colour | Against | Ratio | Needed |
  | --- | --- | --- | --- | --- |
  | Failure disc | `dockWarningFill` (`Semantic.warningFill`) `#C25E00` | its white glyph | 4.29:1 | 3:1 |
  | Failure disc | `#C25E00` | light / dark glass | 3.70:1 / 3.53:1 | 3:1 |
  | Copied keycap text | `dockWarningInk` (`Semantic.cautionInk`) `#943C00` light, `#FFB05C` dark | keycap `#CDCDCD` / `#444444` (14% over light / dark glass) | 4.55:1 / 5.39:1 | 4.5:1 |
  | Inserted arrow | `dictationAccent` `#128077` light, `#5FE0D3` dark | light / dark glass | 4.13:1 / 9.43:1 | 3:1 |

  The bright `dockWarning` `#FF8D28` and `dockSuccess` `#34C759` measure 2.31:1 under white and
  about 2:1 on light glass, so the floating button never draws with them.
- The panel's own `hasShadow` is off: AppKit draws a shadow around a transparent panel's opaque
  content, and every form already carries the one the design asks for. Two shadows around a
  nine-point grip make the resting button look boxed.

## What the menu bar shows for each dictation state

The floating button can be switched off, and is hidden while nobody is signed in, so the menu
bar has to carry every dictation state on its own. `FailurePresenter.placement` decides a
failure's surface from its severity and from whether the button is shown: a blocking failure,
or any failure while the button is not shown, takes the menu bar's attention form for the same
`AppDelegate.linger` the button would have used, then clears with the state. The VoiceOver
label is `MenuBarPresenter.spokenForm` of the status line, so it follows that column.
`MenuBarSurfaceTableTests` fails when a `DictationState` has no row here or when a row's state
shows the resting icon or status line.

| State | Icon, button shown | Icon, button off | Status line |
| --- | --- | --- | --- |
| `idle` | the mark | the mark | Ready |
| `recording` | `mic.fill` | `mic.fill` | Listening… |
| `transcribing` | `sparkles` | `sparkles` | Tidying up… |
| `tidying` | `sparkles` | `sparkles` | Tidying up… |
| `inserting` | `sparkles` | `sparkles` | Tidying up… |
| `inserted`, confirmed | `checkmark` | `checkmark` | Inserted |
| `inserted`, unconfirmed | `questionmark.circle` | `questionmark.circle` | Inserted — not confirmed |
| `inserted`, partial | `exclamationmark.circle` | `exclamationmark.circle` | the missed-speech line |
| `inserted`, copied | `doc.on.clipboard` | `doc.on.clipboard` | Copied — press ⌘V |
| `failed`, informational | `info.circle` | `exclamationmark.triangle.fill`, tinted | the notice's headline |
| `failed`, recoverable or degraded | `xmark.circle` | `exclamationmark.triangle.fill`, tinted | the notice's headline |
| `failed`, blocking | `exclamationmark.triangle.fill`, tinted | `exclamationmark.triangle.fill`, tinted | the notice's headline |

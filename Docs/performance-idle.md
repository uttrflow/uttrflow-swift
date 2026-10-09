# What Uttrflow costs while nobody is using it

Uttrflow is a login item and opens its window at launch, so "running, window open, nobody touching
it" is the state it spends most of its life in. This page covers what the app spends in that state
and on the work that arrives without warning: the home page's animation
(`Sources/Uttrflow/Main/`), motion under the system's energy settings
(`Sources/Uttrflow/Motion/MotionBudget.swift`), the menu bar popover, the clipboard poll and
classifier (`Sources/UttrflowClipboard/`), and the formatter diff (`TextDiff`). The budget these
are held to is in [`performance.md`](performance.md).

## The idle cost

Measured on the signed bundle from outside, by the process's own cumulative processor time over a
minute, on a quiet machine:

| state | processor |
|---|---|
| window covered by another app | 0.08% of a core |
| app hidden with ⌘H | 0.10% |
| window partly visible behind another app | 0.02% |
| minimised | 0.18% |
| resident memory, all states | about 305–309 MB |

The rest of this page is why those numbers are small and what keeps them small.

## The home page's demonstration

`ClipboardDemonstration` draws the paste on the home page with a `TimelineView`. A redraw re-runs
the layout of the card and of the window around it, and a `TimelineView` asks to be redrawn whether
or not anybody can see it; SwiftUI does not stop it. Left to the display's rate it cost a whole
core — 97.5% with the window frontmost, 98.2% with the app hidden by ⌘H — and `sample` put about
three quarters of main-thread samples in `NSHostingView.layout()` under the card. Two rules keep it
cheap.

**It moves only where it can be seen.** `WindowAttention` animates when the view is shown, its
window is key, the application is active and not hidden, the window is on screen, and the card
itself is visible: the part of the card inside its scroll view's bounds (`onGeometryChange` with
`bounds(of: .scrollView)`), reduced by `WindowAttention.uncoveredFrame`, must overlap a display by
an area (`WindowAttention.isVisible`). `WindowVisibility.swift` re-evaluates the rule on the
occlusion, key-window, active, hidden, move, resize and screen notices, and on a scroll through a
reference held in `@State`, without re-evaluating the card's body. Anywhere else the card rests on
`ClipboardDemonstrationPhase.resting`, the panel open with the address row chosen, so a glance at
a background window still shows what the feature is.

`NSWindow.occlusionState` alone is not enough: AppKit keeps `.visible` while any sliver of the
window is on screen, and the card sits below the fold of Home's `ScrollView` at the default window
size, where it stays in the hierarchy and keeps its clock.

**Its clock wakes when the drawing changes.** `ClipboardDemonstrationMoments` is the card's
`TimelineSchedule`. Of the eight-second loop only the panel rising (0.9 s) and going (0.6 s) move
continuously, at `MotionBudget.demonstrationFrameInterval` (1/30 s); the typed line wakes once per
character; everything else is a still state that wakes once, at its boundary.
`ClipboardDemonstrationMomentsTests` counts the wakes headlessly, with the 39-character address
line, and checks the instant drawn matches the clock everywhere outside the moving stretches:

| schedule | wakes per loop | while the panel rises | while it goes |
|---|---|---|---|
| every display frame, 120 Hz (not used) | 960 | 108 | 72 |
| on change, motion at 30 Hz | 91 | 27 | 18 |
| still, under any budget that stops it | 1 | 0 | 0 |

Measured on a Release build with the window key and frontmost (raised through System Events,
processor time counted only across 50 ms steps where it stayed frontmost, captures at 1.2, 1.5
and 1.8 s into the loop confirming the card moved), with motion at 120 Hz on change:

| state, window key and frontmost | over whole loops | across the panel's rise |
|---|---|---|
| card on screen | 11.9% | 40.6–41.0% |
| card scrolled fully out of view | 1.9% | 0.9–3.2% |
| window shortened until the scroll view hides the card | — | 1.6% |
| card past the bottom of the display | — | 1.1% |

The 30 Hz cap cuts wakes by 60% against that schedule, and the cost while animating was found
roughly proportional to wakes; the processor figure at 30 Hz has not been taken.

### Approaches not used

- **A frame-rate cap on the old per-frame clock.** Measured window frontmost: none 97.5%, 60 a
  second 91.7%, 10 a second 26.4%. Sixty buys 6%; ten buys three quarters and is visibly steppy.
  Waking only on change is the lever instead.
- **Hoisting `ViewThatFits` above the clock.** A `TimelineView` inside a `ViewThatFits` candidate
  is never driven, even in the candidate that is drawn: the card renders once and never moves, with
  no warning. The arrangement is chosen instead by
  `ClipboardDemonstrationMetrics.arrangement(forOfferedWidth:)` from a width measured once by
  `onGeometryChange`.
- **`NSView.visibleRect` for the card's visibility.** It does not see SwiftUI's scroll clipping: a
  scrolled-out card still cost 31.4% across the rise.
- **The document and panel in their own `NSHostingView`** (14.5%), **the rise and fade as SwiftUI
  animations** (12.9%) and **a constant shadow with only the opacity animated** (13.8%), each
  against 12.6–18.8% for the schedule without per-character typing. None is distinguishable from
  noise of about ±5 points.

### Measuring it without fooling yourself

A frozen card and a cheap card read the same from outside, so confirm it is animating before
believing a figure: `sample` the process and count `ClipboardDemonstration` frames (27 in three
seconds on screen, 0 where it is meant to rest). The card is absent or still, and therefore free,
when:

- **the window is not frontmost** — a shell command that steals focus is enough; check the
  frontmost application at both ends of the measurement;
- **a permission is missing** — `HomePresentation` hides the demonstration while
  `MainPresenter.obstruction` finds one, and a rebuilt bundle has a new signature and no
  Accessibility grant;
- **the card is below the fold** — it is the last thing in Home's `ScrollView`.

## Motion under Reduce Motion, Low Power Mode and thermal pressure

`MotionBudget` answers, as a pure value from Reduce Motion and `EnergyConditions` (Low Power Mode
and thermal state), how much decorative motion the Mac allows. `MotionBudgetTests` covers it.

| | demonstration | working bars and level meter | dock frame cap |
|---|---|---|---|
| nothing asked | moves, 30 frames a second while the panel moves | move | 60 a second (`fullDockFrameInterval`) |
| Reduce Motion | still frame | still | 60 a second |
| Low Power Mode | still frame | move | 20 a second, the meter's data rate (`reducedDockFrameInterval`) |
| serious or critical thermal state | still frame | move | 20 a second |

`WindowAttention` carries the budget, and `WindowVisibility.swift` re-reads it on
`NSProcessInfoPowerStateDidChange`, `ProcessInfo.thermalStateDidChangeNotification` and
`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (`MotionBudget.changeNotices`). The
dock reads `MotionBudgetObserver.shared`, which re-reads on the same notices.

## The menu bar popover's loading bar

The popover's unknown-length bar is a `CAGradientLayer` slid by a `CABasicAnimation`
(`MenuBarSlidingRun.swift`), drawn above the glass through an anchor preference, so a frame costs
the app's main thread nothing and the glass, which carries a `blur(40)` aurora and a
`shadow(radius: 20)`, is never redrawn for it. It moves only while `MotionBudgetObserver` allows
and while it is in a window; the controller empties the panel on close, which removes the layer.

A SwiftUI `repeatForever` offset inside the glass is not used: it ran SwiftUI's animation pass on
the main thread every display frame and invalidated the glass. Measured in a Debug test build,
main-thread time over three-second samples on a heavily loaded machine:

| | main thread, share of a core |
|---|---|
| SwiftUI `repeatForever` inside the glass (10 samples) | 14–97%, median 66% |
| Core Animation run above the glass (8 samples) | 0.0% in every sample |
| no bar, for comparison | 0.0% |

Offscreen renders match within 1/255 except on the bar's rounded ends (at most 7/255).
`ImageRenderer` cannot draw a platform view, so an offscreen render of the loading state shows
SwiftUI's placeholder where the run is; the live popover does not.

## The clipboard poll

macOS posts no notification for a copy, so `PasteboardWatcher` reads the change count on a timer,
from login, for as long as the app runs: `pollInterval` is 500 ms and the tolerance a fifth of it
(`tolerance(for:)`), at utility priority. It is the largest steady wakeup source in an idle app,
and its cost is wakeups rather than processor time. A stand-alone loop doing exactly this, its own
wakeups read with `proc_pid_rusage` over 30 s:

| cadence | wakeups a second | processor |
|---|---|---|
| 200 ms, no tolerance | 4.8 | ≈ 0.04% of a core |
| 500 ms, 100 ms tolerance (shipped) | 1.7 | ≈ 0.02% |
| 1 s, 200 ms tolerance | 1.0 | ≈ 0.01% |

⌘C followed by the panel shortcut is one hand movement, so `toggleQuickPanel` calls
`PasteboardWatcher.catchUp` before it reads the clips, and a copy made a moment before is in the
panel whatever the cadence. What 500 ms gives up: the clipboard holds only its latest contents, so
two copies inside one interval keep only the second. The measured 1.7 wakeups a second is the
steady idle cost; it remains the cadence while no recent user copy is being recorded.

After the watcher records a user copy, it polls at 100 ms with a 20 ms tolerance. Each newly
recorded copy restarts a four-second quiet window; when that window expires, the watcher returns to
the 500 ms idle cadence. This window spans the measured four-second sequence of 20 copies at
200 ms intervals without raising the steady idle wakeup rate. In the fake-source run-loop test, the
original 500 ms-only cadence recorded 9 of 20 copies; the adaptive cadence must record at least 17.
That test also checks for the faster polling gaps during the burst and a return to a 500 ms-scale
gap after the quiet window. It measures the watcher schedule and captured copies, not whole-process
wakeups on a Mac; the 1.7 wakeups-per-second figure above remains the separate process measurement.

## Classifying a copy

Every text copy up to the 2 MB clip bound goes through `ClipKindDetector.kind(of:)`. The watcher
calls it on its own actor, inside the utility-priority task `AppDelegate` starts, never on the main
thread; opening the panel awaits `catchUp`, which classifies a pending copy while the panel waits.
A clip typed into the panel or kept from a dictation goes through `ClipKindDetector.classify(_:)`,
a detached utility task awaited through a continuation so the wait does not raise its priority.

- **The secret scan reads every byte.** The vendor-key and card-number patterns are handed a
  window at each literal prefix or long digit run rather than the whole clip
  ([`clipboard-secrets.md`](clipboard-secrets.md)).
- **The code-shape signals read a sample of a large clip** (`CodeSample` in `CodeShapes.swift`).
  Up to `budget` (64,000 bytes) a clip is read whole. Above it, the first and last `edge` (16,000
  bytes) and `windows` (16) windows of `window` (2,000 bytes) spread evenly between, each trimmed
  to whole lines where it holds a line break. The whole-clip checks that cost nothing — a shebang,
  an import on the first line, a one-line shell command — still see the whole clip.
- **Two signals end the count**, cheapest first, and a pattern is skipped when the bytes lack a
  literal it cannot match without.

Processor time for one `kind(of:)` call, Release, one core, on the Mac named in
[`performance.md`](performance.md); wall clock matched processor time within a few percent:

| input | 16 KB | 256 KB | 1 MB | 2 MB |
|---|---|---|---|---|
| code | 0.000 s | 0.002 s | 0.007 s | 0.013 s |
| prose | 0.002 s | 0.006 s | 0.012 s | 0.020 s |
| minified JavaScript, one line | 0.001 s | 0.004 s | 0.016 s | 0.029 s |
| base64, 76 columns | 0.007 s | 0.031 s | 0.020 s | 0.057 s |
| base64, one line | 0.000 s | 0.002 s | 0.015 s | 0.030 s |
| logs | 0.005 s | 0.026 s | 0.052 s | 0.085 s |
| CSV | 0.004 s | 0.020 s | 0.024 s | 0.029 s |
| hex dump | 0.014 s | 0.060 s | 0.065 s | 0.014 s |
| hex, one line | 0.000 s | 0.002 s | 0.007 s | 0.013 s |

Reading every clip whole with every pattern is not used: it took 2.1–5.5 s for a 2 MB clip, most of
it in the vendor-key pattern, the card-number pattern and ten code-shape patterns that went on
counting after two signals were found.

`ClipClassifyScalingTests` counts the bytes handed to the code-shape signals and the characters
handed to the two secret patterns, so the bound is a count rather than a clock: the first stays at
the sample's size for 256 KB, 1 MB and 2 MB clips, and the second is zero for a clip with no prefix
and no long digit run.

**What sampling gives up, measured** against the whole-clip classifier as oracle over 50,795 clips
(460 MB) — random strings, planted secrets, realistic clips of every kind up to 2 MB, and every
planted shape at the start, middle and end of 256 KB clips:

- **The secret verdict differed on none**, at any size; nothing about secrets is sampled.
- **The kind differed on 32, all above 64 KB, all code becoming text**: base64 in 76-column lines
  that the whole-clip reading called code because somewhere a line began `//` and another held
  `++`, and prose, logs, CSV or a hex dump with one to three lines of code between the sampled
  windows.
- **Below 64 KB nothing differed.** `ClipKindOracleTests` runs 50,000 random, planted and realistic
  clips below it against the oracle on every `make verify`.

## Showing what a formatter changed

The formatting sheet diffs a clip against the formatter's output once per presentation, on the main
actor, and a kept clip may be 2 MB. `TextDiff` finds the fewest changed lines with an edit-distance
search over layers of furthest-reaching points, the O(n × d) algorithm, whose memory grows with the
changes rather than with the product of the two lengths. It then walks from the top choosing at
each change exactly what the full table would: equal lines first, and a removal before an addition
whenever both are shortest. The walk needs the layers deepest first, so every 32nd layer (`stride`)
is kept and each stretch is rebuilt from it — about one more pass, and about d² / 64 integers held,
2 MB at the change limit.

| limit | value | what happens past it |
|---|---|---|
| `TextDiff.lineLimit` | 20,000 lines | refused up front; the sheet states both line counts |
| `TextDiff.byteLimit` | 1,000,000 bytes | refused up front |
| `TextDiff.changeLimit` | 4,000 changed lines | the search stops; the sheet states both line counts |

A line ends at LF, CRLF or CR, counted the same way by the split and the byte count, and a CR or
CRLF ending belongs to the line after it for comparison, so a change of endings shows as a change.

Release, best single run, peak footprint from `/usr/bin/time -l`. "Every line" indents all lines,
"one in fifty" every fiftieth; a full table, which `TextDiff` does not use, is the comparison:

| lines | shape | full table | `TextDiff` |
|---|---|---|---|
| 1,000 | every line | 12 ms, 10.6 MB | 13 ms, 6.9 MB |
| 1,999 | every line, 3,998 changes | 42 ms, 36 MB | 53 ms, 12.7 MB |
| 5,000 | every line | 1.16 s, 308 MB | 34 ms, 6.9 MB, too large |
| 20,000 | every line | 9.9 s, 3.9 GB | 38 ms, 14 MB, too large |
| 5,000 | one in fifty | 231 ms, 341 MB | 3.0 ms, 3.5 MB |
| 20,000 | one in fifty | 7.3 s, 4.1 GB | 14 ms, 10 MB |

`TextDiffScalingTests` counts steps through `TextDiff.tally` rather than timing, and compares the
diff with the full table on 20,000 random small pairs.

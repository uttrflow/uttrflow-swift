# Design: where each visual decision lives

The shipped Swift UI is the design. This page says which file holds each decision, what the gate
checks, and what a reviewer checks by hand. It holds no values: the values are in the files it
names. `make design-audit` runs every check below and is a prerequisite of `make verify`.

## Principles

1. **Production wins.** The Swift views are the only picture of the app: 0 generated canvases
   are kept beside them. A mockup or doc that disagrees with the Swift code is wrong, and is
   fixed to match the code, never the reverse in the same change.
2. **One home per decision.** A colour, typeface or metric is declared once and named everywhere
   else; two views drawing the same thing point at the same member.
3. **Native first.** A macOS control, system font, SF Symbol or system material is used as the
   platform draws it unless the product has a recorded reason to differ.
4. **Not a redesign.** A change that alters what a person sees says so in its pull request, with
   before and after screenshots in light, dark and Increase Contrast.

## Authority

| Concern | Canonical source | Reached through | Enforced by |
|---|---|---|---|
| Colour | `Sources/Uttrflow/Brand/BrandPalette.swift` | `Sources/Uttrflow/Main/RedesignColors.swift`, `OrbitPalette.swift`, `QuickPanelGlass.swift`, `MenuBarGlass.swift`, `Color` aliases | `design_source_audit.py`; palette and contrast tests in `Tests/UttrflowTests` |
| Typeface | `Sources/Uttrflow/Brand/BrandFont.swift`: `display` (Outfit) and `wordmark` (EB Garamond); every other text is the system font | `BrandFont.display`, `BrandFont.wordmark`, `.font(.system…)` | `design_source_audit.py`; `BrandFontTests` |
| Spacing, radii, sizes | the surface's own metrics enum: `MainMetrics`, `PageMetrics`, `SidebarMetrics`, `SettingsMetrics`, `QuickPanelMetrics`, `DockMetrics`, `DockSetupMetrics`, `OnboardingMetrics`, `ClipboardDemonstrationMetrics` | the enum's members | review |
| Control styles | `PageButtonStyle`, `MainPrimaryButtonStyle`, `MainSecondaryButtonStyle`, `HomeQuietButtonStyle`, `SettingsSwitchStyle`, `SettingsButtonStyle`, `OnboardingPressStyle` | `.buttonStyle`, `.toggleStyle` | review |
| Motion | `Sources/Uttrflow/Motion/MotionBudget.swift` (Reduce Motion, Low Power Mode, thermal state) | `MotionBudget` | `MotionBudgetTests` |
| Mark and icon | `Sources/Uttrflow/Brand/UttrflowMark.swift`, `UttrflowMarkView.swift`; `Resources/AppIcon/ICON.md` for the app icon | SF Symbols for every other glyph | review |
| Sidebar, chrome, page captions | `SidebarPresenter.order`, `MainWindowView.swift`, each page's presenter in `Sources/UttrflowUX` | the views | review |
| Token reference | `BrandPalette.Redesign` | `Docs/redesign-tokens.md` quotes it | `design_source_audit.py` |

A doc that quotes a value loses to the file it quotes. How colours resolve per appearance is in
[`app-main-window.md`](../app-main-window.md#colours).

## Rules

| Rule | Check | Pass |
|---|---|---|
| A colour is a `BrandPalette` role: 0 colours built from literal channels, hex helpers, colour literals or asset colours, and 0 colour-shaped hex literals in `Sources/Uttrflow` or `Sources/UttrflowUX`, outside `BrandPalette.swift` | `python3 Scripts/design_source_audit.py` | exits 0 |
| 0 hued system colours (`NSColor.systemRed`, `Color.orange`, `.fill(.green)`); white, black, clear and the system's semantic label and window colours are native and allowed | `python3 Scripts/design_source_audit.py` | exits 0 |
| A bundled typeface is reached only through `BrandFont`: 0 custom fonts or family names elsewhere | `python3 Scripts/design_source_audit.py` | exits 0 |
| 0 generated canvases: no `Design/*.dc.html`, `Design/_gen_*.py` or canvas manifest is tracked or on disk | `python3 Scripts/design_source_audit.py` | exits 0 |
| Text roles clear 4.5:1 and marks 3:1 on the shared `BrandPalette` surfaces, light and dark | `python3 Scripts/design_contrast_audit.py` | exits 0 |
| Every value in the `Docs/redesign-tokens.md` colour table equals its `BrandPalette.Redesign` role | `python3 Scripts/design_source_audit.py` | exits 0 |
| Production text tones clear 4.5:1 and marks 3:1 on their surfaces, in both appearances and Increase Contrast | `swift test --filter Contrast` | passes |
| `make verify` runs `make design-audit` | `make docs-audit` | exits 0 |

Every audit has a `--self-test` that passes a valid fixture, fails a prohibited one, passes an
allowed exception and fails when the structure it parses has gone; `make design-audit` runs it
first.

## Exceptions

An exception is an entry in `ALLOWED` in `Scripts/design_source_audit.py`, with the platform or
architecture reason. A stale entry fails the audit. 0 inline suppressions, 0 ignore files.

## Changing the design

1. **Reuse first.** Search `BrandPalette.swift`, the surface's metrics enum and the styles above
   before adding anything; extend an existing member before adding a new one. A new shared
   component is one whose identity and behaviour are the same in at least two places.
2. **Colour.** Add the role to `BrandPalette.swift` with a semantic name and both appearances (and
   a high-contrast pair where text sits on it), add its contrast test, then name it from the view.
   0 new colour files.
3. **Typeface.** A new family is a new `BrandFont` member with its licence in
   `Sources/Uttrflow/Resources/Fonts/`.
4. **Native values.** Literal geometry is allowed where it is macOS API geometry (an `NSWindow`
   frame, a status-item size) or an algorithmic constant; a design decision used in two places
   goes in the surface's metrics enum.
5. **Accessibility.** Every new colour pair is checked in light, dark and Increase Contrast; every
   animation goes through `MotionBudget`; every control has an accessibility label
   (`make accessibility-controls`).
6. **No canvases.** Change the Swift view; 0 generated pictures of a screen are committed beside it.
7. Run `make design-audit`, then `make verify`.

## Review-only

The reviewer counts, in the diff:

- 0 new metrics, style or component types duplicating one listed under Authority;
- 0 literal spacing, radius or size values repeated in two views of one surface instead of a
  metrics member;
- 0 visible changes without before and after screenshots.

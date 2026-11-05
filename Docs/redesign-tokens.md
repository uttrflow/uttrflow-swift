# Redesign tokens

`BrandPalette.Redesign` in `Sources/Uttrflow/Brand/BrandPalette.swift` holds the colours of the
app's current design: the main window's pages and Home, the menu-bar popover, the floating button
and the clipboard panel draw from it (through `RedesignColors.swift`, `QuickPanelGlass.swift`,
`MenuBarGlass.swift` and the floating button's views). The headings' typeface is registered by
`BrandFont`. How colours are organised and resolved across the whole palette is in
[`app-main-window.md`](app-main-window.md#colours).

A `BrandTone` is a solid dark/light pair, optionally with a high-contrast pair for Increase
Contrast; a `BrandLayer` is a tone drawn at an opacity per appearance, for translucent films,
hairlines, glass and secondary text.

## Colours

| Token | Dark | Light |
|---|---|---|
| `pageGround` | `#0B0C10` | `#F2F1EC` |
| `windowGround` | `#0C0D14` | `#F2F1EC` |
| `cardFill` | white at 3.5% | `#FFFFFF` |
| `cardEdge` | white at 8% | none |
| `hairline` | white at 8% | `#DEDCD4` |
| `sidebarIsland` | `#100F1C` at 92% | `#12101E` (stays dark) |
| `islandQuiet` | white at 55% | white at 55% (on the dark island) |
| `textStrong` | `#FFFFFF` | `#101316` |
| `textSoft` | white at 72% | `#5C6866` |
| `textQuiet` | white at 55% | `#5C6866` |
| `textFaint` | white at 55% | `#101316` at 66% |
| `dictationAccent` | `#5FE0D3` | `#128077` |
| `suggestionAccent` | `#C49BF5` | `#7A4FC4` |
| `clipboardAccent` | `#FFB05C` | `#B5650F` |
| `clipboardInk` | `#FFB05C` | `Semantic.warningInk` light |
| `infoAccent` | `#6BB4F5` | `#1E6FC4` |
| `neutralAccent` | `#A7ACB8` | `#5E6470` |
| `mintAccent` | `#8FF5EC` | `#128077` |
| `dictationDeep` | `#29C0B4` | `#128077` |
| `badgeInk` | `#AFF3EC` | `#0E645D` |
| `auroraStops` | `#7A3FD1` `#4B3FC0` `#1F8FB0` `#2FE0CF` | same |
| `dockGlass` | `#100D1E` at 72% | `#FFFFFF` at 90% |
| `dockGlassEdge` | white at 14% | `#101316` at 10% |
| `dockMeter` | `#FFFFFF` | `#128077` |
| `avatarInk` | `#08131A` | same |
| `avatarLilac` | `#C49BF5` | `#7A4FC4` |
| `avatarTeal` | `#29C0B4` | `#128077` |
| `avatarRing` | white at 8% | `#101316` at 7.2% |
| `bannerGround` | `#10101A` | same (the banner stays dark) |
| `bannerInk` | `#FFFFFF` | same |
| `bannerSoft` | white at 75% | same |
| `glassFill` | white at 5% | same (all but invisible on the page) |
| `glassEdge` | white at 9% | same |
| `glassRule` | white at 7% | `#101316` at 6.3% |
| `signOutInk` | `#FF8A8C` | `#B0161A` |
| `signOutWash` | `#FF6B6E` at 12% | same |
| `signOutEdge` | `#FF6B6E` at 30% | same |
| `heroGround` | `#0E111A` | `#FFFFFF` |
| `waveformInk` | white at 88% | `#101316` at 79% |
| `controlFill` | white at 6% | `#101316` at 4% |
| `controlEdge` | white at 14% | `#101316` at 14% |
| `ringTrack` | white at 10% | `#101316` at 10% |
| `fieldWell` | black at 25% | `#101316` at 4.5% |
| `onAccentInk` | `#0B0C10` | `#101316` |
| `primaryFill` | `#FFFFFF` | `#101316` |
| `primaryInk` | `#0B0C10` | `#FEFEFE` |
| `destructiveInk` | `#FF8A8C` | `#B0161A` |
| `quietFill` | white at 8% | `#101316` at 7.2% |
| `sheetGlass` | `#121020` at 96% | `#FEFEFC` at 93% |
| `toastGlass` | `#121020` at 90% | `#FEFEFC` at 93% |
| `scrim` | `#05050A` at 55% | `#F2F1EC` at 55% |
| `floatShadow` | black at 70% | black at 12% |
| `calendarDeepInk` | `#04332F` | same |

`controlFill` and `controlEdge` carry a high-contrast pair as well: under Increase Contrast the
fill is drawn at 28% and the edge solid (`#9BA1B2` dark, `#6A607E` light).

`BrandPalette.Redesign.Panel` is the clipboard panel's own set (glass, film, popover, label tones,
accent, key and destructive colours, and the aurora's opacity); its values and contrast are in
[`app-quick-panel.md`](app-quick-panel.md#palette-and-contrast).

## Contrast

Text tones clear 4.5:1 on the page, the window and a card; accents clear 3:1 there, the bar for
marks. The floating button's ink clears 4.5:1 on its glass and the meter 3:1, measured over the
same dark and light desktops [`app-dock.md`](app-dock.md#colours) uses. `RedesignTokenTests` in
`Tests/UttrflowTests/BrandPaletteTests.swift` measures all of these.

### The Insights calendar's day numbers

Every tile is `#5FE0D3` at a shade, in both appearances, over the card's film. In dark the number
is white up to a shade of 0.5 (`InsightsCalendarDay.inkCeiling`) and `calendarDeepInk`
(`#04332F`) from 0.72 (`deepInkFloor`), and no tile is drawn between the two, because there
neither ink reaches 4.5:1:

| Shade | White | `#04332F` |
|---|---|---|
| 0.50 | 4.84:1 | 2.86:1 |
| 0.61 | 3.67:1 | 3.77:1 |
| 0.72 | 2.83:1 | 4.87:1 |

A tile whose share of the busiest day lands in that band is drawn at the nearer edge. Light
clears 9:1 with either ink on every shade. `InsightsCalendarDay.shade` holds the rule, and
`InsightsCalendarContrastTests` checks every shade from 0 to 100%.

## Typeface

Headings use Outfit, a variable font under the SIL Open Font License 1.1. The font file and its
licence ship together in `Sources/Uttrflow/Resources/Fonts/` (`Outfit-Variable.ttf`,
`Outfit-OFL.txt`), as the licence requires. `BrandFont` registers it for the process at launch and
falls back to the system font when the file is missing or registration fails.

Three more families ship under the same licence, each beside its licence file, and each falls back
to a system font. `BrandWordmark` sets the name in Bricolage Grotesque through `BrandFont.wordmark`.
The Home greeting and the first half of the hero headline use Inter Tight through
`BrandFont.headline`; the headline's second half uses Instrument Serif Italic through
`BrandFont.headlineEmphasis`. No other text uses them.

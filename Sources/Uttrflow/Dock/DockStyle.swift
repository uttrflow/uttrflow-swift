// The glass material and the colour palette the dock is drawn in.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

// MARK: - Material

extension View {
    /// The tinted glass every form but the resting one is drawn on: violet-black when dark, frosted white when light.
    func glass(cornerRadius: CGFloat, opaque: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(opaque ? Color.dockOpaqueGlass : Color.dockGlass, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.dockGlassEdge, lineWidth: 1))
            // Clipped and flattened before the shadow, or the material's rectangular backing leaks a square halo.
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .dockShadow, radius: 12, y: 7)
    }
}

// MARK: - Colours

extension Color {
    /// Fills that carry text, capped at 29% lightness so white 13-point text clears 4.5:1.
    static let dockAccent = Color(rgb: BrandPalette.Teal.deep)
    /// Controls and graphics with no text on them.
    static let dockAccentLight = Color(rgb: BrandPalette.Teal.light)
    static let dockAccentTint = Color(rgb: BrandPalette.Teal.tint)
    static let dockAccentWash = Color(rgb: BrandPalette.Teal.wash)
    /// Recording and destructive: the main window's critical tone and its destructive buttons.
    static let dockRecording = Color(rgb: BrandPalette.Semantic.recording)
    /// The live accent: what is selected, what is running.
    static let dockActive = Color(rgb: BrandPalette.Teal.primary)
    /// Words and glyphs on the dock's glass: white when dark, ink when light.
    static let dockInk = Color(nsColor: .orbit(BrandPalette.Redesign.textStrong))
    /// The dock's glass tint over the system material.
    static let dockGlass = Color(nsColor: .orbit(BrandPalette.Redesign.dockGlass))
    /// The solid tint behind notice text when Increase Contrast is on.
    static let dockOpaqueGlass = Color(nsColor: .orbit(BrandPalette.Redesign.dockGlass.tone))
    /// The hairline round the dock's glass.
    static let dockGlassEdge = Color(nsColor: .orbit(BrandPalette.Redesign.dockGlassEdge))
    static let dockShadow = Color(nsColor: .orbit(BrandPalette.Redesign.dockShadow))
    /// The listening meter: white on the dark glass, dictation teal on the light.
    static let dockMeter = Color(nsColor: .orbit(BrandPalette.Redesign.dockMeter))
    static let dockSuccess = Color(rgb: BrandPalette.Semantic.success)
    static let dockWarning = Color(rgb: BrandPalette.Semantic.warning)
    /// The warning as text on the dock's glass, which the bright tone fails on a light desktop.
    static let dockWarningInk = Color(nsColor: .orbit(BrandPalette.Semantic.cautionInk))
    /// The failure disc under a white glyph.
    static let dockWarningFill = Color(rgb: BrandPalette.Semantic.warningFill)

    /// The accent as text on a surface that follows the appearance; `dockAccent` is for fills.
    static let accentInk = Color(nsColor: .orbit(BrandPalette.Teal.ink))
    /// A warning as text; `dockWarning` is for dots, icons and fills.
    static let warningInk = Color(nsColor: .orbit(BrandPalette.Semantic.warningInk))
    /// Success as text; `dockSuccess` is for dots, icons and fills.
    static let successInk = Color(nsColor: .orbit(BrandPalette.Semantic.successInk))
    /// A failure as text; `dockRecording` is for dots, icons and fills.
    static let criticalInk = Color(nsColor: .orbit(BrandPalette.Semantic.criticalInk))
}

extension LinearGradient {
    /// The accent as a filled control, deepened at the top so the fill reads as lit from above.
    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [Color(rgb: BrandPalette.Teal.deepLit), .dockAccent], startPoint: .top, endPoint: .bottom)
    }
}

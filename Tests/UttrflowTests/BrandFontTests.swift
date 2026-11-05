// Tests for the bundled display typeface.

import CoreText
import Foundation
import SwiftUI
import Testing

@testable import Uttrflow

@Suite("The brand typeface")
struct BrandFontTests {
    @Test("the font file and its licence ship in the bundle")
    func shipsWithLicence() {
        #expect(BrandFont.fileURL != nil)
        #expect(Bundle.module.url(forResource: "Outfit-OFL", withExtension: "txt") != nil)
    }

    @Test("registration succeeds, and a second registration still counts as available")
    func registers() {
        #expect(BrandFont.isAvailable)
        #expect(BrandFont.register(BrandFont.fileURL))
    }

    @Test("the registered family resolves to the bundled typeface")
    func resolvesFamily() {
        _ = BrandFont.isAvailable
        let font = CTFontCreateWithName(BrandFont.family as CFString, 20, nil)
        #expect(CTFontCopyFamilyName(font) as String == BrandFont.family)
    }

    @Test("a missing or unreadable file is reported as unavailable")
    func missingFile() {
        #expect(!BrandFont.register(nil))
        #expect(!BrandFont.register(URL(fileURLWithPath: "/nonexistent/font.ttf")))
    }

    @Test("the display font falls back to the system font when the typeface is missing")
    func fallsBack() {
        let fallback = BrandFont.display(size: 20, weight: .bold, available: false)
        let branded = BrandFont.display(size: 20, weight: .bold, available: true)
        #expect(fallback == .system(size: 20, weight: .bold))
        #expect(branded == .custom("Outfit", size: 20).weight(.bold))
        let preferred = BrandFont.display(size: 20, weight: .semibold, available: true)
        #expect(BrandFont.display(size: 20) == preferred)
    }

    @Test("the wordmark font and its licence ship in the bundle and register")
    func wordmarkShips() {
        #expect(BrandFont.wordmarkFileURL != nil)
        #expect(Bundle.module.url(forResource: "BricolageGrotesque-OFL", withExtension: "txt") != nil)
        #expect(BrandFont.isWordmarkAvailable)
        let font = CTFontCreateWithName(BrandFont.wordmarkFamily as CFString, 20, nil)
        #expect(CTFontCopyFamilyName(font) as String == BrandFont.wordmarkFamily)
    }

    @Test("the wordmark face is the display cut at the weight asked for")
    func wordmarkFaceAxes() throws {
        _ = BrandFont.isWordmarkAvailable
        // Core Text leaves an axis out of the variation when it sits at the font's default.
        let face = BrandFont.wordmarkFace(size: 21, weight: 400)
        #expect(CTFontCopyFamilyName(face) as String == BrandFont.wordmarkFamily)
        let axes = try #require(CTFontCopyVariation(face) as? [NSNumber: NSNumber])
        #expect(axes[NSNumber(value: BrandFont.opticalSizeAxis)]?.doubleValue ?? 96 == 96)
        #expect(axes[NSNumber(value: BrandFont.weightAxis)]?.doubleValue == 400)
    }

    @Test("the wordmark font falls back to the system font when the typeface is missing")
    func wordmarkFallsBack() {
        let heavy = BrandFont.wordmark(size: 30, weight: 800, available: false)
        let regular = BrandFont.wordmark(size: 30, weight: 400, available: false)
        #expect(heavy == .system(size: 30, weight: .heavy))
        #expect(regular == .system(size: 30, weight: .regular))
    }

    @Test("the headline font and its licence ship in the bundle and register")
    func headlineShips() {
        #expect(BrandFont.headlineFileURL != nil)
        #expect(Bundle.module.url(forResource: "InterTight-OFL", withExtension: "txt") != nil)
        #expect(BrandFont.isHeadlineAvailable)
        let font = CTFontCreateWithName(BrandFont.headlineFamily as CFString, 20, nil)
        #expect(CTFontCopyFamilyName(font) as String == BrandFont.headlineFamily)
    }

    @Test("the headline font falls back to the system font when the typeface is missing")
    func headlineFallsBack() {
        let branded = BrandFont.headline(size: 30, available: true)
        #expect(BrandFont.headline(size: 30, available: false) == .system(size: 30, weight: .semibold))
        #expect(branded == .custom("Inter Tight", size: 30).weight(.semibold))
        #expect(BrandFont.headline(size: 30) == branded)
    }

    @Test("the emphasis face and its licence ship in the bundle and resolve to the italic")
    func emphasisShips() {
        #expect(BrandFont.headlineEmphasisFileURL != nil)
        #expect(Bundle.module.url(forResource: "InstrumentSerif-OFL", withExtension: "txt") != nil)
        #expect(BrandFont.isHeadlineEmphasisAvailable)
        let font = CTFontCreateWithName(BrandFont.headlineEmphasisFace as CFString, 20, nil)
        #expect(CTFontCopyPostScriptName(font) as String == BrandFont.headlineEmphasisFace)
        #expect(CTFontGetSymbolicTraits(font).contains(.traitItalic))
    }

    @Test("the emphasis font falls back to the system serif italic when the typeface is missing")
    func emphasisFallsBack() {
        let branded = BrandFont.headlineEmphasis(size: 44, available: true)
        let fallback = BrandFont.headlineEmphasis(size: 44, available: false)
        #expect(fallback == .system(size: 44, design: .serif).italic())
        #expect(branded == .custom("InstrumentSerif-Italic", size: 44))
        #expect(BrandFont.headlineEmphasis(size: 44) == branded)
    }
}

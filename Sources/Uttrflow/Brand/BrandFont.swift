// The display typeface the redesign sets headings in, bundled so no screen depends on the network.

import CoreText
import Foundation
import SwiftUI

/// Registers the bundled Outfit typeface and builds display fonts from it. See `Docs/redesign-tokens.md`.
enum BrandFont {
    /// The family name the typeface registers under.
    static let family = "Outfit"

    /// The bundled variable font file.
    static var fileURL: URL? {
        Bundle.module.url(forResource: "Outfit-Variable", withExtension: "ttf")
    }

    /// Whether the typeface is usable, registering it on first read.
    static let isAvailable: Bool = register(fileURL)

    /// Registers a font file for this process; a file already registered counts as success.
    static func register(_ url: URL?) -> Bool {
        guard let url else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
        return code == CTFontManagerError.alreadyRegistered.rawValue
    }

    /// A display font in the brand typeface, or the system font when the typeface is missing.
    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        display(size: size, weight: weight, available: isAvailable)
    }

    /// A display font chosen by whether the typeface is available.
    static func display(size: CGFloat, weight: Font.Weight, available: Bool) -> Font {
        available ? .custom(family, size: size).weight(weight) : .system(size: size, weight: weight)
    }

    /// The family the wordmark is set in.
    static let wordmarkFamily = "Bricolage Grotesque"

    /// The bundled variable font file for the wordmark family.
    static var wordmarkFileURL: URL? {
        Bundle.module.url(forResource: "BricolageGrotesque-Variable", withExtension: "ttf")
    }

    /// Whether the wordmark typeface is usable, registering it on first read.
    static let isWordmarkAvailable: Bool = register(wordmarkFileURL)

    /// The optical size the wordmark is drawn at whatever its point size: the family's narrow display cut.
    static let wordmarkOpticalSize: CGFloat = 96

    /// The OpenType tags of the optical size and weight axes.
    static let opticalSizeAxis = axisTag("opsz")
    static let weightAxis = axisTag("wght")

    /// A four-letter OpenType tag as the number Core Text names an axis by.
    static func axisTag(_ tag: String) -> Int {
        tag.utf8.reduce(0) { $0 << 8 | Int($1) }
    }

    /// A wordmark font at an OpenType weight, or the system font when the typeface is missing.
    static func wordmark(size: CGFloat, weight: CGFloat) -> Font {
        wordmark(size: size, weight: weight, available: isWordmarkAvailable)
    }

    /// A wordmark font chosen by whether the typeface is available.
    static func wordmark(size: CGFloat, weight: CGFloat, available: Bool) -> Font {
        available
            ? Font(wordmarkFace(size: size, weight: weight))
            : .system(size: size, weight: weight >= 600 ? .heavy : .regular)
    }

    /// The wordmark face with its optical size and weight set on the variable font's axes.
    static func wordmarkFace(size: CGFloat, weight: CGFloat) -> CTFont {
        // Core Text sets the optical size from the point size unless it is given outright.
        let axes = [opticalSizeAxis: wordmarkOpticalSize, weightAxis: weight]
        let attributes: [CFString: Any] = [
            kCTFontVariationAttribute: axes as CFDictionary, kCTFontOpticalSizeAttribute: wordmarkOpticalSize,
        ]
        let base = CTFontCopyFontDescriptor(CTFontCreateWithName(wordmarkFamily as CFString, size, nil))
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// The family the Home greeting and the hero headline are set in.
    static let headlineFamily = "Inter Tight"

    /// The bundled variable font file for the headline family.
    static var headlineFileURL: URL? {
        Bundle.module.url(forResource: "InterTight-Variable", withExtension: "ttf")
    }

    /// Whether the headline typeface is usable, registering it on first read.
    static let isHeadlineAvailable: Bool = register(headlineFileURL)

    /// A headline font, or the system font when the typeface is missing.
    static func headline(size: CGFloat) -> Font {
        headline(size: size, available: isHeadlineAvailable)
    }

    /// A headline font chosen by whether the typeface is available.
    static func headline(size: CGFloat, available: Bool) -> Font {
        available
            ? .custom(headlineFamily, size: size).weight(.semibold)
            : .system(size: size, weight: .semibold)
    }

    /// The face the emphasised half of the hero headline is set in.
    static let headlineEmphasisFace = "InstrumentSerif-Italic"

    /// The bundled font file for the headline's emphasis.
    static var headlineEmphasisFileURL: URL? {
        Bundle.module.url(forResource: headlineEmphasisFace, withExtension: "ttf")
    }

    /// Whether the emphasis typeface is usable, registering it on first read.
    static let isHeadlineEmphasisAvailable: Bool = register(headlineEmphasisFileURL)

    /// An emphasis font, or the system serif italic when the typeface is missing.
    static func headlineEmphasis(size: CGFloat) -> Font {
        headlineEmphasis(size: size, available: isHeadlineEmphasisAvailable)
    }

    /// An emphasis font chosen by whether the typeface is available.
    static func headlineEmphasis(size: CGFloat, available: Bool) -> Font {
        available ? .custom(headlineEmphasisFace, size: size) : .system(size: size, design: .serif).italic()
    }
}

import CoreGraphics
import CoreText
import Foundation
import UttrflowCore

/// The type a field's attributed string describes, read without Accessibility so every form is testable.
extension FocusedFieldReader {
    /// What a field says about its own type, either half of which it may leave out.
    struct TypeStyle: Sendable, Equatable {
        /// The type size in points, so the ghost matches the line it sits on.
        let size: CGFloat?
        /// The font family, so the ghost is set in the face the line is.
        let family: String?
        /// Whether the face is bold, so the ghost keeps the run's weight.
        let isBold: Bool
        /// Whether the face is italic or oblique, so the ghost keeps the run's slant.
        let isItalic: Bool
        /// The text colour, so the ghost reads against the field rather than against Uttrflow's appearance.
        var color: TextColor?
    }

    /// The font size in an attributed string, from whichever form the application answered in.
    static func pointSize(inAttributed attributed: CFAttributedString) -> CGFloat? {
        typeStyle(inAttributed: attributed)?.size
    }

    static func writingDirection(inAttributed attributed: CFAttributedString) -> WritingDirection {
        guard CFAttributedStringGetLength(attributed) > 0,
            let attribute = CFAttributedStringGetAttribute(
                attributed, 0, kCTParagraphStyleAttributeName, nil),
            CFGetTypeID(attribute) == CTParagraphStyleGetTypeID()
        else { return .unknown }
        let style = unsafeDowncast(attribute, to: CTParagraphStyle.self)
        var direction = CTWritingDirection.natural
        guard
            CTParagraphStyleGetValueForSpecifier(
                style, .baseWritingDirection, MemoryLayout<CTWritingDirection>.size, &direction)
        else { return .unknown }
        return switch direction {
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        default: .unknown
        }
    }

    /// The font in an attributed string: a Core Text font where AppKit put one, else the `AXFont` dictionary most applications answer with.
    static func typeStyle(inAttributed attributed: CFAttributedString) -> TypeStyle? {
        guard CFAttributedStringGetLength(attributed) > 0 else { return nil }
        let color = textColor(inAttributed: attributed)
        if let font = CFAttributedStringGetAttribute(attributed, 0, kCTFontAttributeName, nil),
            CFGetTypeID(font) == CTFontGetTypeID()
        {
            // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
            let font = unsafeDowncast(font, to: CTFont.self)
            let traits = CTFontGetSymbolicTraits(font)
            return TypeStyle(
                size: CTFontGetSize(font), family: CTFontCopyFamilyName(font) as String,
                isBold: traits.contains(.traitBold), isItalic: traits.contains(.traitItalic), color: color)
        }
        var size: CGFloat?
        var family: String?
        var isBold = false
        var isItalic = false
        if let described = CFAttributedStringGetAttribute(attributed, 0, Self.axFontKey as CFString, nil),
            CFGetTypeID(described) == CFDictionaryGetTypeID()
        {
            // Checked by type ID above; a Core Foundation dictionary bridges to Foundation without AppKit.
            let font = unsafeDowncast(described, to: CFDictionary.self) as NSDictionary
            size = (font[Self.axFontSizeKey] as? NSNumber).map { CGFloat($0.doubleValue) }
            family = font[Self.axFontFamilyKey] as? String
            let name = font[Self.axFontNameKey] as? String
            let style = font[Self.axFontStyleKey] as? String
            let nameTraits = name.map {
                CTFontGetSymbolicTraits(CTFontCreateWithName($0 as CFString, size ?? 12, nil))
            }
            let styleName = style?.lowercased() ?? ""
            isBold = nameTraits?.contains(.traitBold) == true || styleName.contains("bold")
            isItalic =
                nameTraits?.contains(.traitItalic) == true
                || styleName.contains("italic") || styleName.contains("oblique")
        }
        guard size != nil || family != nil || isBold || isItalic || color != nil else { return nil }
        return TypeStyle(size: size, family: family, isBold: isBold, isItalic: isItalic, color: color)
    }

    /// The text colour at the start of an attributed string, from the Accessibility key or the Core Text one.
    static func textColor(inAttributed attributed: CFAttributedString) -> TextColor? {
        let keys = [Self.axForegroundColorKey as CFString, kCTForegroundColorAttributeName]
        for key in keys {
            if let color = textColor(CFAttributedStringGetAttribute(attributed, 0, key, nil)) { return color }
        }
        return nil
    }

    /// A Core Graphics colour as sRGB, or nothing for a value that is not one or cannot be converted.
    static func textColor(_ value: CFTypeRef?) -> TextColor? {
        guard let value, CFGetTypeID(value) == CGColor.typeID,
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        let color = unsafeDowncast(value, to: CGColor.self)
        guard let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
            let channels = converted.components, channels.count >= 3
        else { return nil }
        return TextColor(red: Double(channels[0]), green: Double(channels[1]), blue: Double(channels[2]))
    }

    /// The attribute Accessibility describes a run's font under, which is a dictionary rather than a font object.
    private static let axFontKey = "AXFont"
    private static let axFontSizeKey = "AXFontSize"
    private static let axFontFamilyKey = "AXFontFamily"
    private static let axFontNameKey = "AXFontName"
    private static let axFontStyleKey = "AXFontStyle"
    private static let axForegroundColorKey = "AXForegroundColor"
}

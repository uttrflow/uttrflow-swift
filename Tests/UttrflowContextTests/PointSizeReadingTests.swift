import CoreText
import Foundation
import Testing

import UttrflowCore

@testable import UttrflowContext

@Suite("Reading a font size without building an AppKit object off-main")
struct PointSizeReadingTests {
    /// An attributed string carrying a font, the shape Accessibility answers a range read with.
    private func attributed(pointSize: CGFloat) throws -> CFAttributedString {
        let font = CTFontCreateWithName("Helvetica" as CFString, pointSize, nil)
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 3), kCTFontAttributeName, font)
        return string
    }

    @Test("The size comes back from the Core Text font, not an NSFont.")
    func readsThePointSize() throws {
        let size = FocusedFieldReader.pointSize(inAttributed: try attributed(pointSize: 17))
        #expect(size == 17)
    }

    @Test("The attributed paragraph style reports explicit right-to-left writing direction")
    func readsParagraphWritingDirection() throws {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "אב" as CFString)
        var direction = CTWritingDirection.rightToLeft
        let style = withUnsafePointer(to: &direction) { directionPointer in
            var setting = CTParagraphStyleSetting(
                spec: .baseWritingDirection,
                valueSize: MemoryLayout<CTWritingDirection>.size,
                value: directionPointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 2), kCTParagraphStyleAttributeName, style)
        #expect(FocusedFieldReader.writingDirection(inAttributed: string) == .rightToLeft)
    }

    @Test("An attributed string with no font at all yields nothing rather than a wrong size.")
    func withoutAFontYieldsNothing() throws {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        #expect(FocusedFieldReader.pointSize(inAttributed: string) == nil)
    }

    @Test("An empty attributed string yields nothing.")
    func emptyYieldsNothing() throws {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        #expect(FocusedFieldReader.pointSize(inAttributed: string) == nil)
    }

    @Test("The family comes back beside the size, so the ghost can be set in the field's own face.")
    func readsTheFamilyFromTheFont() throws {
        let style = FocusedFieldReader.typeStyle(inAttributed: try attributed(pointSize: 17))
        #expect(style?.size == 17)
        #expect(style?.family == "Helvetica")
    }

    /// The shape most applications answer with: no font object, only an `AXFont` dictionary describing one.
    private func described(
        size: Double?, family: String?, name: String? = nil, style: String? = nil
    )
        throws -> CFAttributedString
    {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        var font: [String: Any] = [:]
        if let size { font["AXFontSize"] = size }
        if let family { font["AXFontFamily"] = family }
        if let name { font["AXFontName"] = name }
        if let style { font["AXFontStyle"] = style }
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 3), "AXFont" as CFString, font as CFDictionary)
        return string
    }

    @Test("A font described as an AXFont dictionary, as TextEdit answers, is read as size and family.")
    func readsTheAccessibilityDictionary() throws {
        let style = FocusedFieldReader.typeStyle(inAttributed: try described(size: 11, family: "Menlo"))
        #expect(style?.size == 11)
        #expect(style?.family == "Menlo")
        let size = FocusedFieldReader.pointSize(inAttributed: try described(size: 11, family: "Menlo"))
        #expect(size == 11)
    }

    @Test("Bold and italic AXFont names preserve their symbolic traits.")
    func readsAccessibilityFontTraits() throws {
        let bold = FocusedFieldReader.typeStyle(
            inAttributed: try described(size: 11, family: "Helvetica", name: "Helvetica-Bold"))
        #expect(bold?.isBold == true)
        #expect(bold?.isItalic == false)

        let italic = FocusedFieldReader.typeStyle(
            inAttributed: try described(size: 11, family: "Helvetica", style: "Italic"))
        #expect(italic?.isBold == false)
        #expect(italic?.isItalic == true)
    }

    @Test("A dictionary missing one half still yields the other, and one with neither yields nothing.")
    func partialDictionariesAreKept() throws {
        #expect(FocusedFieldReader.typeStyle(inAttributed: try described(size: 12, family: nil))?.size == 12)
        #expect(
            FocusedFieldReader.typeStyle(inAttributed: try described(size: nil, family: "Georgia"))?.family
                == "Georgia")
        #expect(FocusedFieldReader.typeStyle(inAttributed: try described(size: nil, family: nil)) == nil)
    }

    /// An attributed string whose first run carries a colour under the given key and nothing else.
    private func coloured(_ color: CGColor, key: CFString) throws -> CFAttributedString {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        CFAttributedStringSetAttribute(string, CFRange(location: 0, length: 3), key, color)
        return string
    }

    @Test("White text under AXForegroundColor is read as white, so the ghost is light on a dark field")
    func readsTheAccessibilityForegroundColour() throws {
        let white = CGColor(gray: 1, alpha: 1)
        let style = FocusedFieldReader.typeStyle(
            inAttributed: try coloured(white, key: "AXForegroundColor" as CFString))
        let color = try #require(style?.color)
        #expect(abs(color.red - 1) < 0.01 && abs(color.green - 1) < 0.01 && abs(color.blue - 1) < 0.01)
        #expect(style?.size == nil)
    }

    @Test("The Core Text foreground key is read beside the font")
    func readsTheCoreTextForegroundColour() throws {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 3), kCTFontAttributeName,
            CTFontCreateWithName("Helvetica" as CFString, 12, nil))
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 3), kCTForegroundColorAttributeName,
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let style = FocusedFieldReader.typeStyle(inAttributed: string)
        #expect(style?.size == 12)
        #expect(style?.color == TextColor(red: 0, green: 0, blue: 0))
    }

    @Test("A value under the colour key that is not a colour is ignored")
    func aNonColourIsIgnored() throws {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 3), "AXForegroundColor" as CFString, "white" as CFString)
        #expect(FocusedFieldReader.typeStyle(inAttributed: string) == nil)
        #expect(FocusedFieldReader.textColor(nil) == nil)
    }
}

import CoreText
import Foundation
import Testing

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
    private func described(size: Double?, family: String?) throws -> CFAttributedString {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "abc" as CFString)
        var font: [String: Any] = [:]
        if let size { font["AXFontSize"] = size }
        if let family { font["AXFontFamily"] = family }
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

    @Test("A dictionary missing one half still yields the other, and one with neither yields nothing.")
    func partialDictionariesAreKept() throws {
        #expect(FocusedFieldReader.typeStyle(inAttributed: try described(size: 12, family: nil))?.size == 12)
        #expect(
            FocusedFieldReader.typeStyle(inAttributed: try described(size: nil, family: "Georgia"))?.family
                == "Georgia")
        #expect(FocusedFieldReader.typeStyle(inAttributed: try described(size: nil, family: nil)) == nil)
    }
}

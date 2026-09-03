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
}

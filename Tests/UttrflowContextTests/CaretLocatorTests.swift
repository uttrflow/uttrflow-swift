import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// A field that answers only the questions a test gives it an answer for.
private struct Field {
    var bounds: (Int, Int) -> CGRect? = { _, _ in nil }
    var marker: CGRect? = nil
    var frame: CGRect? = nil
    var pointSize: CGFloat? = nil
    var value: String? = nil

    func caret(at selection: (location: Int, length: Int)?) -> CGRect? {
        CaretLocator.caret(
            at: selection, frame: frame, pointSize: pointSize, value: value,
            textSelectionLocation: selection?.location, bounds: bounds, markerBounds: { marker })
    }
}

/// The field a test describes.
private func locator(
    bounds: @escaping (Int, Int) -> CGRect? = { _, _ in nil }, marker: CGRect? = nil, frame: CGRect? = nil,
    value: String? = nil
) -> Field {
    Field(bounds: bounds, marker: marker, frame: frame, value: value)
}

@Suite("Where the caret is found from a field's answers")
struct CaretLocatorTests {
    @Test("A field that refuses its selected range still gets a caret from its text-marker bounds.")
    func refusedRangeFallsBackToTheMarker() {
        let found = locator(marker: CGRect(x: 300, y: 140, width: 0, height: 17)).caret(at: nil)
        #expect(found == CGRect(x: 300, y: 140, width: 0, height: 17))
    }

    @Test("A field that refuses its range and parks a one-pixel field at the caret gets that frame.")
    func refusedRangeFallsBackToACaretShapedFrame() {
        let found = locator(frame: CGRect(x: 88, y: 60, width: 1, height: 16)).caret(at: nil)
        #expect(found == CGRect(x: 88, y: 60, width: 0, height: 16))
    }

    @Test("A refused range with no marker and a field-sized frame has no caret.")
    func refusedRangeWithNothingElseHasNoCaret() {
        #expect(locator(frame: CGRect(x: 0, y: 0, width: 400, height: 40)).caret(at: nil) == nil)
    }

    @Test("The glyph before the caret still wins over the marker where the range is answered.")
    func glyphBeforeTheCaretWins() {
        let field = locator(
            bounds: { location, length in
                location == 4 && length == 1 ? CGRect(x: 40, y: 10, width: 8, height: 16) : nil
            },
            marker: CGRect(x: 999, y: 999, width: 0, height: 16))
        #expect(field.caret(at: (location: 5, length: 0)) == CGRect(x: 48, y: 10, width: 0, height: 16))
    }

    @Test("Adjacent right-to-left glyph bounds put the caret at the previous glyph's leading edge")
    func rightToLeftCaretUsesLeadingEdge() throws {
        let found = try #require(
            CaretLocator.result(
                at: (location: 1, length: 0), frame: nil, value: "אב",
                bounds: { location, _ in
                    location == 0
                        ? CGRect(x: 100, y: 10, width: 9, height: 16)
                        : CGRect(x: 82, y: 10, width: 9, height: 16)
                }, markerBounds: { nil }))
        #expect(found.caret == CGRect(x: 100, y: 10, width: 0, height: 16))
        #expect(found.direction == .rightToLeft)
    }

    @Test("An RTL paragraph direction places an end-of-line caret at the previous glyph's leading edge")
    func rightToLeftLineEndUsesParagraphDirection() throws {
        let found = try #require(
            CaretLocator.result(
                at: (location: 2, length: 0), frame: nil, value: "אב",
                paragraphDirection: .rightToLeft,
                bounds: { location, _ in
                    location == 1 ? CGRect(x: 82, y: 10, width: 9, height: 16) : nil
                }, markerBounds: { nil }))
        #expect(found.caret == CGRect(x: 82, y: 10, width: 0, height: 16))
        #expect(found.direction == .rightToLeft)
    }

    @Test("The caret convenience method passes paragraph direction through to the result")
    func caretPassesParagraphDirectionThrough() {
        let found = CaretLocator.caret(
            at: (location: 2, length: 0), frame: nil, value: "אב",
            paragraphDirection: .rightToLeft,
            bounds: { location, _ in
                location == 1 ? CGRect(x: 82, y: 10, width: 9, height: 16) : nil
            }, markerBounds: { nil })
        #expect(found == CGRect(x: 82, y: 10, width: 0, height: 16))
    }

    @Test("Overlapping mixed-direction glyph bounds leave direction unknown")
    func ambiguousCaretDirectionIsUnknown() {
        let found = CaretLocator.result(
            at: (location: 1, length: 0), frame: nil, value: "אa",
            bounds: { location, _ in
                location == 0
                    ? CGRect(x: 100, y: 10, width: 12, height: 16)
                    : CGRect(x: 106, y: 10, width: 12, height: 16)
            }, markerBounds: { nil })
        #expect(found?.direction == .unknown)
    }

    @Test("A surrogate-pair emoji is queried as one character before the caret")
    func surrogateEmojiUsesItsFullRange() {
        var requested: (Int, Int)?
        let field = CaretLocator.caret(
            at: (location: 2, length: 0), frame: nil, value: "👍", textSelectionLocation: 2,
            bounds: { location, length in
                guard location < 2 else { return nil }
                requested = (location, length)
                return CGRect(x: 40, y: 10, width: 18, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.0 == 0 && requested?.1 == 2)
        #expect(field == CGRect(x: 58, y: 10, width: 0, height: 16))
    }

    @Test("A ZWJ family is queried as one character before the caret")
    func familyEmojiUsesItsFullRange() {
        let family = "👨‍👩‍👧‍👦"
        var requested: (Int, Int)?
        let field = CaretLocator.caret(
            at: (location: family.utf16.count, length: 0), frame: nil, value: family,
            textSelectionLocation: family.utf16.count,
            bounds: { location, length in
                guard location < family.utf16.count else { return nil }
                requested = (location, length)
                return CGRect(x: 40, y: 10, width: 72, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.0 == 0 && requested?.1 == family.utf16.count)
        #expect(field == CGRect(x: 112, y: 10, width: 0, height: 16))
    }

    @Test(
        "Bounds after the caret and selection cover the full following grapheme",
        arguments: ["🇺🇸", "👨‍👩‍👧‍👦", "e\u{301}"]
    )
    func followingGraphemeUsesItsFullRange(_ grapheme: String) {
        let length = grapheme.utf16.count
        let value = "a" + grapheme + "z"
        var requested: (Int, Int)?
        _ = CaretLocator.caret(
            at: (location: 1, length: 0), frame: nil, value: value,
            bounds: { location, length in
                requested = (location, length)
                return CGRect(x: 40, y: 10, width: 18, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.0 == 1 && requested?.1 == length)

        requested = nil
        _ = CaretLocator.caret(
            at: (location: 1, length: length), frame: nil, value: value,
            bounds: { location, length in
                requested = (location, length)
                return CGRect(x: 40, y: 10, width: 18, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.0 == 1 && requested?.1 == length)
    }

    @Test("A selection gets its caret from the glyph at its start")
    func selectionUsesStartGlyph() {
        var requested: (Int, Int)?
        let found = CaretLocator.caret(
            at: (location: 12, length: 100_000_000), frame: nil, value: "abcdefghijklm",
            textSelectionLocation: 12,
            bounds: { location, length in
                requested = (location, length)
                return CGRect(x: 30, y: 10, width: 8, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.1 == 1)
        #expect(found == CGRect(x: 30, y: 10, width: 0, height: 16))
    }

    @Test("A bounded text window supplies its local selection while bounds use the field offset")
    func boundedTextWindowKeepsTheFieldOffset() {
        var requested: (Int, Int)?
        let field = CaretLocator.caret(
            at: (location: 1_002, length: 0), frame: nil, value: "a👍", textSelectionLocation: 3,
            bounds: { location, length in
                guard location < 1_002 else { return nil }
                requested = (location, length)
                return CGRect(x: 40, y: 10, width: 18, height: 16)
            }, markerBounds: { nil })
        #expect(requested?.0 == 1_000 && requested?.1 == 2)
        #expect(field == CGRect(x: 58, y: 10, width: 0, height: 16))
    }

    @Test("A caret after Return uses the first glyph on the new line, not the line break's bounds.")
    func caretAfterReturnUsesTheFollowingGlyph() {
        let field = locator(
            bounds: { location, length in
                switch (location, length) {
                case (5, 1): CGRect(x: 80, y: 10, width: 0, height: 16)
                case (6, 1): CGRect(x: 12, y: 30, width: 7, height: 18)
                default: nil
                }
            }, value: "Hello\nGoodbye")
        #expect(field.caret(at: (location: 6, length: 0)) == CGRect(x: 12, y: 30, width: 0, height: 18))
    }

    @Test("Zero-size glyph bounds fall through to the marker, as a Chromium field answers them.")
    func zeroSizeGlyphsFallThrough() {
        let field = locator(
            bounds: { _, _ in CGRect(x: 2_865, y: 154, width: 0, height: 0) },
            marker: CGRect(x: 310, y: 150, width: 0, height: 15))
        #expect(field.caret(at: (location: 22, length: 0)) == CGRect(x: 310, y: 150, width: 0, height: 15))
    }

    @Test("A reading whose range was refused but whose value and marker answered can take the inline ghost.")
    func refusedRangeStillTakesTheGhost() {
        let caret = locator(marker: CGRect(x: 300, y: 140, width: 0, height: 17)).caret(at: nil)
        let reading = FocusedFieldSnapshot(
            bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", role: "AXTextArea",
            value: "Thanks for the quick", selection: nil, caret: caret)
        #expect(reading.placement == .inlineGhost)
        #expect(reading.currentLine == "Thanks for the quick")
    }

    @Test("A marker rectangle that is the whole rich editor is no caret, so nothing is drawn at its corner")
    func markerAsTheWholeEditorIsNoCaret() {
        let editor = CGRect(x: 64, y: 1_117, width: 602, height: 202)
        var field = locator(
            bounds: { _, _ in CGRect(x: 0, y: 1_117, width: 0, height: 0) }, marker: editor, frame: editor)
        #expect(field.caret(at: (location: 84, length: 0)) == nil)
        field.frame = nil
        #expect(field.caret(at: (location: 84, length: 0)) == nil)
        field.frame = editor
        field.pointSize = 80
        #expect(field.caret(at: (location: 84, length: 0)) == nil)
    }

    @Test("A marker rectangle taller than a line of the field's type is no caret, and one line of it is")
    func markerTallerThanALineIsNoCaret() {
        var field = locator(marker: CGRect(x: 90, y: 40, width: 0, height: 60), frame: nil)
        field.pointSize = 14
        #expect(field.caret(at: nil) == nil)
        field.marker = CGRect(x: 90, y: 40, width: 0, height: 18)
        #expect(field.caret(at: nil) == CGRect(x: 90, y: 40, width: 0, height: 18))
        field.pointSize = nil
        field.marker = CGRect(x: 90, y: 40, width: 0, height: 40)
        #expect(field.caret(at: nil) == CGRect(x: 90, y: 40, width: 0, height: 40))
    }

    @Test(
        "A one-line field whose marker fills it is no caret, since the marker's corner is not where typing is"
    )
    func markerFillingAOneLineFieldIsNoCaret() {
        let input = CGRect(x: 10, y: 10, width: 300, height: 22)
        #expect(locator(marker: input, frame: input).caret(at: nil) == nil)
        #expect(
            locator(marker: CGRect(x: 120, y: 13, width: 0, height: 16), frame: input).caret(at: nil)
                == CGRect(x: 120, y: 13, width: 0, height: 16))
    }
}

import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// A field that refuses its character range gives the dictation read the same caret text through text markers.
struct MarkerSelectionRungTests {
    static let value = "Dear team, the draft is ready"
    static let caret = 9

    private static func read(field answers: [String: FieldAnswer]) -> (FocusedWindow?, [String]) {
        let log = MessageLog()
        let field = Node(id: 2, role: "AXTextArea", answers: answers)
        let window = Node(id: 3, role: "AXWindow", answers: ["AXTitle": .value("Draft")])
        let app = Node(
            id: 1, role: "AXApplication",
            answers: ["AXFocusedWindow": .value(window), "AXFocusedUIElement": .value(field)])
        let source = TreeWindowSource(
            tree: FakeTree(root: app, messages: log), app: app,
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
        return (sink.value, log.asked)
    }

    private static let base: [String: FieldAnswer] = [
        "AXRole": .value("AXTextArea"), "AXValue": .value(value), "AXMultiline": .value(true),
    ]

    @Test func markerRungGivesTheSameCaretTextAsTheCharacterRange() {
        var answering = Self.base
        answering["AXSelectedTextRange"] = .value(CFRange(location: Self.caret, length: 0))
        answering["AXNumberOfCharacters"] = .value(Self.value.utf16.count)
        var refusing = Self.base
        refusing["AXSelectedTextMarkerRange"] = .value(
            MarkerSelection(range: NSRange(location: Self.caret, length: 0), count: Self.value.utf16.count))
        let (byRange, rangeMessages) = Self.read(field: answering)
        let (byMarker, markerMessages) = Self.read(field: refusing)
        #expect(byRange?.precedingText == "Dear team")
        #expect(byMarker?.precedingText == byRange?.precedingText)
        #expect(byMarker?.followingText == byRange?.followingText)
        #expect(!rangeMessages.contains("AXSelectedTextMarkerRange"))
        #expect(markerMessages.contains("AXSelectedTextMarkerRange"))
    }

    @Test func markerPastTheFieldEndGivesNoCaretText() {
        var refusing = Self.base
        refusing["AXSelectedTextMarkerRange"] = .value(
            MarkerSelection(range: NSRange(location: 99, length: 0), count: Self.value.utf16.count))
        #expect(Self.read(field: refusing).0?.precedingText == nil)
    }

    @Test func fieldWithNeitherRungGivesNoCaretText() {
        #expect(Self.read(field: Self.base).0?.precedingText == nil)
    }
}

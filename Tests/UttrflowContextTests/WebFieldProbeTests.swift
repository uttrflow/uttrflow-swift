import Foundation
import Testing

@testable import UttrflowContext

/// What the dictation read gets from each web field fixture, one per field type, engine and full-tree state.
struct WebFieldProbeTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    /// The read's outcome for one fixture: the value it keeps, the messages it sent and whether the page is named.
    struct Outcome: Equatable {
        let value: String?
        let messages: Int
        let document: Bool
    }

    private static let text = "Lorem ipsum dolor"
    private static let read = Outcome(value: text, messages: 8, document: true)
    private static let nothing = Outcome(value: nil, messages: 6, document: false)

    static let expected: [String: Outcome] = [
        "web-textarea-chromium-tree-on.json": read,
        "web-textarea-chromium-tree-off.json": Outcome(value: text, messages: 8, document: false),
        "web-textarea-webkit-tree-on.json": read,
        "web-textarea-webkit-tree-off.json": read,
        "web-contenteditable-chromium-tree-on.json": read,
        "web-contenteditable-chromium-tree-off.json": nothing,
        "web-contenteditable-webkit-tree-on.json": read,
        "web-contenteditable-webkit-tree-off.json": read,
        "web-rich-editor-chromium-tree-on.json": Outcome(value: "", messages: 8, document: true),
        "web-rich-editor-chromium-tree-off.json": nothing,
        "web-rich-editor-webkit-tree-on.json": Outcome(value: "", messages: 8, document: true),
        "web-rich-editor-webkit-tree-off.json": Outcome(value: "", messages: 8, document: true),
        "web-address-bar-chromium-tree-on.json": nothing,
        "web-address-bar-chromium-tree-off.json": nothing,
        "web-address-bar-webkit-tree-on.json": nothing,
        "web-address-bar-webkit-tree-off.json": nothing,
    ]

    /// Replays one fixture through the focused-field read, taking the caret from its recorded selection.
    static func outcome(of snapshot: AccessibilitySnapshot) -> Outcome {
        let tree = ReplayTree(snapshot: snapshot)
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        let caret = tree.attribute("AXSelectedTextRange", of: snapshot.focused).integer
        let text = FocusedFieldRead.text(
            of: snapshot.focused, in: tree, names: names,
            at: caret.map { NSRange(location: $0, length: 0) })
        return Outcome(
            value: text.value, messages: tree.messages.asked.count, document: snapshot.document != nil)
    }

    @Test(arguments: expected.keys.sorted())
    func eachWebFieldReplaysItsRecordedOutcome(file: String) throws {
        let data = try Data(contentsOf: Self.directory.appending(path: file))
        let snapshot = try AccessibilitySnapshot.decode(data)
        #expect(snapshot.windowTitle != nil)
        #expect(Self.outcome(of: snapshot) == Self.expected[file])
    }

    @Test func everyWebFixtureHasAnExpectedOutcome() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path())
            .filter { $0.hasPrefix("web-") }
        #expect(Set(files) == Set(Self.expected.keys))
    }
}

import Foundation
import Testing

@testable import UttrflowContext

/// A recorded snapshot answering as the application did, each message logged so a test can count them.
struct ReplayTree: ElementTree {
    let snapshot: AccessibilitySnapshot
    let messages = MessageLog()

    func role(of element: AccessibilitySnapshot.Element) -> String? {
        element.attributes["AXRole"]?.fieldAnswer.string
    }
    func isSecure(_ element: AccessibilitySnapshot.Element) -> Bool { false }
    func text(of element: AccessibilitySnapshot.Element) -> String? {
        element.attributes["AXValue"]?.fieldAnswer.string
    }
    func children(of element: AccessibilitySnapshot.Element) -> [AccessibilitySnapshot.Element] {
        element.children
    }
    func parent(of element: AccessibilitySnapshot.Element) -> AccessibilitySnapshot.Element? { nil }
    func frame(of element: AccessibilitySnapshot.Element) -> CGRect? { nil }

    func attribute(_ name: String, of element: AccessibilitySnapshot.Element) -> FieldAnswer {
        messages.asked.append(name)
        return element.attributes[name]?.fieldAnswer ?? .unsupported
    }

    /// A ranged read cuts the recorded value unless the snapshot recorded a refusal for ranged reads.
    func attribute(_ name: String, of element: AccessibilitySnapshot.Element, range: NSRange) -> FieldAnswer {
        messages.asked.append(name)
        if let recorded = element.rangedText, recorded.kind != .value || recorded.text != nil {
            return recorded.fieldAnswer
        }
        guard let whole = element.attributes["AXValue"]?.fieldAnswer.string, let cut = Range(range, in: whole)
        else { return .unsupported }
        return .value(String(whole[cut]))
    }
}

struct SnapshotReplayTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    private static func load(_ name: String) throws -> AccessibilitySnapshot {
        try AccessibilitySnapshot.decode(Data(contentsOf: directory.appending(path: name)))
    }

    @Test func seedTextAreaReplaysItsReadingAndMessageCount() throws {
        let snapshot = try Self.load("native-text-area.json")
        let tree = ReplayTree(snapshot: snapshot)
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        let text = FocusedFieldRead.text(
            of: snapshot.focused, in: tree, names: names, at: NSRange(location: 11, length: 0))
        #expect(names.role == "AXTextArea")
        #expect(!text.isSecure)
        #expect(text.value == "Lorem ipsum dolor")
        #expect(text.selection == NSRange(location: 11, length: 0))
        #expect(tree.messages.asked == FocusedFieldRead.nameAttributes + ["AXNumberOfCharacters", "AXValue"])
    }

    /// Replays a fixture's read at its recorded selection, returning the reading and the messages it sent.
    private static func replay(_ name: String) throws -> (FieldNames, FieldText, [String]) {
        let snapshot = try load(name)
        let tree = ReplayTree(snapshot: snapshot)
        let caret = snapshot.focused.attributes["AXSelectedTextRange"]?.text.flatMap(NSRange.init)
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        let text = FocusedFieldRead.text(of: snapshot.focused, in: tree, names: names, at: caret)
        return (names, text, tree.messages.asked)
    }

    private static let wholeRead = FocusedFieldRead.nameAttributes + ["AXNumberOfCharacters", "AXValue"]

    @Test(arguments: [
        ("native-plain-text-view.json", "AXTextArea", nil as String?),
        ("native-text-field.json", "AXTextField", nil),
        ("native-search-field.json", "AXTextField", "AXSearchField"),
    ])
    func shortNativeFieldsAreReadWholeInSevenMessages(file: String, role: String, subrole: String?) throws {
        let (names, text, asked) = try Self.replay(file)
        #expect(names.role == role)
        #expect(names.subrole == subrole)
        #expect(!text.isSecure)
        #expect(text.value?.isEmpty == false)
        #expect(asked == Self.wholeRead)
    }

    @Test func richTextViewPublishesListMarkersAndAttachmentsButNotLinkTargets() throws {
        let (_, text, asked) = try Self.replay("native-rich-text-view.json")
        let value = try #require(text.value)
        #expect(value.contains("\t•\tApples\n\t•\tPears\n"))
        #expect(value.contains("the guide"))
        #expect(!value.contains("example.com"))
        #expect(value.contains("\u{FFFC}"))
        #expect(asked == Self.wholeRead)
    }

    @Test func longDocumentIsReadByRangeAroundTheCaretNeverWhole() throws {
        let (_, text, asked) = try Self.replay("native-long-document.json")
        let selection = try #require(text.selection)
        #expect(selection.location == ValueWindow.unitsBefore)
        #expect(text.value?.utf16.count == ValueWindow.unitsBefore + ValueWindow.unitsAfter)
        #expect(asked == FocusedFieldRead.nameAttributes + ["AXNumberOfCharacters", "AXStringForRange"])
    }

    @Test func everyFixtureDecodesInTheCurrentSchema() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        for file in files {
            let snapshot = try AccessibilitySnapshot.decode(Data(contentsOf: file))
            #expect(!snapshot.family.isEmpty)
        }
    }

    @Test func aFixtureInAnotherSchemaIsRefused() {
        let data = Data(#"{"schema":2,"family":"x","focused":{"attributes":{},"children":[]}}"#.utf8)
        #expect(throws: AccessibilitySnapshot.DecodingFailure.unsupportedSchema(2)) {
            try AccessibilitySnapshot.decode(data)
        }
    }
}

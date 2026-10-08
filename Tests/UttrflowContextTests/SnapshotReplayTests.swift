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
        if let recorded = element.rangedText, recorded.kind != .value { return recorded.fieldAnswer }
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

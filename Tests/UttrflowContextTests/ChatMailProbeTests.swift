import Foundation
import Testing

@testable import UttrflowContext

/// A recorded window answering as the application did, with parents found in its bounded subtree.
struct WindowReplayTree: ElementTree {
    typealias Element = AccessibilitySnapshot.Element
    let window: Element

    func role(of element: Element) -> String? { element.attributes["AXRole"]?.fieldAnswer.string }
    func subrole(of element: Element) -> String? { element.attributes["AXSubrole"]?.fieldAnswer.string }
    func isSecure(_ element: Element) -> Bool { false }
    func children(of element: Element) -> [Element] { element.children }
    func frame(of element: Element) -> CGRect? { nil }

    /// The value, then the title, then the description, as the system tree reads a person's text.
    func text(of element: Element) -> String? {
        ["AXValue", "AXTitle", "AXDescription"].lazy
            .compactMap { element.attributes[$0]?.fieldAnswer.string }
            .first { $0.contains { !$0.isWhitespace } }
    }

    /// A list holding links, as the system tree recognises a list of other conversations.
    func isConversationLinkList(_ element: Element) -> Bool {
        guard role(of: element) == "AXList" else { return false }
        return element.children.contains { child in
            role(of: child) == "AXLink" || child.children.contains { role(of: $0) == "AXLink" }
        }
    }

    func parent(of element: Element) -> Element? { Self.parent(of: element, under: window) }

    private static func parent(of element: Element, under node: Element) -> Element? {
        if node.children.contains(element) { return node }
        return node.children.lazy.compactMap { parent(of: element, under: $0) }.first
    }

    func attribute(_ name: String, of element: Element) -> FieldAnswer {
        element.attributes[name]?.fieldAnswer ?? .unsupported
    }

    func attribute(_ name: String, of element: Element, range: NSRange) -> FieldAnswer {
        if let recorded = element.rangedText, recorded.kind != .value { return recorded.fieldAnswer }
        guard let whole = element.attributes["AXValue"]?.fieldAnswer.string, let cut = Range(range, in: whole)
        else { return .unsupported }
        return .value(String(whole[cut]))
    }
}

/// What the dictation read and the surroundings walk get from chat composers and mail bodies. See `Docs/chat-mail-probe.md`.
struct ChatMailProbeTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    private struct Reading {
        let beforeCaret: String?
        let around: String
    }

    private static func read(_ name: String, caret: Int) throws -> Reading {
        let snapshot = try AccessibilitySnapshot.decode(Data(contentsOf: directory.appending(path: name)))
        let window = try #require(snapshot.window)
        let tree = WindowReplayTree(window: window)
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        let text = FocusedFieldRead.text(
            of: snapshot.focused, in: tree, names: names, at: NSRange(location: caret, length: 0))
        let before = text.value.flatMap { value in
            text.selection.flatMap { Range(NSRange(location: 0, length: $0.location), in: value) }
                .map { String(value[$0]) }
        }
        let around = Surroundings.collect(
            around: snapshot.focused, in: tree, windowTitle: snapshot.windowTitle,
            deadline: .now + .seconds(60))
        return Reading(beforeCaret: before, around: around.text ?? "")
    }

    @Test func nativeChatComposerPublishesItsDraftOnlyInTheDescription() throws {
        let reading = try Self.read("chat-native-composer.json", caret: 0)
        #expect(reading.beforeCaret == "")
        #expect(reading.around.contains("Are we still on for the book club at seven?"))
        #expect(reading.around.contains("Mira Okafor"))
    }

    @Test func browserEngineChatComposerFindsTheThreadAndNotTheOtherConversations() throws {
        let draft = "Sounds good, I will bring the"
        let reading = try Self.read("chat-web-engine-composer.json", caret: draft.utf16.count)
        #expect(reading.beforeCaret == draft)
        #expect(reading.around.contains("#garden-club"))
        #expect(reading.around.contains("Lena Voss"))
        #expect(!reading.around.contains("Tomas Brandt"))
        #expect(!reading.around.contains("Workspace"))
    }

    @Test(arguments: [("above", 30), ("below", 136)])
    func webmailBodyKeepsTheQuoteAndFindsTheRecipient(_ side: String, _ caret: Int) throws {
        let reading = try Self.read("mail-web-body-quoted.json", caret: caret)
        let before = try #require(reading.beforeCaret)
        #expect(before.hasPrefix("Thanks, Thursday works for me."))
        #expect(before.contains("> - Tuesday is out") == (side == "below"))
        #expect(reading.around.contains("ana.lima@example.com"))
        #expect(reading.around.contains("Re: Planning call"))
        #expect(!reading.around.contains("Inbox"))
    }

    @Test(arguments: [("above", 0), ("below", 125)])
    func nativeMailBodyKeepsTheQuoteAndHidesTheRecipientToken(_ side: String, _ caret: Int) throws {
        let reading = try Self.read("mail-native-body-quoted.json", caret: caret)
        let before = try #require(reading.beforeCaret)
        #expect(before.isEmpty == (side == "above"))
        #expect(before.contains("> \u{2022} the room number") == (side == "below"))
        #expect(reading.around.contains("Re: Venue details"))
        // The recipient field says only its description, so the token inside it is never walked.
        #expect(!reading.around.contains("Jonas Pereira"))
    }
}

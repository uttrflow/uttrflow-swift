import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// Counts the messages one dictation window read sends, batched and one at a time, over three field families.
struct WindowReadMessageCountTests {
    /// A field family as the fake stands it in: its role, its value, and where the caret is.
    struct Family: CustomTestStringConvertible, Sendable {
        let name: String
        let role: String
        let value: String
        let caret: Int
        let isTerminal: Bool
        var testDescription: String { name }
    }

    static let families = [
        Family(
            name: "native text view", role: "AXTextArea", value: "Dear team, the draft", caret: 9,
            isTerminal: false),
        Family(
            name: "browser text area", role: "AXTextArea",
            value: String(repeating: "word ", count: 400), caret: 1_000, isTerminal: false),
        Family(
            name: "terminal", role: "AXTextArea", value: "user@host.invalid ~ % git status",
            caret: 32, isTerminal: true),
    ]

    private static func app(_ family: Family) -> Node {
        let field = Node(
            id: 2, role: family.role,
            answers: [
                "AXRole": .value(family.role), "AXTitle": .value("Body"),
                "AXSelectedTextRanges": .value([CFRange(location: family.caret, length: 0)]),
                "AXSelectedTextRange": .value(CFRange(location: family.caret, length: 0)),
                "AXNumberOfCharacters": .value(family.value.utf16.count), "AXValue": .value(family.value),
                "AXMultiline": .value(true), "AXTextInputMarkedRange": .noValue,
            ])
        let window = Node(id: 3, role: "AXWindow", answers: ["AXTitle": .value("Draft")])
        return Node(
            id: 1, role: "AXApplication",
            answers: ["AXFocusedWindow": .value(window), "AXFocusedUIElement": .value(field)])
    }

    private static func read(_ family: Family, batches: Bool) -> (FocusedWindow?, [String]) {
        let log = MessageLog()
        let app = app(family)
        let source = TreeWindowSource(
            tree: FakeTree(root: app, messages: log, batches: batches), app: app,
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: family.isTerminal, into: sink, while: { true })
        return (sink.value, log.asked)
    }

    @Test(arguments: families)
    func batchingCutsTheMessagesAndKeepsTheReading(family: Family) {
        let (batched, batchedMessages) = Self.read(family, batches: true)
        let (single, singleMessages) = Self.read(family, batches: false)
        #expect(batched == single)
        #expect(batched?.precedingText?.isEmpty == false)
        #expect(batched?.isMultiline == true)
        #expect(batchedMessages.count == 5)
        #expect(singleMessages.count == 15)
        #expect(batchedMessages.count * 3 <= singleMessages.count * 2)
    }

    @Test func eachBatchIsOneMessageInTheSecureOrder() {
        let (_, messages) = Self.read(Self.families[0], batches: true)
        #expect(
            messages == [
                "AXFocusedWindow+AXFocusedUIElement", "AXTitle",
                "AXRole+AXSubrole+AXIdentifier+AXPlaceholderValue+AXDescription+AXTitle",
                "AXSelectedTextRanges+AXSelectedTextRange+AXNumberOfCharacters+AXMultiline+AXTextInputMarkedRange",
                "AXValue",
            ])
    }

    @Test func aDeclaredSecureFieldIsAskedForNoState() {
        let log = MessageLog()
        let field = Node(id: 2, answers: ["AXRole": .value("AXSecureTextField"), "AXValue": .value("x")])
        let app = Node(id: 1, answers: ["AXFocusedUIElement": .value(field)])
        let source = TreeWindowSource(
            tree: FakeTree(root: app, messages: log), app: app,
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
        #expect(sink.value?.isSecure == true)
        #expect(log.asked.count == 2)
    }

    @Test func eachMessageIsGivenOnlyTheBudgetLeft() {
        let started = ContinuousClock.now
        #expect(MacContextEngine.timeLeft(since: started, now: started) == MacContextEngine.budgetInSeconds)
        let later = MacContextEngine.timeLeft(since: started, now: started + .milliseconds(60))
        #expect(abs(later - 0.04) < 0.0001)
        let spent = MacContextEngine.timeLeft(since: started, now: started + .milliseconds(500))
        #expect(spent == MacContextEngine.minimumMessageTimeout)
    }
}

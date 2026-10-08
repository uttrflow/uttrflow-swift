import CoreFoundation
import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowContext

/// One application as the fake tree answers it, and the reason its read must end with.
struct UnreadField: Sendable, CustomTestStringConvertible {
    let name: String
    let app: Node
    let reason: ContextUnavailableReason

    var testDescription: String { name }
}

/// Every reason a dictation's context read gives for carrying no field text, each driven through the fake tree.
@Suite("Why a context read carries no field text")
struct ContextUnavailableReasonTests {
    private static let window = Node(id: 9, role: "AXWindow", answers: ["AXTitle": .value("Notes")])
    private static let notes = FrontmostApplication(
        name: "Notes", bundleIdentifier: "com.example.notes", processIdentifier: 4_242)

    /// An application whose focused-element answer is `focus`.
    private static func app(focusing focus: FieldAnswer) -> Node {
        Node(
            id: 1, role: "AXApplication",
            answers: ["AXFocusedWindow": .value(window), "AXFocusedUIElement": focus])
    }

    /// An application whose focused field answers `answers`, a text area holding `value` with the caret at its end.
    private static func app(field answers: [String: FieldAnswer] = [:], value: String = "") -> Node {
        let field: [String: FieldAnswer] = [
            "AXRole": .value("AXTextArea"), "AXValue": .value(value),
            "AXNumberOfCharacters": .value(value.utf16.count),
            "AXSelectedTextRange": .value(CFRange(location: value.utf16.count, length: 0)),
        ]
        return app(focusing: .value(Node(id: 2, answers: field.merging(answers) { $1 })))
    }

    static let unreadFields = [
        UnreadField(name: "no Accessibility grant", app: app(focusing: .notTrusted), reason: .notTrusted),
        UnreadField(name: "nothing focused", app: app(focusing: .noValue), reason: .noFocusedElement),
        UnreadField(name: "focus unsupported", app: app(focusing: .unsupported), reason: .noFocusedElement),
        UnreadField(name: "focus refused", app: app(focusing: .cannotComplete), reason: .refused),
        UnreadField(name: "focus timed out", app: app(focusing: .timedOut), reason: .timedOut),
        UnreadField(name: "names refused", app: app(field: ["AXRole": .cannotComplete]), reason: .refused),
        UnreadField(name: "names timed out", app: app(field: ["AXRole": .timedOut]), reason: .timedOut),
        UnreadField(name: "no role", app: app(field: ["AXRole": .noValue]), reason: .refused),
        UnreadField(name: "value refused", app: app(field: ["AXValue": .cannotComplete]), reason: .refused),
        UnreadField(name: "value timed out", app: app(field: ["AXValue": .timedOut]), reason: .timedOut),
        UnreadField(name: "value unsupported", app: app(field: ["AXValue": .unsupported]), reason: .refused),
        UnreadField(
            name: "secure by role", app: app(field: ["AXRole": .value("AXSecureTextField")]), reason: .secure),
        UnreadField(name: "secure by mask", app: app(value: "••••••"), reason: .secure),
    ]

    /// An engine whose window read is the dictation's own read over the fake tree, on `clock`.
    private static func engine(
        reading app: Node, clock: any Clock<Duration> = ContinuousClock()
    ) -> MacContextEngine {
        MacContextEngine(
            readFrontmostApplication: { notes },
            readFocusedWindow: { _, sink in
                let source = TreeWindowSource(
                    tree: FakeTree(root: app), app: app,
                    decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
                    cap: { _ in }, identify: { _ in nil })
                MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
            },
            ownBundleIdentifier: "com.example.uttrflow", ownProcessIdentifier: 1, clock: clock)
    }

    @Test("names why the field text is missing, and carries none of it", arguments: unreadFields)
    func namesTheReason(_ unread: UnreadField) async {
        let context = await Self.engine(reading: unread.app).currentContext()

        #expect(context.unavailable == unread.reason)
        #expect(context.precedingText == nil)
        #expect(context.followingText == nil)
        #expect(context.applicationName == "Notes")
    }

    @Test("a field that gives its text carries no reason, even when it is empty")
    func aReadFieldHasNoReason() async {
        let empty = await Self.engine(reading: Self.app(field: [:])).currentContext()
        let typed = await Self.engine(reading: Self.app(value: "Dear team")).currentContext()

        #expect(empty.unavailable == nil)
        #expect(empty.precedingText == "")
        #expect(typed.unavailable == nil)
        #expect(typed.precedingText == "Dear team")
    }

    @Test("a read cut short by the budget and a truly empty field give different contexts")
    func aTimeoutIsNotAnEmptyField() async {
        let clock = ManualClock()
        let hung = MacContextEngine(
            readFrontmostApplication: { Self.notes },
            readFocusedWindow: { _, sink in
                sink.bank(FocusedWindow(title: "Notes"))
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)) }
            },
            ownBundleIdentifier: "com.example.uttrflow", ownProcessIdentifier: 1, clock: clock)
        async let reading = hung.currentContext()
        await clock.advanceWhenSomethingIsWaiting(by: MacContextEngine.budget)
        let timedOut = await reading
        let empty = await Self.engine(reading: Self.app(field: [:])).currentContext()

        #expect(timedOut.unavailable == .timedOut)
        #expect(timedOut.precedingText == nil)
        #expect(empty.unavailable == nil)
        #expect(timedOut != empty)
    }

    @Test("several selections at once give no caret, so the read says the field refused one")
    func discontinuousSelectionIsRefused() async {
        let ranges: [Any] = [CFRange(location: 0, length: 1), CFRange(location: 3, length: 1)]
        let app = Self.app(field: ["AXSelectedTextRanges": .value(ranges)], value: "abcdef")
        let context = await Self.engine(reading: app).currentContext()

        #expect(context.unavailable == .refused)
        #expect(context.precedingText == nil)
    }

    @Test("Accessibility's not-trusted error is its own answer, not an unsupported attribute")
    func apiDisabledIsNotTrusted() {
        let answer = FieldAnswer.classify(
            code: FieldAnswer.apiDisabledCode, value: nil, elapsedSeconds: 0, timeoutSeconds: 0.05)

        #expect(answer == .notTrusted)
        #expect(answer.unavailable == .notTrusted)
        #expect(FieldAnswer.unsupported.unavailable == nil)
    }
}

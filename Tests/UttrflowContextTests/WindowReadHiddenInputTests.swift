import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// The dictation's window read over an editor that keeps an empty input at the caret and draws its text itself.
struct WindowReadHiddenInputTests {
    private static let stub = CGRect(x: 250, y: 189, width: 1, height: 1)

    /// An editor whose focused input is empty and caret-sized, beside a rendered line holding `typed`.
    private static func app(typed: [String], value: FieldAnswer = .value("")) -> Node {
        let field = Node(
            id: 2, role: "AXTextArea", frame: stub,
            answers: [
                "AXRole": .value("AXTextArea"),
                "AXSelectedTextRange": .value(CFRange(location: 0, length: 0)),
                "AXNumberOfCharacters": .value(0), "AXValue": value,
            ])
        var x: CGFloat = 98
        let runs = typed.enumerated().map { index, text in
            defer { x += 50 }
            return label(20 + index, text, frame: CGRect(x: x, y: 190, width: 50, height: 15))
        }
        let line = Node(id: 10, frame: CGRect(x: 94, y: 190, width: 1_000, height: 15), children: runs)
        let editor = Node(
            id: 5, frame: CGRect(x: 64, y: 171, width: 1_100, height: 300),
            children: [Node(id: 3, frame: stub, children: [field]), line])
        return Node(
            id: 1, role: "AXApplication", children: [editor],
            answers: ["AXFocusedUIElement": .value(field)])
    }

    private static func read(_ app: Node, log: MessageLog? = nil) -> FocusedWindow? {
        let source = TreeWindowSource(
            tree: FakeTree(root: app, messages: log), app: app,
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
        return sink.value
    }

    @Test func theRenderedLineIsTheTextBeforeTheCaret() {
        let window = Self.read(Self.app(typed: ["the build", " is red", " because"]))
        #expect(window?.precedingText == "the build is red because")
        #expect(window?.followingText == "")
    }

    @Test func aStubWithNoRenderedLineIsUnknownNotEmpty() {
        let window = Self.read(Self.app(typed: []))
        #expect(window?.precedingText == nil)
        #expect(window?.followingText == nil)
    }

    @Test func aStubWhoseValueIsRefusedIsStillReadFromItsLine() {
        let window = Self.read(Self.app(typed: ["the build", " is red", " because"], value: .unsupported))
        #expect(window?.precedingText == "the build is red because")
    }

    @Test func anEmptyFieldOfOrdinarySizeStaysTheStartOfTheText() {
        let field = Node(
            id: 2, role: "AXTextArea", frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            answers: [
                "AXRole": .value("AXTextArea"),
                "AXSelectedTextRange": .value(CFRange(location: 0, length: 0)),
                "AXNumberOfCharacters": .value(0), "AXValue": .value(""),
            ])
        let app = Node(id: 1, children: [field], answers: ["AXFocusedUIElement": .value(field)])
        #expect(Self.read(app)?.precedingText == "")
    }

    @Test func aFieldWithTextIsNeverWalked() {
        let field = Node(
            id: 2, role: "AXTextArea", frame: Self.stub,
            answers: [
                "AXRole": .value("AXTextArea"),
                "AXSelectedTextRange": .value(CFRange(location: 3, length: 0)),
                "AXNumberOfCharacters": .value(3), "AXValue": .value("abc"),
            ])
        let visits = VisitCounter()
        let app = Node(id: 1, children: [field], answers: ["AXFocusedUIElement": .value(field)])
        let source = TreeWindowSource(
            tree: FakeTree(root: app, visits: visits), app: app,
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cap: { _ in }, identify: { _ in nil })
        let sink = FocusedWindowSink()
        MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
        #expect(sink.value?.precedingText == "abc")
        #expect(visits.count == 0)
    }

    @Test func aStubReadAddsNoAttributeMessages() {
        let log = MessageLog()
        _ = Self.read(Self.app(typed: ["the build"]), log: log)
        #expect(log.asked.count == 4)
    }
}

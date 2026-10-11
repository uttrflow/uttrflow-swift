import Testing

@testable import UttrflowCore

/// The slot a caret stands in within HTML and CSS, read from invented preceding text.
@Suite("Markup position")
struct MarkupPositionTests {
    /// One invented preceding text and the position it must give.
    struct Case: Sendable, CustomTestStringConvertible {
        let text: String
        let language: CodeLanguage
        let position: MarkupPosition?
        var testDescription: String { "\(language): \(text)" }
    }

    static let cases: [Case] = [
        Case(text: "", language: .html, position: .slot(.text)),
        Case(text: "<body>\n<p>Hello there ", language: .html, position: .slot(.text)),
        Case(text: "<p>It's fine, isn't it ", language: .html, position: .slot(.text)),
        Case(text: "<div ", language: .html, position: .slot(.tag)),
        Case(text: "<div class=hero ", language: .html, position: .slot(.tag)),
        Case(text: "</", language: .html, position: .slot(.tag)),
        Case(text: "<div class=\"a > b\" ", language: .html, position: .slot(.tag)),
        Case(text: "<div class=\"hero ", language: .html, position: .quoted),
        Case(text: "<a title='", language: .html, position: .quoted),
        Case(text: "<div class=hero>", language: .html, position: .slot(.text)),
        Case(text: "<!-- note ", language: .html, position: .quoted),
        Case(text: "<!-- note -->\n", language: .html, position: .slot(.text)),
        Case(text: "a < b and ", language: .html, position: .slot(.text)),
        Case(text: "<style>\n", language: .html, position: .slot(.selector)),
        Case(text: "<style>\n.a {\n  ", language: .html, position: .slot(.property)),
        Case(text: "<style>\n.a { color: ", language: .html, position: .slot(.value)),
        Case(text: "<style>.a { color: red }</style>\n<p>", language: .html, position: .slot(.text)),
        Case(text: "<script>\nlet x = ", language: .html, position: nil),
        Case(text: "<script>let x</script>\n", language: .html, position: .slot(.text)),
        Case(text: "", language: .css, position: .slot(.selector)),
        Case(text: ".a ", language: .css, position: .slot(.selector)),
        Case(text: ".a {\n  ", language: .css, position: .slot(.property)),
        Case(text: ".a {\n  color", language: .css, position: .slot(.property)),
        Case(text: ".a {\n  color: ", language: .css, position: .slot(.value)),
        Case(text: ".a {\n  color: red;\n  ", language: .css, position: .slot(.property)),
        Case(text: ".a {\n  color: red;\n}\n", language: .css, position: .slot(.selector)),
        Case(text: ".a { background: url(a;b.png) ", language: .css, position: .slot(.value)),
        Case(text: "@media (min-width: 600px) {\n", language: .css, position: .slot(.selector)),
        Case(text: "@media (min-width: 600px) {\n  .a {\n    ", language: .css, position: .slot(.property)),
        Case(text: "@font-face {\n  ", language: .css, position: .slot(.property)),
        Case(text: "/* note ", language: .css, position: .quoted),
        Case(text: "/* note */\n", language: .css, position: .slot(.selector)),
        Case(text: ".a { content: \"x ", language: .css, position: .quoted),
        Case(text: ".a { content: \"x{\"; ", language: .css, position: .slot(.property)),
    ]

    @Test("reads the slot from the text before the caret", arguments: cases)
    func readsSlot(testCase: Case) {
        #expect(MarkupPosition.at(testCase.text, language: testCase.language) == testCase.position)
    }

    @Test("claims nothing for another language or for text it was not given")
    func abstains() {
        #expect(MarkupPosition.at("<div ", language: .swift) == nil)
        #expect(MarkupPosition.at("<div ", language: nil) == nil)
        #expect(MarkupPosition.at(nil, language: .html) == nil)
        #expect(MarkupPosition.at(nil, language: .css) == nil)
    }

    @Test("names a slot only where notation may be written")
    func slotOfPosition() {
        #expect(MarkupPosition.quoted.slot == nil)
        #expect(MarkupPosition.slot(.tag).slot == .tag)
    }
}

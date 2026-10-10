import Testing

@testable import UttrflowClipboard

@Suite("Inline HTML white-space styles")
struct RichTextPlainFormWhitespaceTests {
    @Test(
        "preserves whitespace only within preformatted inline styles",
        arguments: ["pre", "pre-wrap", "break-spaces"])
    func inlinePreformattedWhitespace(_ mode: String) {
        let html = "<p>before <span style=\"white-space: \(mode)\">a    b\t c</span> after a    b</p>"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "before a    b\t c after a b")
    }

    @Test("inherits and restores nested white-space styles")
    func nestedWhiteSpaceStyles() {
        let html =
            "<p><span style=\"white-space: pre\">a    <b>b\t c</b>"
            + "<span style=\"white-space: normal\"> d    e</span> f    g</span> h    i</p>"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "a    b\t c d e f    g h i")
    }

    @Test("a stray end tag leaves the open styles as they were")
    func strayEndTagKeepsStyles() {
        let html = "<p><span style=\"white-space: pre\">a    b</b>    c</span> d    e</p>"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "a    b    c d e")
    }
}

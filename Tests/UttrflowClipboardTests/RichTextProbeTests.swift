import Testing

@testable import UttrflowClipboard

/// Written from outside the converter, against the case it would be worst to get wrong.
///
/// A browser reads `Array<String>` as a tag and is right to. Here that would eat a type
/// parameter on the way into an editor — a clip silently arriving as `Array` instead of
/// `Array<String>` is the kind of corruption somebody pastes into production without
/// reading. These exist to prove the converter leaves code alone.
@Suite("What the rich-text converter must not eat")
struct RichTextProbeTests {
    @Test(
        "code that is shaped like markup survives whole",
        arguments: [
            "Array<String>",
            "let names: [String: Set<Int>] = [:]",
            "if (a < b && c > d) { return }",
            "template<typename T> class Vector {};",
            "std::cout << x << std::endl;",
            "a -> b -> c",
            "5 < 10 and 10 > 5",
            "<<<<<<< HEAD",
            "SELECT * FROM t WHERE a < 3 AND b > 1;",
            "func f<T: Sendable>(_ x: T) -> T { x }",
        ])
    func codeSurvives(_ text: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: text) == text)
    }

    /// The other half of the bargain: returning the input untouched would also pass every
    /// test above.
    @Test("but real markup is still flattened")
    func markupIsStillHandled() {
        let html = "<h1>Title</h1><ul><li>one</li><li>two</li></ul><p>See <b>this</b>.</p>"

        let plain = RichTextPlainForm.plainText(fromHTML: html)

        #expect(plain.contains("Title"))
        #expect(plain.contains("• one"))
        #expect(plain.contains("• two"))
        #expect(plain.contains("See this."))
        #expect(!plain.contains("<"), "and nothing bracketed survives")
    }

    /// E3's actual sentence: never HTML tags in a code editor.
    @Test(
        "no tag survives any of these, however malformed",
        arguments: [
            "<p>unclosed",
            "<b><i>crossed</b></i>",
            "<div class=\"x\" data-y='z'>text</div>",
            "<script>alert('x')</script>visible",
            "<style>p{color:red}</style>visible",
            "<!-- comment -->visible",
            "<img src=x onerror=y>visible",
            "text with a stray < and a > in it",
            "<a href=\"https://example.com\">https://example.com</a>",
        ])
    func noTagSurvives(_ html: String) {
        let plain = RichTextPlainForm.plainText(fromHTML: html)

        #expect(!plain.contains("<script"))
        #expect(!plain.contains("<style"))
        #expect(!plain.contains("<div"))
        #expect(!plain.contains("<p>"))
        #expect(!plain.contains("</"))
    }

    /// Never `https://x (https://x)` — the duplicate is what makes people stop trusting a
    /// paste.
    @Test("a link whose words are its address is not printed twice")
    func noDoubledLinks() {
        let same = RichTextPlainForm.plainText(
            fromHTML: "<a href=\"https://example.com\">https://example.com</a>")
        let named = RichTextPlainForm.plainText(
            fromHTML: "<a href=\"https://example.com\">our pricing</a>")

        #expect(same == "https://example.com")
        #expect(named.contains("our pricing"))
        #expect(named.contains("example.com"), "the address is the part a plain target loses")
    }

    /// A non-breaking space looks like a space, is not one, and breaks shell commands and
    /// compilers — the exact surprise this conversion exists to prevent.
    @Test("entities decode, and a non-breaking space becomes an ordinary one")
    func entitiesDecode() {
        #expect(RichTextPlainForm.plainText(fromHTML: "a &amp;&amp; b") == "a && b")
        #expect(RichTextPlainForm.plainText(fromHTML: "&lt;div&gt;") == "<div>")
        #expect(RichTextPlainForm.plainText(fromHTML: "&amp;amp;") == "&amp;")

        let nbsp = RichTextPlainForm.plainText(fromHTML: "git&nbsp;status")
        #expect(nbsp == "git status")
        #expect(!nbsp.unicodeScalars.contains { $0.value == 0x00A0 })
    }

    @Test("nothing at all comes back as nothing")
    func empty() {
        #expect(RichTextPlainForm.plainText(fromHTML: "").isEmpty)
    }
}

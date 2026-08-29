import Testing

@testable import UttrflowClipboard

@Suite("What a copied thing turns out to be")
struct ClipKindDetectorTests {
    /// Most things are prose, and prose is the answer that costs nothing when it is
    /// wrong. Each of these is a near-miss for one of the other kinds.
    @Test(
        "calls ordinary writing text",
        arguments: [
            "hello",
            "Remember to email Priya about the invoice.",
            "example.com",
            "www.example.com",
            "someone@example.com",
            "Use the {name} placeholder in the template.",
            "It cost £4.50; I paid cash.",
            "Meet at 4pm, then dinner: Italian.",
            "ftp://files.example.com/report.pdf",
            "192.168.0.1",
        ])
    func prose(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .text)
    }

    /// Nothing at all is still text: there is no kind for "empty", and the store refuses
    /// to record one anyway.
    @Test("calls nothing text")
    func empty() {
        #expect(ClipKindDetector.kind(of: "") == .text)
        #expect(ClipKindDetector.kind(of: "   \n\t ") == .text)
    }

    /// Surrounding whitespace is a copying accident, never a kind. The clip keeps its
    /// original text; only the detection sees it trimmed.
    @Test("ignores whitespace around the edges")
    func trimming() {
        #expect(ClipKindDetector.kind(of: "  https://example.com \n") == .link)
        #expect(ClipKindDetector.kind(of: "\n#ff0000\n") == .colour)
    }

    // MARK: - Links

    @Test(
        "calls a web address a link",
        arguments: [
            "https://example.com",
            "http://example.com",
            "HTTPS://EXAMPLE.COM",
            "https://example.com/",
            "https://example.com/path/to/page",
            "https://example.com/search?q=clipboard&page=2",
            "https://example.com/docs#installation",
            "https://example.com/search?q=a+b&sort=new#results",
            "http://localhost:3000/admin",
            "https://user@example.com/private",
        ])
    func links(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    /// The three near-misses the product was told about, plus the two that come up in
    /// practice: a scheme-less host and a link with prose attached.
    @Test(
        "does not call these links",
        arguments: [
            "example.com",
            "docs.example.com/page",
            "/Users/me/Sites/example.com",
            "hello@example.com",
            "https://",
            "See https://example.com for details",
        ])
    func notLinks(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .link)
    }

    // MARK: - Colours

    @Test(
        "calls a colour a colour",
        arguments: [
            "#fff",
            "#FFF",
            "#f0a8",
            "#ff00aa",
            "#FF00AA",
            "#ff00aacc",
            "rgb(255, 0, 170)",
            "rgba(255, 0, 170, 0.5)",
            "RGB(255,0,170)",
            "hsl(320, 100%, 50%)",
            "oklch(0.7 0.2 20)",
            "oklab(0.7 0.1 -0.1)",
            "lch(50% 40 30)",
            "color(display-p3 1 0 0.6)",
        ])
    func colours(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .colour)
    }

    /// Five and seven hex digits are not a notation anyone uses, and a bare word after a
    /// hash is a tag rather than a colour.
    @Test(
        "does not call these colours",
        arguments: [
            "#ff00a", "#ff00aab", "#clipboard", "translate(10, 20)", "#ff0000 #00ff00",
            "#ff", "#fffffff", "#hashtag", "#include <stdio.h>",
        ])
    func notColours(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .colour)
    }

    /// The whole clip has to be the colour. A colour with anything else around it is a
    /// sentence about a colour or a line of source, and both of those are clips people
    /// keep — the swatch would be beside the wrong thing, and in the CSS case the row
    /// would lose the monospaced face it needs more.
    @Test(
        "does not call a clip that merely contains a colour one",
        arguments: [
            "The brand colour is #fff.",
            "color: #fff;",
            "background: rgb(0, 128, 255);",
            "--accent: #ff00aa;",
            "See #ff0000 for the old brand red",
        ])
    func containsAColour(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .colour)
    }

    /// Three hex letters are also three ordinary words, and six are `facade`. The `#` is
    /// what keeps a swatch off them, and this is the test that says so out loud.
    @Test(
        "requires the hash",
        arguments: ["fff", "ffffff", "dad", "bed", "ace", "fade", "added", "decade", "facade"])
    func bareHexIsAWord(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .text)
    }

    /// A component out of range is a typo or a slider read in the wrong units, not a
    /// change of kind. It stays a colour and ``ClipKindDetector/colour(in:)`` clamps it —
    /// which is what a browser does with the same string.
    @Test("still calls an out-of-range colour a colour")
    func outOfRange() {
        #expect(ClipKindDetector.kind(of: "rgb(300, 0, 0)") == .colour)
        #expect(ClipKindDetector.kind(of: "hsl(400, 200%, 50%)") == .colour)
    }

    /// Colour is asked after ``ClipKind/secret`` and before ``ClipKind/link`` and
    /// ``ClipKind/code``, and each of those boundaries is a real string rather than a
    /// hypothetical one. A URL fragment is the case that pushed colour below link, and a
    /// bracketed call is the case that pushed it above code.
    @Test("gives way to a secret and to a link, and takes precedence over code")
    func colourPrecedence() {
        // `#fff` after a URL is part of the address, and the address is the clip.
        #expect(ClipKindDetector.kind(of: "https://example.com/theme#fff") == .link)
        // A colour is not a link merely for carrying a hash.
        #expect(ClipKindDetector.kind(of: "#ff00aa") == .colour)
        // A bracketed call is code's shape too, and the colour reading wins.
        #expect(ClipKindDetector.kind(of: "rgb(0, 128, 255)") == .colour)
        #expect(ClipKindDetector.kind(of: "hsla(120, 100%, 50%, 0.5)") == .colour)
        // A credential stays masked whatever else it looks like.
        #expect(ClipKindDetector.kind(of: "api_key = ff00aa11ff00aa11ff00aa11") == .secret)
    }

    // MARK: - Code

    @Test(
        "calls source code code",
        arguments: [
            "#!/usr/bin/env bash\necho hello",
            "func greet(name: String) -> String {\n    \"Hello, \\(name)\"\n}",
            "if (ready) { start(); }",
            "const total = items.length;",
            "class Invoice(models.Model):\n    number = models.CharField()",
            "import Foundation\nimport Testing",
            "SELECT id, name FROM users WHERE active = true;",
            "// the count is one-based here\nreturn index + 1;",
            "let x = 1\nlet y = 2\nreturn x + y",
            "public func run() async {\n    await start()\n}",
        ])
    func code(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .code)
    }

    /// The case the brief called out: one line, no punctuation of any kind, and still
    /// unmistakably something to be set in a monospaced face.
    @Test(
        "calls a one-line shell command code",
        arguments: [
            "brew install jq",
            "git commit -am wip",
            "npm run build",
            "docker ps -a",
            "ls -la",
            "kubectl get pods --namespace prod",
            "$ swift build",
            "cat log.txt | grep error",
            "curl -s https://example.com/api > out.json",
        ])
    func shell(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .code)
    }

    /// Prose that happens to carry a brace, a semicolon or a keyword is not code. One
    /// signal is never enough, which is the rule this exists to hold in place.
    @Test(
        "does not call prose code",
        arguments: [
            "Use the {name} placeholder in your template.",
            "I bought apples, pears and figs; then I went home.",
            "The class starts at nine and the lecture is on Tuesday.",
            "Go to the shop and buy milk.",
            "Please return the book to the library.",
            "She let the dog out.",
            "Sort by name (ascending) and then export.",
        ])
    func notCode(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .code)
    }
}

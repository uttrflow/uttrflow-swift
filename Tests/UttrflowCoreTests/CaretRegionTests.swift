import Testing

@testable import UttrflowCore

@Suite("Whether the caret sits in a comment")
struct CaretRegionTests {
    @Test(
        "calls a line comment a comment",
        arguments: [
            ("Cache.swift", "// "), ("app.js", "  // note: "), ("main.go", "\t// TODO "),
            ("script.py", "# "), ("deploy.sh", "    # "), ("query.sql", "-- "),
        ])
    func lineCommentIsAComment(document: String, preceding: String) {
        #expect(isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "calls executable code not a comment",
        arguments: [
            ("Cache.swift", "func read() -> Value {"), ("Cache.swift", "    "),
            ("app.js", "const total = "), ("query.sql", "SELECT * FROM "),
        ])
    func codeIsNotAComment(document: String, preceding: String) {
        #expect(!isComment(precedingText: preceding, documentName: document))
    }

    @Test("calls a caret inside an unterminated block comment a comment")
    func openBlockCommentIsAComment() {
        #expect(
            isComment(
                precedingText: "let x = 1\n/* still writing this ", documentName: "Cache.swift"))
    }

    @Test("does not call a caret after a closed block comment a comment")
    func closedBlockCommentIsNotAComment() {
        #expect(
            !isComment(
                precedingText: "/* done */ let x = ", documentName: "Cache.swift"))
    }

    @Test("ignores block markers inside strings and line comments")
    func blockMarkersInsideStringsAndLineCommentsAreIgnored() {
        #expect(
            !isComment(
                precedingText: "let s = \"/*\"\nlet y = ", documentName: "Cache.swift"))
        #expect(
            !isComment(
                precedingText: "let glob = \"src/**/*.ts\"\nlet y = ", documentName: "Cache.swift"))
        #expect(
            !isComment(
                precedingText: "// /*\nlet y = ", documentName: "Cache.swift"))
    }

    @Test("recognizes a block opener after a string that contains comment markers")
    func blockOpenerAfterStringIsAComment() {
        #expect(
            isComment(
                precedingText: "let s = \"*/\"\n/* still writing this ", documentName: "Cache.swift"))
    }

    @Test(
        "calls a line comment after code on the caret's line a comment",
        arguments: [("main.swift", "let x = f() // "), ("main.py", "x = 1  # "), ("app.js", "a()\nb() // ")])
    func trailingCommentIsAComment(document: String, preceding: String) {
        #expect(isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "does not call a line marker inside a string a comment",
        arguments: [
            ("main.swift", "let url = \"https://"),
            ("main.swift", "let url = \"https://x.test\"\nlet y = "),
        ])
    func markerInsideStringIsNotAComment(document: String, preceding: String) {
        #expect(!isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "calls an open Python docstring a comment",
        arguments: [
            "def f():\n    \"\"\"", "def f():\n    '''Load ",
            "\"\"\"Module.\"\"\"\ndef f():\n    \"\"\"",
        ])
    func openDocstringIsAComment(preceding: String) {
        #expect(isComment(precedingText: preceding, documentName: "main.py"))
    }

    @Test("does not call code after a closed docstring a comment")
    func closedDocstringIsNotAComment() {
        #expect(
            !isComment(
                precedingText: "def f():\n    \"\"\"Load.\"\"\"\n    return ", documentName: "main.py"))
    }

    @Test("reads the extension off a window title that carries more than the filename")
    func readsExtensionFromAWindowTitle() {
        #expect(
            isComment(precedingText: "// ", documentName: "Retrier.swift — Uttrflow"))
    }

    @Test(
        "never calls an unrecognised or missing document a comment",
        arguments: [(nil, "// "), ("notes.txt", "// "), ("Cache.swift", nil)] as [(String?, String?)])
    func unknownDocumentIsNeverAComment(document: String?, preceding: String?) {
        #expect(!isComment(precedingText: preceding, documentName: document))
    }

    @Test(
        "calls an unclosed string literal a string, which is still code",
        arguments: [("main.swift", "let url = \"https://"), ("main.py", "x = 'a # ")])
    func openStringIsAString(document: String, preceding: String) {
        let region = CaretStructure.region(precedingText: preceding, documentName: document)
        #expect(region == .string)
        #expect(region.isCode)
    }

    @Test(
        "calls body lines of a Markdown or text document prose and a heading not",
        arguments: [
            ("README.md", "Some words ", CaretStructure.Region.prose), ("notes.txt", nil, .prose),
            ("README.md", "intro\n  # Title ", .unrecognised), ("Cache.swift", nil, .code),
        ] as [(String, String?, CaretStructure.Region)])
    func documentProse(document: String, preceding: String?, expected: CaretStructure.Region) {
        #expect(CaretStructure.region(precedingText: preceding, documentName: document) == expected)
    }

    @Test(
        "says a comment opens only before its first word",
        arguments: [
            ("// ", "Cache.swift", true), ("let x = 1 // ", "Cache.swift", true),
            ("/*\n * ", "Cache.swift", true), ("\"\"\"\n", "cache.py", true), ("<!-- ", "page.html", true),
            ("// keep this, ", "Cache.swift", false),
            ("let x = ", "Cache.swift", false), ("// ", "README.md", false), ("// ", nil, false),
        ] as [(String, String?, Bool)])
    func opensComment(preceding: String, document: String?, expected: Bool) {
        #expect(CaretStructure.opensComment(precedingText: preceding, documentName: document) == expected)
    }

    private func isComment(precedingText: String?, documentName: String?) -> Bool {
        CaretStructure.region(precedingText: precedingText, documentName: documentName) == .comment
    }
}

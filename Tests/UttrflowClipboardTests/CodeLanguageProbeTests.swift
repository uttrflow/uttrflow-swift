// Tests for what the language detector refuses.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Written from outside the detector with cases chosen to break it; a wrong chip is worse than none.
@Suite("What the language detector refuses to guess")
struct CodeLanguageRefusalTests {
    @Test(
        "clips that are not one language answer with nothing",
        arguments: [
            // Real formats outside the set it knows, copied constantly.
            (
                "yaml",
                "name: build\non:\n  push:\n    branches: [main]\njobs:\n  test:\n    runs: ubuntu"
            ),
            ("xml", "<config><item name=\"a\" value=\"1\"/></config>"),
            ("dockerfile", "FROM node:20\nRUN npm ci\nCOPY . .\nCMD [\"npm\", \"start\"]"),
            ("env file", "DATABASE_URL=postgres://localhost/db\nAPI_KEY=abc123\nDEBUG=true"),
            ("csv", "name,email,age\nalice,a@example.com,30\nbob,b@example.com,41"),
            // Output *about* code, which is not code.
            (
                "git diff",
                "diff --git a/x.swift b/x.swift\n--- a/x.swift\n+++ b/x.swift\n"
                    + "@@ -1 +1 @@\n-let a = 1\n+let a = 2"
            ),
            (
                "stack trace",
                "Traceback (most recent call last):\n  File \"x.py\", line 3\n"
                    + "    raise ValueError"
            ),
            // Prose that happens to be shaped like a statement — D3.
            ("prose that reads like SQL", "Select all the files from the folder and delete them."),
            ("prose with semicolons", "I went to the shop; it was closed; I came home."),
            ("prose with braces", "I told them {name} would be there, and it was."),
            ("markdown", "- one\n- two\n\nSome **bold** text."),
            ("a link", "https://example.com/path?query=1"),
        ])
    func refuses(_ each: (String, String)) {
        #expect(CodeLanguage.detect(each.1) == nil, "labelled \(each.0) as a language")
    }

    /// Not "we cannot tell" but "this is genuinely two things at once"; a single lead earns no chip.
    @Test(
        "a fragment that is equally two languages answers with nothing",
        arguments: [
            "let x: String = \"a\"",  // Swift and TypeScript both
            "func main() {\n    println(\"hi\")\n}",  // Swift and Go both
            "import Foundation",  // one line, no corroboration
            "x = 1",
            "ls -la | grep foo | awk '{print $1}'",  // shell, but nothing says so
        ])
    func refusesAmbiguity(_ text: String) {
        #expect(CodeLanguage.detect(text) == nil)
    }

    /// The other half of the bargain: refusing everything would also pass the tests above.
    @Test(
        "real source in a language it knows is named",
        arguments: [
            (
                "struct Clip: Sendable {\n    let text: String\n"
                    + "    func summary() -> String { text }\n}", CodeLanguage.swift
            ),
            ("def add(a, b):\n    return a + b\n\nclass Thing:\n    pass", .python),
            (
                "interface User { name: string }\n"
                    + "const greet = (u: User): string => `hi ${u.name}`", .typescript
            ),
            ("SELECT * FROM users WHERE id = 3;", .sql),
            ("[{\"a\": 1}, {\"b\": 2}]", .json),
        ])
    func namesWhatItKnows(_ each: (String, CodeLanguage)) {
        #expect(CodeLanguage.detect(each.0) == each.1)
    }
}

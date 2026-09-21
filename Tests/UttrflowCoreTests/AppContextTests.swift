// Tests for AppContext.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("AppContext")
struct AppContextTests {
    @Test("reports an all-nil context as empty so the prompt can omit it")
    func unknownContextIsEmpty() {
        #expect(AppContext.unknown.isEmpty)
        #expect(AppContext().isEmpty)
    }

    @Test("reports a context as non-empty when any single field is present")
    func anyFieldMakesItNonEmpty() {
        #expect(!AppContext(applicationName: "Slack").isEmpty)
        #expect(!AppContext(bundleIdentifier: "com.example").isEmpty)
        #expect(!AppContext(documentName: "notes.md").isEmpty)
        #expect(!AppContext(selectedText: "hello").isEmpty)
        #expect(!AppContext(precedingText: "").isEmpty, "an empty field is still something learnt")
        #expect(!AppContext(followingText: "later").isEmpty)
    }

    @Test("keeps every field it was given")
    func retainsFields() {
        let context = AppContext(
            applicationName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            documentName: "main.py",
            selectedText: "def main():"
        )

        #expect(context.applicationName == "Visual Studio Code")
        #expect(context.bundleIdentifier == "com.microsoft.VSCode")
        #expect(context.documentName == "main.py")
        #expect(context.selectedText == "def main():")
        #expect(context.precedingText == nil)
        #expect(context.followingText == nil)
    }

    @Test("carries the text either side of the caret when a reader supplies it")
    func retainsCaretText() {
        let context = AppContext(applicationName: "Notes", precedingText: "before ", followingText: " after")
        #expect(context.precedingText == "before ")
        #expect(context.followingText == " after")
    }

    @Test("reads a context written before secure fields were told apart as not secure")
    func decodesOldContextAsNotSecure() throws {
        let json = Data(#"{"applicationName":"Notes","precedingText":"before"}"#.utf8)
        let context = try JSONDecoder().decode(AppContext.self, from: json)

        #expect(context == AppContext(applicationName: "Notes", precedingText: "before"))
        #expect(context.isSecure == false)
    }

    @Test("keeps a secure context secure across encoding")
    func roundTripsSecure() throws {
        let context = AppContext(applicationName: "Notes", isSecure: true)
        let decoded = try JSONDecoder().decode(
            AppContext.self, from: try JSONEncoder().encode(context))

        #expect(decoded == context)
        #expect(decoded.isSecure)
    }

    @Test("a secure field alone does not make a context worth a prompt")
    func secureAloneIsEmpty() {
        #expect(AppContext(isSecure: true).isEmpty)
    }
}

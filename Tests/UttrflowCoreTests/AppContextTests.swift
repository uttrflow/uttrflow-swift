// Tests for AppContext.

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
    }
}

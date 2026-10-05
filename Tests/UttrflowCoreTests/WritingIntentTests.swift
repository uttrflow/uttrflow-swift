import Testing

@testable import UttrflowCore

@Suite("WritingIntent")
struct WritingIntentTests {
    private func intent(document: String?, before: String? = nil) -> WritingIntent {
        let editor = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: document)
        return SituationResolver.resolve(app: editor, insertion: InsertionPoint(precedingText: before)).intent
    }

    @Test("one editor gives each document the language its extension declares")
    func languageFromDocumentName() {
        #expect(intent(document: "Query.sql").language == .sql)
        #expect(intent(document: "main.swift").language == .swift)
        #expect(intent(document: "Sources/App/main.swift").language == .swift)
    }

    @Test("an unknown or missing extension gives no language, not a guess")
    func unknownExtensionIsNil() {
        #expect(intent(document: "Notes.md").language == nil)
        #expect(intent(document: "COMMIT_EDITMSG").language == nil)
        #expect(intent(document: nil).language == nil)
    }

    @Test("with no extension, the text before the caret declares the language")
    func languageFromCaretText() {
        let shell = "#!/bin/bash\nset -euo pipefail\n"
        #expect(intent(document: "COMMIT_EDITMSG", before: shell).language == .shell)
    }

    @Test("the extension outranks the text before the caret")
    func extensionWins() {
        let shell = "#!/bin/bash\nset -euo pipefail\n"
        #expect(intent(document: "Query.sql", before: shell).language == .sql)
    }

    @Test("the intent is the same however the situation is built")
    func oneDerivation() {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "a.py")
        let built = Situation(app: app, insertion: app.insertionPoint, destination: .plain)
        #expect(built.intent == SituationResolver.resolve(from: app).intent)
        #expect(Situation.unknown.intent == .unknown)
    }
}

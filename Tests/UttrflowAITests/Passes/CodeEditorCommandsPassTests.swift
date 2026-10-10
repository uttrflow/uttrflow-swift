import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spoken commands in code editors")
struct CodeEditorCommandsPassTests {
    @Test("writes the reported identifiers and empty parentheses")
    func acceptanceExamples() {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "Example.swift", precedingText: "let x = ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(
            for: .standard(for: .codeEditor), situation: situation)

        #expect(pipeline.run(Draft(text: "camel case user id")).text == "userId")
        #expect(pipeline.run(Draft(text: "snake case max retries")).text == "max_retries")
        #expect(pipeline.run(Draft(text: "open paren close paren")).text == "()")
    }

    @Test("keeps code commands through the deterministic transformer")
    func deterministicTransformer() async throws {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "Example.swift", precedingText: "let x = ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        for (spoken, expected) in [
            ("camel case user id", "userId"),
            ("snake case max retries", "max_retries"),
            ("open paren close paren", "()"),
        ] {
            let request = TransformationRequest(
                transcription: Transcription(text: spoken), situation: situation)
            #expect(try await RuleBasedTransformer().transform(request).text == expected)
        }
    }

    @Test("stops identifier casing at a spoken clause mark")
    func clauseBoundary() {
        let app = AppContext(documentName: "Example.swift")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        #expect(
            pipeline.run(Draft(text: "camel case user id comma then explain it")).text
                == "userId, then explain it")
    }

    @Test("leaves command-like speech unchanged in comments and prose destinations")
    func scopeAndCommentControls() {
        let spoken = "camel case user id open paren close paren"
        let comment = AppContext(documentName: "Example.swift", precedingText: "// ")
        let commentSituation = Situation(
            app: comment, insertion: comment.insertionPoint, destination: .codeEditor)
        let commentPipeline = CleaningPipeline.beforeModel(
            for: .standard(for: .codeEditor), situation: commentSituation)
        #expect(commentPipeline.run(Draft(text: spoken)).text == spoken)

        for destination in [Destination.plain, .document, .email] {
            let app = AppContext(documentName: "Example.swift", precedingText: " ")
            let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
            let pipeline = CleaningPipeline.beforeModel(
                for: .standard(for: destination), situation: situation)
            #expect(pipeline.run(Draft(text: spoken)).text == spoken)
        }
    }

    @Test("leaves prose unchanged in a code editor whose document is not recognised source")
    func proseDocuments() {
        let spoken = [
            "the dot product equals the sum of the products",
            "press the arrow keys to move",
            "the underscore key is next to the dash",
            "all caps is shouting so avoid it",
        ]
        let documents: [(String?, String?)] = [
            ("README.md", "## Notes\n"), ("notes.txt", ""), ("paper.tex", nil), (nil, nil),
        ]
        for (documentName, precedingText) in documents {
            let pipeline = CleaningPipeline.piece(
                numbers: .fromTen, digits: .none, destination: .codeEditor,
                intent: WritingIntent(
                    app: AppContext(documentName: documentName),
                    insertion: InsertionPoint(precedingText: precedingText)))
            for text in spoken {
                #expect(pipeline.run(Draft(text: text)).text == text, "\(documentName ?? "untitled")")
            }
        }
    }

    @Test("writes code operators")
    func symbols() {
        let app = AppContext(documentName: "Example.swift")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        #expect(pipeline.run(Draft(text: "max retries equals five")).text == "max retries = 5")
    }

    /// The words a code editor's rules write for `spoken` when the caret sits in code in `documentName`.
    private static func written(_ spoken: String, in documentName: String) -> String {
        let app = AppContext(documentName: documentName, precedingText: "    ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        return CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test("writes an arrow as the caret's language writes it")
    func arrowFollowsTheLanguage() {
        #expect(Self.written("value arrow bool", in: "Example.swift") == "value -> bool")
        #expect(Self.written("value arrow bool", in: "example.py") == "value -> bool")
        #expect(Self.written("value arrow bool", in: "example.js") == "value => bool")
        #expect(Self.written("value arrow bool", in: "example.ts") == "value => bool")
    }

    @Test("keeps a language's own operators out of a language without them")
    func languageRowsStayInTheirLanguage() {
        #expect(Self.written("left triple equals right", in: "example.ts") == "left === right")
        #expect(Self.written("left triple equals right", in: "example.py") == "left triple = right")
        #expect(Self.written("side double star 2", in: "example.py") == "side ** 2")
        #expect(Self.written("side double star 2", in: "Example.swift") == "side double star 2")
    }

    @Test("leaves a word whose notation depends on the language as spoken where no language is known")
    func unknownLanguageAbstainsOnAmbiguousWords() throws {
        let arrow = try #require(SpokenCommands.codeSymbols.first { $0.id == "code.arrow" })
        let equals = try #require(SpokenCommands.codeSymbols.first { $0.id == "code.double-equals" })
        #expect(!arrow.isEnabled(for: nil))
        #expect(arrow.isEnabled(for: .swift) && !arrow.isEnabled(for: .javascript))
        #expect(equals.isEnabled(for: nil) && equals.isEnabled(for: .python))
    }

    @Test("reads the word after empty parentheses")
    func readsTheWordAfterEmptyParentheses() {
        #expect(Self.written("open paren close paren arrow void", in: "Example.swift") == "() -> void")
        #expect(Self.written("open paren close paren equals nil", in: "Example.swift") == "() = nil")
    }

    @Test("reads a casing phrase that a form of be follows as the subject of prose, at a code caret")
    func casingPhraseAsSubject() {
        for precedingText in ["let total = 0\n", "let message = \""] {
            let app = AppContext(documentName: "notes.swift", precedingText: precedingText)
            let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
            let pipeline = CleaningPipeline.beforeModel(
                for: .standard(for: .codeEditor), situation: situation)
            for spoken in ["all caps is shouting so avoid it", "camel case was the old style"] {
                #expect(pipeline.run(Draft(text: spoken)).text == spoken, "\(precedingText)")
            }
            #expect(pipeline.run(Draft(text: "all caps max retries")).text == "MAX RETRIES")
        }
    }
}

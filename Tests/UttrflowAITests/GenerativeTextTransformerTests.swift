import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

@Suite("GenerativeTextTransformer")
struct GenerativeTextTransformerTests {
    private func request(_ text: String, language: LanguageCode? = .english) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: language))
    }

    @Test("reports the engine it stands for", arguments: [TransformerKind.foundationModels, .cloud])
    func kind(kind: TransformerKind) {
        let sut = GenerativeTextTransformer(kind: kind, model: FakeCleanupModel())
        #expect(sut.kind == kind)
    }

    @Test("asks the model whether it knows the spoken language")
    func asksAboutLanguage() async {
        let model = FakeCleanupModel()
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = await sut.availability(for: request("hello", language: .hindi))
        #expect(model.languagesAsked == [.hindi])
    }

    @Test("passes the model's own verdict straight through")
    func reportsModelAvailability() async {
        let model = FakeCleanupModel(availability: .unsupportedLanguage(.hindi))
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(await sut.availability(for: request("hello")) == .unsupportedLanguage(.hindi))
    }

    @Test("sends the prompt's instructions, not something improvised")
    func sendsPromptInstructions() async throws {
        let model = FakeCleanupModel { _ in "Hello there." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = try await sut.transform(request("hello there"))

        #expect(model.calls.first?.instructions == PromptBuilder.standard.instructions(for: .plain))
        #expect(model.calls.first?.text == "Spoken: \"hello there\"")
        #expect(model.calls.first?.kind == .foundationModels)
    }

    @Test("attributes the result to itself")
    func attributesResult() async throws {
        let model = FakeCleanupModel { _ in "Hello there." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("hello there"))
        #expect(result.text == "Hello there.")
        #expect(result.producedBy == .foundationModels)
    }

    /// The model leaves output ragged even when told not to, so a deterministic pass
    /// finishes it.
    @Test(
        "finishes what the model left ragged",
        arguments: [
            ("Hello  there", "Hello there."),
            ("Hello there", "Hello there."),
            ("  Hello there.  ", "Hello there."),
        ]
    )
    func tidiesModelOutput(modelOutput: String, expected: String) async throws {
        let model = FakeCleanupModel { _ in modelOutput }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        #expect(try await sut.transform(request("hello there")).text == expected)
    }

    /// The passes run first, so the model never sees the fillers and discarded halves it might rewrite.
    @Test("hands the model the draft after the passes, not the raw words")
    func handsModelTheDraft() async throws {
        let model = FakeCleanupModel { _ in "Let's meet at five." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        _ = try await sut.transform(request("um let's meet at four no sorry at five"))

        #expect(model.calls.first?.text == "Spoken: \"let's meet at five\"")
    }

    @Test("finishes the capitals and the full stop the model forgot, and lays out the list it meant")
    func finishesWhatTheModelForgot() async throws {
        let model = FakeCleanupModel { _ in "hello there" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        #expect(try await sut.transform(request("um hello there")).text == "Hello there.")

        let listing = GenerativeTextTransformer(
            kind: .foundationModels, model: FakeCleanupModel { _ in "we need:\n- milk\n\n- eggs" })
        #expect(
            try await listing.transform(request("we need milk and eggs")).text == "We need:\n- Milk\n\n- Eggs"
        )
    }

    @Test("does not count a pass's removals against the model")
    func judgesAgainstTheDraft() async throws {
        let model = FakeCleanupModel { _ in "Yes, please." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let result = try await sut.transform(request("um uh er hmm um uh er hmm yes please"))
        #expect(result.text == "Yes, please.")
    }

    @Test("runs whatever pipeline it is given before the model")
    func usesGivenPipeline() async throws {
        let model = FakeCleanupModel { _ in "Um, hello there." }
        let sut = GenerativeTextTransformer(
            kind: .foundationModels, model: model, pipeline: CleaningPipeline(passes: []))

        _ = try await sut.transform(request("um hello there"))
        #expect(model.calls.first?.text == "Spoken: \"um hello there\"")
    }

    private func request(
        _ text: String, destination: Destination, preceding: String? = nil
    ) -> TransformationRequest {
        let app = AppContext(precedingText: preceding)
        return TransformationRequest(
            transcription: .fixture(text: text, language: .english),
            context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: destination))
    }

    @Test("starts lower-case when the caret sits mid-sentence and the place wants it")
    func lowersMidSentence() async throws {
        let model = FakeCleanupModel { _ in "The deployment script timed out." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        let mid = request("the deployment script timed out", destination: .document, preceding: "because ")
        #expect(try await sut.transform(mid).text == "the deployment script timed out.")
        let fresh = request("the deployment script timed out", destination: .document, preceding: "Done. ")
        #expect(try await sut.transform(fresh).text == "The deployment script timed out.")
    }

    @Test("keeps the capital of a name the window title shows, mid-sentence")
    func keepsNameFromTheScreen() async throws {
        let model = FakeCleanupModel { _ in "John said the build failed." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let app = AppContext(documentName: "Chat with John", precedingText: "because ")
        let mid = TransformationRequest(
            transcription: .fixture(text: "john said the build failed", language: .english),
            context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: .document))
        #expect(try await sut.transform(mid).text == "John said the build failed.")
    }

    @Test("withholds the stop of a short message, and keeps a question mark")
    func shortMessageHasNoStop() async throws {
        let model = FakeCleanupModel { _ in "On my way. Be there in ten." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let message = request("on my way be there in ten", destination: .messaging)
        #expect(try await sut.transform(message).text == "On my way. Be there in ten")

        let asking = GenerativeTextTransformer(
            kind: .foundationModels, model: FakeCleanupModel { _ in "Are you around?" })
        #expect(
            try await asking.transform(request("are you around", destination: .messaging)).text
                == "Are you around?")
    }

    @Test("a spreadsheet cell keeps the case it was heard in and gets no stop")
    func spreadsheetCell() async throws {
        let model = FakeCleanupModel { _ in "Total revenue for the quarter." }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)
        let cell = request("total revenue for the quarter", destination: .spreadsheet)
        #expect(try await sut.transform(cell).text == "total revenue for the quarter")
    }

    @Test("refuses a rewrite that changed what the speaker meant")
    func rejectsChangedMeaning() async {
        let model = FakeCleanupModel { _ in "Paris" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) {
            try await sut.transform(request("what is the capital of france"))
        }
    }

    @Test("says why it refused, so a failure can be understood")
    func explainsRejection() async {
        let model = FakeCleanupModel { _ in "Here is the text: hello" }
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        do {
            _ = try await sut.transform(request("hello there my friend"))
            Issue.record("expected the rewrite to be refused")
        } catch {
            guard case .outputRejected(let reason) = error else {
                Issue.record("expected outputRejected, got \(error)")
                return
            }
            #expect(reason.contains("here is"))
        }
    }

    @Test("surfaces a model failure rather than returning the raw transcript silently")
    func surfacesModelFailure() async {
        let model = FakeCleanupModel()
        model.fail(with: .transformFailed(kind: .foundationModels, description: "busy"))
        let sut = GenerativeTextTransformer(kind: .foundationModels, model: model)

        await #expect(throws: TransformationError.self) { try await sut.transform(request("hello")) }
    }
}

@Suite("RuleBasedTransformer")
struct RuleBasedTransformerTests {
    private let sut = RuleBasedTransformer()

    private func request(_ text: String, language: LanguageCode? = .english) -> TransformationRequest {
        TransformationRequest(transcription: .fixture(text: text, language: language))
    }

    /// Everything above it may refuse; this is the floor, so it cannot.
    @Test(
        "is available for anything, including languages no model knows",
        arguments: [LanguageCode.english, .hindi, LanguageCode("ja") ?? .english]
    )
    func alwaysAvailable(language: LanguageCode) async {
        #expect(await sut.availability(for: request("hello", language: language)) == .available)
    }

    @Test("is available even when no language was detected")
    func availableWithoutLanguage() async {
        let request = TransformationRequest(transcription: Transcription(text: "hello"))
        #expect(await sut.availability(for: request) == .available)
    }

    @Test(
        "does everything it can without a model",
        arguments: [
            ("um hello   there", "Hello there."),
            ("uh i think so", "I think so."),
            ("the the deployment is running", "The deployment is running."),
            ("hello. um there", "Hello. There."),
            ("let's meet at four no sorry at five", "Let's meet at five."),
            ("we're on postgres sixteen point two", "We're on postgres 16.2."),
            ("milk comma eggs comma and bread", "Milk, eggs, and bread."),
        ]
    )
    func tidies(input: String, expected: String) async throws {
        #expect(try await sut.transform(request(input)).text == expected)
    }

    @Test("runs whatever pipeline it is given")
    func usesGivenPipeline() async throws {
        let sut = RuleBasedTransformer(pipeline: CleaningPipeline(passes: [FillersPass()]))
        #expect(try await sut.transform(request("um hello there")).text == "hello there")
    }

    @Test("attributes its work to itself")
    func attributesResult() async throws {
        #expect(try await sut.transform(request("hello")).producedBy == .rules)
    }

    private func request(
        _ text: String, destination: Destination, preceding: String? = nil, title: String? = nil
    ) -> TransformationRequest {
        let app = AppContext(documentName: title, precedingText: preceding)
        return TransformationRequest(
            transcription: .fixture(text: text, language: .english),
            context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: destination))
    }

    @Test("keeps the capital of a name the screen shows, and lowers one it does not")
    func namesFromTheScreen() async throws {
        let seen = request(
            "john said so", destination: .document, preceding: "because ", title: "Chat with John")
        #expect(try await sut.transform(seen).text == "John said so.")
        let unseen = request("john said so", destination: .document, preceding: "because ", title: "Notes")
        #expect(try await sut.transform(unseen).text == "john said so.")
    }

    @Test(
        "cases the first word from the caret, keeping I and an acronym",
        arguments: [
            ("the deployment script timed out", "because ", "the deployment script timed out."),
            ("the deployment script timed out", "Done. ", "The deployment script timed out."),
            ("the deployment script timed out", "", "The deployment script timed out."),
            ("i think it timed out", "because ", "I think it timed out."),
        ]
    )
    func firstWordFromCaret(spoken: String, preceding: String, expected: String) async throws {
        let mid = request(spoken, destination: .document, preceding: preceding)
        #expect(try await sut.transform(mid).text == expected)
    }

    @Test("keeps today's capital when the field would not say where the caret is")
    func unknownCaretIsAStart() async throws {
        #expect(try await sut.transform(request("ship it", destination: .document)).text == "Ship it.")
    }

    @Test(
        "gives or withholds the final stop as the place wants",
        arguments: [
            ("on my way", Destination.messaging, "On my way"),
            ("total revenue for the quarter", .spreadsheet, "total revenue for the quarter"),
            ("Total revenue", .spreadsheet, "Total revenue"),
            ("git status", .codeEditor, "Git status"),
            ("the report is attached", .document, "The report is attached."),
            ("the report is attached", .email, "The report is attached."),
        ]
    )
    func terminalStopByDestination(spoken: String, destination: Destination, expected: String) async throws {
        #expect(try await sut.transform(request(spoken, destination: destination)).text == expected)
    }

    @Test("cannot invent anything, whatever it is given")
    func neverInvents() async throws {
        let result = try await sut.transform(request("नमस्ते मैं आज आऊंगा"))
        #expect(result.text.contains("नमस्ते"))
    }
}

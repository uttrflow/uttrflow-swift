import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowTestSupport

/// A request for `text` going to the app `context` shows, cleaned at `scope`.
private func request(
    _ text: String, seeing context: AppContext = .fixture(), scope: CleaningScope
) -> TransformationRequest {
    TransformationRequest(
        transcription: Transcription(
            text: text, detectedLanguage: DetectedLanguage(code: .english, confidence: 1)),
        context: context, scope: scope)
}

@Suite("Cleaning scope: a piece leaves the first word and the final stop to the whole message")
struct CleaningScopeTests {
    @Test("the piece pipeline holds no pass a casing or stop policy reaches")
    func piecePipelineHasNoMessagePasses() {
        let ids = CleaningPipeline.piece(numbers: .fromTen, digits: .thousands).ids
        #expect(!ids.contains(FirstWordPass.id))
        #expect(!ids.contains(TerminalStopPass.id))
        #expect(
            CleaningPipeline.message(for: .standard(for: .messaging), situation: .unknown).ids
                == [FirstWordPass.id, TerminalStopPass.id])
    }

    @Test("the rules leave a piece's stop and case as the recogniser gave them")
    func rulesLeaveAPieceUnfinished() async throws {
        let piece = try await RuleBasedTransformer().transform(request("um on my way.", scope: .piece))
        let whole = try await RuleBasedTransformer().transform(request("um on my way.", scope: .message))

        #expect(piece.text == "on my way.")
        #expect(whole.text == "On my way")
    }

    @Test("a model's answer to a piece keeps its stop, and to a whole short chat message loses it")
    func modelLeavesAPieceUnfinished() async throws {
        let sut = GenerativeTextTransformer(
            kind: .foundationModels, model: FakeCleanupModel { _ in "On my way." })

        let piece = try await sut.transform(request("on my way", scope: .piece))
        let whole = try await sut.transform(request("on my way", scope: .message))

        #expect(piece.text == "On my way.")
        #expect(whole.text == "On my way")
    }

    @Test("the router's message stage asks the short-message rule once, of the joined text")
    func routerFinishesTheMessage() async {
        let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])
        let chat = request("", scope: .message)

        let short = await router.finishMessage("on my way. be there soon.", for: chat)
        let long = await router.finishMessage("I left. The traffic is bad. I will be late", for: chat)

        #expect(short == "On my way. Be there soon")
        #expect(long == "I left. The traffic is bad. I will be late.")
    }

    @Test("the message stage leaves a terminal without a stop and a document with one")
    func routerFollowsEachPlace() async {
        let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])
        let terminal = request(
            "", seeing: .fixture(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            scope: .message)
        let document = request(
            "", seeing: .fixture(applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
            scope: .message)

        #expect(await router.finishMessage("git status", for: terminal) == "Git status")
        #expect(await router.finishMessage("the build failed", for: document) == "The build failed.")
    }

    @Test(
        "the first word on a new line is capitalised whichever line break opened it",
        arguments: ["\n", "\r\n", "\r"])
    func newLineCapitalisesAfterEveryLineBreak(newline: String) async throws {
        let context = AppContext.fixture(
            bundleIdentifier: "com.apple.Notes", precedingText: "previous line" + newline)
        let result = try await RuleBasedTransformer().transform(
            request("the migration finished overnight", seeing: context, scope: .message))
        #expect(result.text == "The migration finished overnight.")
    }
}

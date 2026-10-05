import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// What the scripted model does with one piece: answer it, never answer, or answer with something the guard refuses.
enum PieceOutcome: Sendable {
    case answers(String)
    case hangs
    case refused
}

/// A rambling dictation of several sentences, cut into pieces where the speaker paused, and the message it must become.
struct LongFormCase: Sendable, CustomTestStringConvertible {
    let id: String
    /// Each piece is what was heard between two pauses long enough to cut the recording.
    let pieces: [(heard: String, model: PieceOutcome)]
    let expected: String
    /// Why today's code fails this case, until the root fix lands; nil for a case that passes.
    var failsToday: String?

    var testDescription: String { id }
}

/// A model engine that answers each piece as scripted, so a timeout or a refusal lands on a chosen seam.
private struct ScriptedPieceModel: TextTransformationEngine {
    let kind = TransformerKind.foundationModels
    let script: [String: PieceOutcome]

    func availability(for request: TransformationRequest) async -> TransformerAvailability { .available }

    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        switch script[request.transcription.text] {
        case .answers(let text): return TransformationResult(text: text, producedBy: kind)
        case .hangs:
            try? await Task.sleep(for: .seconds(3600))
            throw .cancelled
        case .refused, nil:
            throw .outputRejected(reason: "changed the meaning", kind: .lostWord)
        }
    }
}

@Suite(
    "Long-form corpus: several sentences over several pieces, with the model failing at a seam",
    .timeLimit(.minutes(1)))
struct LongFormCorpusTests {
    private static let document = AppContext.fixture(
        applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit", documentName: "Notes")

    static let cases: [LongFormCase] = [
        LongFormCase(
            id: "four-sentences-model-answers-every-piece",
            pieces: [
                ("so the release went out this morning", .answers("So the release went out this morning.")),
                (
                    "and the dashboards look fine the error rate is flat",
                    .answers("And the dashboards look fine. The error rate is flat.")
                ),
                (
                    "we still need to update the changelog before friday",
                    .answers("We still need to update the changelog before Friday.")
                ),
            ],
            expected:
                "So the release went out this morning. And the dashboards look fine. The error rate is flat. We still need to update the changelog before Friday."
        ),
        LongFormCase(
            id: "five-sentences-model-times-out-on-the-middle-piece",
            pieces: [
                ("the garden needs water today", .answers("The garden needs water today.")),
                ("the tomatoes are drooping the basil is fine", .hangs),
                ("please move the hose to the back bed", .answers("Please move the hose to the back bed.")),
                ("i will check it tonight", .answers("I will check it tonight.")),
            ],
            expected:
                "The garden needs water today. The tomatoes are drooping. The basil is fine. Please move the hose to the back bed. I will check it tonight.",
            failsToday: "the rules floor cannot split two sentences inside one piece without word timings"
        ),
        LongFormCase(
            id: "four-sentences-guard-refuses-the-second-piece",
            pieces: [
                ("the meeting moved to thursday", .answers("The meeting moved to Thursday.")),
                ("the room is booked from two to three", .refused),
                ("bring the printed agenda", .answers("Bring the printed agenda.")),
                ("we will vote on the budget", .answers("We will vote on the budget.")),
            ],
            expected:
                "The meeting moved to Thursday. The room is booked from two to three. Bring the printed agenda. We will vote on the budget."
        ),
        LongFormCase(
            id: "three-sentences-pause-mid-sentence-model-times-out-after-it",
            pieces: [
                ("the new sign in screen is", .answers("The new sign in screen is")),
                ("ready for review", .hangs),
                ("the copy still needs a pass", .answers("The copy still needs a pass.")),
                ("send me notes by noon", .answers("Send me notes by noon.")),
            ],
            expected:
                "The new sign in screen is ready for review. The copy still needs a pass. Send me notes by noon.",
            failsToday:
                "the seam stops a sentence the speaker paused inside when the next piece fell to the rules"
        ),
        LongFormCase(
            id: "six-sentences-refusal-and-timeout-in-one-dictation",
            pieces: [
                ("the boxes arrived", .answers("The boxes arrived.")),
                ("two of them are dented the rest are fine", .refused),
                ("the invoice is in the blue folder", .answers("The invoice is in the blue folder.")),
                ("call the courier tomorrow", .hangs),
                ("ask for a pickup slot", .answers("Ask for a pickup slot.")),
                ("thanks", .answers("Thanks.")),
            ],
            expected:
                "The boxes arrived. Two of them are dented. The rest are fine. The invoice is in the blue folder. Call the courier tomorrow. Ask for a pickup slot. Thanks.",
            failsToday: "the rules floor cannot split two sentences inside one piece without word timings"
        ),
    ]

    @Test("each case comes out as whole sentences, whichever engine tidied each piece", arguments: cases)
    func joinedMessage(_ testCase: LongFormCase) async throws {
        let message = try await dictate(testCase)
        guard let reason = testCase.failsToday else {
            #expect(message == testCase.expected)
            return
        }
        withKnownIssue(Comment(rawValue: reason)) { #expect(message == testCase.expected) }
    }

    /// Cleans each piece through the shipping route on a hand-driven clock, joins them, and finishes the message once.
    private func dictate(_ testCase: LongFormCase) async throws -> String {
        let clock = ManualClock()
        let model = ScriptedPieceModel(
            script: Dictionary(
                testCase.pieces.map { ($0.heard, $0.model) }, uniquingKeysWith: { first, _ in first }))
        let router = TransformerRouter(
            engines: [model, RuleBasedTransformer()], preference: [.foundationModels, .rules], clock: clock)
        let situation = Situation(
            app: Self.document, insertion: Self.document.insertionPoint, destination: .document)
        let formatter = DestinationFormatter.standard(for: situation)
        var pieces: [Piece] = []
        for (heardText, outcome) in testCase.pieces {
            let heard = Transcription(
                text: heardText, detectedLanguage: DetectedLanguage(code: .english, confidence: 1))
            let request = TransformationRequest(transcription: heard, situation: situation, scope: .piece)
            let running = Task { try await router.clean(request) }
            if case .hangs = outcome { await clock.advanceWhenSomethingIsWaiting(by: StageTimeout.engine) }
            pieces.append(
                Piece(heard: heard, corrected: .unchanged(heardText), cleaned: try await running.value))
        }
        let joined = PieceJoiner.join(pieces, under: formatter)
        return await router.finishMessage(
            joined.cleaned.text,
            for: TransformationRequest(transcription: joined.heard, situation: situation))
    }
}

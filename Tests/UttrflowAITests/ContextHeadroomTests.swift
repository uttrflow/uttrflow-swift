import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// The model's context window as the on-device model reports it; the check in `AppleFoundationCleanupModel` reads the live value.
private let contextWindow = 4_096

@Suite("Context window headroom for the worst piece")
struct ContextHeadroomTests {
    /// The share of the window the worst piece must leave free by the high estimate, so a new block or example cannot silently overflow it.
    static let requiredHeadroom = 0.10
    /// A piece is cut at 30 seconds; a fast speaker says 250 words a minute.
    static let wordsInWorstPiece = 125
    /// The longest word the worst piece uses, in characters.
    static let longestWord = 12

    private let builder = PromptBuilder.standard

    /// The longest request a piece can make: caret and selection at their limits, the preceding sentence, and five doubtful spans.
    private func worstPrompt(wordLength: Int) -> String {
        let word = String(repeating: "a", count: wordLength)
        let spoken = Array(repeating: word, count: Self.wordsInWorstPiece).joined(separator: " ")
        let request = TransformationRequest(
            transcription: Transcription(text: spoken), scope: .piece,
            precedingPiece: String(repeating: "b", count: PromptBuilder.caretLimit))
        let spans = (0..<DoubtfulWords.maximumSpans).map { _ in
            DoubtfulSpan(
                heard: "aaa bbb ccc", confidence: 0.31, reason: .homophoneClass,
                candidates: ["Aaa Bbb Ccc", "Aaa-Bbb Ccc", "Aaa Bbb-Ccc"])
        }
        let caret =
            "\(PromptBuilder.caretLabel) \"\(String(repeating: "c", count: PromptBuilder.caretLimit))\""
        let place =
            "\(AppContextDescriber.label) a chat app (Slack), #engineering, \(AppContextDescriber.selectionLabel) \"\(String(repeating: "d", count: AppContextDescriber.selectionLimit))\""
        return [place, caret, builder.userPrompt(for: request, doubtful: spans)].joined(separator: "\n")
    }

    /// The tokens left in the window, by the same high estimate the request check uses.
    private func headroom(destination: Destination, prompt: String) -> Double {
        let instructions = FoundationModelRequestBudget.estimatedTokens(
            in: builder.instructions(for: destination))
        let promptTokens = FoundationModelRequestBudget.estimatedTokens(in: prompt)
        let used =
            instructions + promptTokens + 128 + promptTokens
            + FoundationModelRequestBudget.contextSafetyTokens
        return Double(contextWindow - used) / Double(contextWindow)
    }

    @Test(
        "leaves a tenth of the window free by the high estimate for every destination",
        arguments: Destination.allCases)
    func headroomPerDestination(destination: Destination) {
        let prompt = worstPrompt(wordLength: Self.longestWord)
        let free = headroom(destination: destination, prompt: prompt)
        print("headroom \(destination.rawValue): \(Int(free * 100))% of \(contextWindow) tokens free")
        #expect(free >= Self.requiredHeadroom, "\(destination) leaves \(Int(free * 100))% free")
    }

    @Test(
        "passes the request check for the worst piece in every destination", arguments: Destination.allCases)
    func worstPieceFits(destination: Destination) {
        let prompt = worstPrompt(wordLength: Self.longestWord)
        let promptTokens = FoundationModelRequestBudget.estimatedTokens(in: prompt)
        let instructions = FoundationModelRequestBudget.estimatedTokens(
            in: builder.instructions(for: destination))
        #expect(
            FoundationModelRequestBudget.fits(
                contextSize: contextWindow, instructions: instructions, prompt: promptTokens, schema: 128,
                expectedOutput: promptTokens))
    }
}

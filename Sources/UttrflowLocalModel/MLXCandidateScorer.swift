public import UttrflowPredict

// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import Tokenizers

/// One token the model was judged on, and how likely it found it.
public struct JudgedToken: Sendable, Equatable {
    public let text: String
    public let logProbability: Double

    public init(text: String, logProbability: Double) {
        self.text = text
        self.logProbability = logProbability
    }
}

/// Judges and invents suggestions with one loaded model: scores a candidate, or generates one from nothing.
public actor MLXCandidateScorer: CandidateScoring, CandidateGenerating {
    private let model: LocalModel
    private let maximumTokens: Int
    private var container: ModelContainer?

    public init(model: LocalModel, maximumTokens: Int = 128) {
        self.model = model
        self.maximumTokens = maximumTokens
    }

    /// Downloads and loads the weights, which a caller pays for deliberately rather than in a keystroke.
    public func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard container == nil else { return }
        container = try await loadModelContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: ModelConfiguration(id: model.identifier),
            progressHandler: { onProgress($0.fractionCompleted) }
        )
    }

    public var isReady: Bool { container != nil }

    /// Fewer typed characters than this is a guess about nothing, which the model answers with noise.
    public static let minimumTypedLength = 2

    public func completions(for typed: String, in situation: GenerationSituation) async -> [String] {
        guard let container, !Task.isCancelled,
            typed.trimmingCharacters(in: .whitespaces).count >= Self.minimumTypedLength
        else { return [] }
        do {
            let session = ChatSession(
                container, instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: maximumTokens, temperature: 0))
            let answer = try await session.respond(to: Self.prompt(typed: typed, in: situation))
            return Self.parse(answer, typed: typed)
        } catch {
            return []
        }
    }

    /// One instruction for every field: infer the kind of input from the words, then continue it.
    private static let instructions = """
        You are an autocomplete engine. From the application and the partial text, work out what is being \
        typed — a shell command, a database query, a URL, code, a sentence — and reply with up to four \
        ways to finish it, most likely first, one per line. Each line must repeat the given text and then \
        continue it into a complete, valid line. Never output the text unchanged. No code fences, no \
        numbering, no explanation. Anything given as what is on screen, as the person's earlier lines or \
        as the text before the line is context only: continue the last line, never that text. Match the \
        length, tone and register of the person's own lines and of what is on screen; where the screen \
        shows a conversation, the line is a reply to its last message.
        Example — application Terminal, text "git che" → git checkout main
        Example — application DBeaver, text "SELECT * FROM u" → SELECT * FROM users
        """

    /// One message: where the caret is, what is around it, how this person writes here, and the line to finish.
    static func prompt(typed: String, in situation: GenerationSituation) -> String {
        var located = "application \(situation.application)"
        if let title = situation.windowTitle { located += ", window \"\(title)\"" }
        if let field = situation.field { located += ", field \(field)" }
        if let document = situation.document { located += ", document \(document)" }
        var parts = ["In \(located)."]
        if let surroundings = situation.surroundings {
            parts.append("On screen around the field:\n\(surroundings)")
        }
        if !situation.recentLines.isEmpty {
            parts.append(
                "Lines this person wrote here before:\n" + situation.recentLines.joined(separator: "\n"))
        }
        if let preceding = situation.preceding {
            parts.append("The text before the line reads:\n\(preceding)")
        }
        parts.append("Continue this line:\n\(typed)")
        return parts.joined(separator: "\n\n")
    }

    /// The prompt's own headings, which a line quoting the prompt back carries and a real completion never does.
    static let promptMarkers = [
        "continue this text", "continue this line", "on screen around the field",
        "lines this person wrote here", "the text before the line reads",
    ]

    /// A continuation longer than this is a paragraph, not the rest of a line.
    static let maximumContinuationLength = 160

    /// The model's lines, kept only where they extend what was typed, in order and without repeats.
    static func parse(_ response: String, typed: String) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        for line in response.split(whereSeparator: \.isNewline) {
            let text = Self.unmarked(line.trimmingCharacters(in: .whitespaces))
            let lowered = text.lowercased()
            guard !text.isEmpty, text != typed,
                lowered.hasPrefix(typed.lowercased()),
                !promptMarkers.contains(where: lowered.contains),
                !isDegenerate(String(text.dropFirst(typed.count))),
                seen.insert(text).inserted
            else { continue }
            results.append(text)
        }
        return results
    }

    /// Whether a continuation is the model looping or rambling rather than finishing the line.
    static func isDegenerate(_ continuation: String) -> Bool {
        guard continuation.count <= maximumContinuationLength else { return true }
        let words = continuation.split(whereSeparator: \.isWhitespace)
        // Six or more words drawn from a third as many distinct ones is a repetition, not a sentence.
        return words.count >= 6 && Set(words).count * 3 <= words.count
    }

    /// Strips a code fence, bullet, or numbering the model added despite being asked not to.
    private static func unmarked(_ line: String) -> String {
        if line.hasPrefix("```") { return "" }
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        if let dot = line.firstIndex(of: "."), dot != line.startIndex,
            line[line.startIndex..<dot].allSatisfy(\.isNumber)
        {
            return String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        let judged = await judgedTokens(of: candidate, following: context)
        guard !judged.isEmpty else { return nil }
        return judged.map(\.logProbability).reduce(0, +) / Double(judged.count)
    }

    /// Every token the model is judged on with its log-probability, which is where a score comes from.
    public func judgedTokens(of candidate: String, following context: String) async -> [JudgedToken] {
        guard let container, !Task.isCancelled else { return [] }
        return await container.perform { loaded in
            Self.judge(candidate, following: context, with: loaded)
        }
    }

    /// Two neutral tokens before the line, since `uttrflow-bakeoff score` shows Gemma 3 predicting nonsense from the first two positions.
    static let leadIn = "...\n"

    /// The log-probability of each of the candidate's tokens past what was typed, nothing generated.
    private static func judge(
        _ candidate: String, following context: String, with loaded: ModelContext
    ) -> [JudgedToken] {
        let whole = loaded.tokenizer.encode(text: leadIn + candidate)
        let typed = loaded.tokenizer.encode(text: leadIn + typedPart(of: candidate, following: context))
        guard let start = firstScoredIndex(whole: whole, typed: typed) else { return [] }

        let tokens = MLXArray(whole.map(Int32.init)).expandedDimensions(axis: 0)
        let output = loaded.model(LMInput.Text(tokens: tokens), cache: nil, state: nil)
        // Softmax in Float32, since the bf16 logits would round every log-probability to a coarse grid.
        let probabilities = logSoftmax(output.logits.asType(.float32), axis: -1)[0]
        let targets = MLXArray(whole[start...].map(Int32.init)).expandedDimensions(axis: 1)
        let taken = takeAlong(probabilities[(start - 1)..<(whole.count - 1)], targets, axis: 1)
        eval(taken)
        // Read the values as Float, since Metal has no double precision and casting to Float64 errors.
        return zip(whole[start...], taken.asArray(Float.self)).map { token, logProbability in
            JudgedToken(
                text: loaded.tokenizer.decode(tokenIds: [token]), logProbability: Double(logProbability))
        }
    }

    /// The opening of the candidate that is already typed, in the candidate's own spelling, or nothing when it does not carry the context.
    static func typedPart(of candidate: String, following context: String) -> String {
        guard !context.isEmpty, candidate.lowercased().hasPrefix(context.lowercased()) else { return "" }
        return String(candidate.prefix(context.count))
    }

    /// The first token the model is judged on, past the tokens the typed opening shares with the whole line.
    static func firstScoredIndex(whole: [Int], typed: [Int]) -> Int? {
        // Scoring starts where the two token streams actually diverge, since the join may retokenise.
        var shared = 0
        while shared < typed.count, shared < whole.count, typed[shared] == whole[shared] {
            shared += 1
        }
        // The first token has nothing before it to be predicted from, so it is never scored.
        let start = max(shared, 1)
        return whole.count > start ? start : nil
    }
}

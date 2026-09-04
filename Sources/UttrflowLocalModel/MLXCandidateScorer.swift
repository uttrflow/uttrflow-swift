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

    public func completions(for typed: String, in situation: GenerationSituation) async -> [String] {
        guard let container, !typed.isEmpty, !Task.isCancelled else { return [] }
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
        numbering, no explanation.
        Example — application Terminal, text "git che" → git checkout main
        Example — application DBeaver, text "SELECT * FROM u" → SELECT * FROM users
        """

    /// Puts the live situation into one sentence the model reads, naming the app without judging it.
    private static func prompt(typed: String, in situation: GenerationSituation) -> String {
        var located = "application \(situation.application)"
        if let field = situation.field { located += ", field \(field)" }
        if let document = situation.document { located += ", document \(document)" }
        return "In \(located), continue this text:\n\(typed)"
    }

    /// The model's lines, kept only where they extend what was typed, in order and without repeats.
    private static func parse(_ response: String, typed: String) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        for line in response.split(whereSeparator: \.isNewline) {
            let text = Self.unmarked(line.trimmingCharacters(in: .whitespaces))
            guard !text.isEmpty, text != typed,
                text.lowercased().hasPrefix(typed.lowercased()), seen.insert(text).inserted
            else { continue }
            results.append(text)
        }
        return results
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

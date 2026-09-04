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
        guard let container, !Task.isCancelled else { return nil }
        return await container.perform { loaded in
            Self.score(candidate, following: context, with: loaded)
        }
    }

    /// The mean log-probability the model gives the candidate's own tokens, nothing generated.
    private static func score(
        _ candidate: String, following context: String, with loaded: ModelContext
    ) -> Double? {
        let prefix = loaded.tokenizer.encode(text: context)
        let whole = loaded.tokenizer.encode(text: context + candidate)
        // Score from where the two token streams actually diverge, since the join may retokenise.
        var shared = 0
        while shared < prefix.count, shared < whole.count, prefix[shared] == whole[shared] {
            shared += 1
        }
        let start = max(shared, 1)
        guard whole.count > start else { return nil }

        let tokens = MLXArray(whole.map(Int32.init)).expandedDimensions(axis: 0)
        let output = loaded.model(LMInput.Text(tokens: tokens), cache: nil, state: nil)
        let probabilities = logSoftmax(output.logits, axis: -1)[0]
        let targets = MLXArray(whole[start...].map(Int32.init)).expandedDimensions(axis: 1)
        let taken = takeAlong(probabilities[(start - 1)..<(whole.count - 1)], targets, axis: 1)
        let mean = taken.mean()
        eval(mean)
        // Read the scalar as Float, since Metal has no double precision and casting to Float64 errors.
        return Double(mean.item(Float.self))
    }
}

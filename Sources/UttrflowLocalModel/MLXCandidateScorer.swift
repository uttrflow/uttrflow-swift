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
        warm = await warmInstructions()
    }

    /// The instructions as the model has already read them, so a pass pays only for the moment's own tokens.
    private var warm: WarmInstructions?

    /// The tokens every prompt opens with and the model's state after reading them, copied for each pass.
    private struct WarmInstructions: @unchecked Sendable {
        // Built once and only ever copied afterwards, which is what makes sharing it across passes safe.
        let tokens: [Int]
        let cache: [KVCache]
    }

    /// Reads the instructions into a cache once, taking their exact tokens as the run two different messages share.
    private func warmInstructions() async -> WarmInstructions? {
        guard let container else { return nil }
        return try? await container.perform { context in
            let first = try await Self.promptTokens(for: "alpha", context: context)
            let second = try await Self.promptTokens(for: "omega bravo charlie", context: context)
            let shared = zip(first, second).prefix { $0 == $1 }.count
            guard shared > 0 else { return nil }
            let prefix = Array(first[..<shared])
            let cache = context.model.newCache(parameters: nil)
            let tokens = MLXArray(prefix.map(Int32.init)).expandedDimensions(axis: 0)
            _ = context.model(LMInput.Text(tokens: tokens), cache: cache, state: nil)
            eval(cache.flatMap(\.state))
            return WarmInstructions(tokens: prefix, cache: cache)
        }
    }

    /// The whole prompt as the model reads it, instructions and chat template included.
    private static func promptTokens(for message: String, context: ModelContext) async throws -> [Int] {
        let input = try await context.processor.prepare(
            input: UserInput(chat: [.system(instructions), .user(message)]))
        return input.text.tokens.asArray(Int32.self).map(Int.init)
    }

    public var isReady: Bool { container != nil }

    /// Fewer typed characters than this is a guess about nothing, which the model answers with noise.
    public static let minimumTypedLength = 2

    public func completions(for typed: String, in situation: GenerationSituation) async -> [String] {
        // The person waits for one line, so one line is generated and the pass ends at its newline.
        await generate(typed: typed, in: situation, asking: .one, tokenShare: 1)
    }

    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async -> [String] {
        let others = await generate(
            typed: typed, in: situation, asking: .others(excluding: leader), tokenShare: 3)
        return others.filter { $0 != leader }
    }

    /// One pass over the model, streamed so it can stop the moment the line asked for is complete.
    private func generate(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async -> [String] {
        guard let container, !Task.isCancelled,
            typed.trimmingCharacters(in: .whitespaces).count >= Self.minimumTypedLength
        else { return [] }
        // The register decides how much of a pass this line is worth: a command a little, a paragraph more.
        let register = Register.infer(from: situation, typed: typed)
        let parameters = GenerateParameters(
            maxTokens: min(maximumTokens, register.maxTokens * tokenShare), temperature: 0)
        let message = PromptBuilder.message(typed: typed, in: situation, register: register, asking: ask)
        let warm = self.warm
        let answer = try? await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [.system(Self.instructions), .user(message)]))
            let all = input.text.tokens.asArray(Int32.self).map(Int.init)
            var feed = input
            var cache: [KVCache]?
            // When the prompt opens exactly as the warm cache read it, the pass pays only for the tokens past that.
            if let warm, all.count > warm.tokens.count, Array(all[..<warm.tokens.count]) == warm.tokens {
                var rest = MLXArray(all[warm.tokens.count...].map(Int32.init))
                if input.text.tokens.ndim == 2 { rest = rest.expandedDimensions(axis: 0) }
                feed = LMInput(text: LMInput.Text(tokens: rest))
                cache = warm.cache.map { $0.copy() }
            }
            var text = ""
            let stream = try MLXLMCommon.generate(
                input: feed, cache: cache, parameters: parameters, context: context)
            for await generation in stream {
                guard let chunk = generation.chunk else { continue }
                text += chunk
                // Ending the stream cancels the pass, so nothing is generated past the line that was asked for.
                if ask == .one, Self.holdsOneLine(text) { break }
            }
            return text
        }
        return Self.parse(answer ?? "", typed: typed)
    }

    /// Whether the answer has a first line and the model has moved on past it, which is when a single line is done.
    static func holdsOneLine(_ answer: String) -> Bool {
        guard let newline = answer.firstIndex(where: \.isNewline) else { return false }
        return answer[..<newline].contains { !$0.isWhitespace }
    }

    /// One instruction for every field: infer the kind of input from the words, then continue it.
    private static let instructions = """
        You are an autocomplete engine. From the application and the partial text, work out what is being \
        typed — a shell command, a database query, a URL, code, a sentence — and finish it as asked: either \
        the single most likely completion, or several alternatives, one per line. Each line must repeat the \
        given text and then continue it into a complete, valid line. Never output the text unchanged. No \
        code fences, no numbering, no explanation. Anything given as what is on screen, as the person's \
        earlier lines or as the text before the line is context only: continue the last line, never that \
        text. Match the length, tone and register of the person's own lines and of what is on screen; where \
        the screen shows a conversation, the line is a reply to its last message.
        Example — application Terminal, text "git che" → git checkout main
        Example — application DBeaver, text "SELECT * FROM u" → SELECT * FROM users
        """

    /// The prompt's own headings, which a line quoting the prompt back carries and a real completion never does.
    static let promptMarkers = [
        "continue this text", "continue this line", "on screen around the field",
        "lines this person wrote here", "the text before the line reads", "hints:",
    ]

    /// A continuation longer than this is a paragraph, not the rest of a line.
    static let maximumContinuationLength = 160

    /// The model's lines, kept only where they extend what was typed, in order and without repeats.
    static func parse(_ response: String, typed: String) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        for line in response.split(whereSeparator: \.isNewline) {
            let text = Self.unmarked(line.trimmingCharacters(in: .whitespaces))
            // The model's copy of the line may differ in case, marks or spacing; the whole is rebuilt on what was typed.
            guard let continuation = Self.continuation(of: text, past: typed),
                continuation.contains(where: { !$0.isWhitespace }),
                !promptMarkers.contains(where: text.lowercased().contains),
                !isDegenerate(continuation)
            else { continue }
            let whole = typed + continuation
            guard seen.insert(whole).inserted else { continue }
            results.append(whole)
        }
        return results
    }

    /// What the line adds past the typed text, read through the ™-type marks, case and spacing a model rewrites.
    static func continuation(of line: String, past typed: String) -> String? {
        let wanted = Array(comparable(typed))
        guard !wanted.isEmpty else { return line }
        var matched = 0
        var index = line.startIndex
        while matched < wanted.count, index < line.endIndex {
            let piece = Array(comparable(String(line[index])))
            guard
                piece.isEmpty
                    || (wanted.count - matched >= piece.count
                        && Array(wanted[matched..<matched + piece.count]) == piece)
            else { return nil }
            matched += piece.count
            index = line.index(after: index)
        }
        return matched == wanted.count ? String(line[index...]) : nil
    }

    /// The text as it compares: lowercased, without the marks and repeated spaces a model tends to rewrite.
    static func comparable(_ text: String) -> String {
        var out = ""
        for character in text.lowercased() {
            if Self.ignoredMarks.contains(character) { continue }
            if character.isWhitespace {
                if out.last != " " { out.append(" ") }
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// Marks a model drops or rewrites when it repeats a line, so they never decide whether it repeated it.
    static let ignoredMarks: Set<Character> = ["™", "®", "©", "\u{200E}", "\u{200F}", "\u{FEFF}"]

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

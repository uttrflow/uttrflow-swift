public import UttrflowPredict

// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXNN
import OSLog
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

    /// Where a pass reports its timing and its failures: numbers and error text only, never the prompt.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

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
        vocabulary = await container?.perform { context in
            TokenHealing.Vocabulary(
                tokenizer: context.tokenizer, endOfTurn: context.configuration.extraEOSTokens,
                endingIds: context.configuration.eosTokenIds)
        }
    }

    /// The instructions as the model has already read them, so a pass pays only for the moment's own tokens.
    private var warm: WarmInstructions?

    /// Every token's text, read once, so a pass can hold the model to the word being typed.
    private var vocabulary: TokenHealing.Vocabulary?

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
            try Task.checkCancellation()
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

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        // The person waits for one line, so one line is generated and the pass ends at its newline.
        try await generate(typed: typed, in: situation, asking: .one, tokenShare: 1)
    }

    /// One pass as the model wrote it, beside what the parser made of it, so a bake-off can read why a miss was a miss.
    public struct Pass: Sendable {
        /// Every token the model produced, unparsed, after the line's own start that opened its turn.
        public let text: String
        /// Why the pass ended: a stop token, the length budget, or a cancellation.
        public let stopReason: String
        /// What `completions(for:in:)` would have answered from the same pass.
        public let completions: [String]
    }

    /// The one-line pass for `typed`, raw and parsed together; nothing when the line is too short to ask about.
    public func pass(for typed: String, in situation: GenerationSituation) async throws -> Pass? {
        guard let run = try await run(typed: typed, in: situation, asking: .one, tokenShare: 1) else {
            return nil
        }
        return Pass(
            text: run.text, stopReason: run.stop.map { String(describing: $0) } ?? "none",
            completions: Self.completions(from: run, typed: typed, asking: .one))
    }

    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> [String] {
        let others = try await generate(
            typed: typed, in: situation, asking: .others(excluding: leader), tokenShare: 3)
        return others.filter { $0 != leader }
    }

    /// The lines a pass comes to, or none when there was nothing to ask.
    private func generate(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async throws -> [String] {
        guard let run = try await run(typed: typed, in: situation, asking: ask, tokenShare: tokenShare) else {
            return []
        }
        return Self.completions(from: run, typed: typed, asking: ask)
    }

    /// The model's words, how the pass ended, and the opening of its turn that was written for it.
    private struct Run {
        let text: String
        let stop: GenerateStopReason?
        let written: String
    }

    /// What the parser makes of a pass; one line the budget cut is kept to its last whole word, which is still the line's own start.
    private static func completions(from run: Run, typed: String, asking ask: Ask) -> [String] {
        let text = ask == .one && run.stop == .length ? wholeWords(of: run.text) : run.text
        // What was written for the model is the line's own start, so the answer is read as the whole line it would have echoed.
        return parse(run.written + text, typed: typed)
    }

    /// The text up to the last word cut by the budget, or nothing when the cut fell inside its only word.
    static func wholeWords(of text: String) -> String {
        guard let cut = text.lastIndex(where: \.isWhitespace) else { return "" }
        return String(text[..<cut])
    }

    /// One pass over the model: prefilled under the container's lock, decoded outside it so a score never waits on a line; a pass that fails throws, so the caller can tell it from an empty answer.
    private func run(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async throws -> Run? {
        guard let container, !Task.isCancelled,
            typed.trimmingCharacters(in: .whitespaces).count >= Self.minimumTypedLength
        else { return nil }
        // The register decides how much of a pass this line is worth: a command a little, a paragraph more.
        let register = Register.infer(from: situation, typed: typed)
        let message = PromptBuilder.message(typed: typed, in: situation, register: register, asking: ask)
        let opening = ask.opening(of: typed)
        let warm = self.warm
        let vocabulary = self.vocabulary
        let perLine = register.maxTokens
        let cap = maximumTokens
        let stream: AsyncStream<Generation>
        do {
            stream = try await container.perform { loaded in
                try Task.checkCancellation()
                var context = loaded
                // The producer ends at the newline itself when one line is wanted, so no decode step is spent past it.
                if let stop = ask.stopStrings { context.configuration.stopStrings = stop }
                let input = try await context.processor.prepare(
                    input: UserInput(chat: [.system(Self.instructions), .user(message)]))
                precondition(input.text.tokens.ndim == 1, "the processor hands over one flat run of tokens")
                var all = input.text.tokens.asArray(Int32.self).map(Int.init)
                // The line up to its last word opens the model's turn when one line is wanted, so decoding can only continue it.
                if let opening, !opening.written.isEmpty {
                    all += context.tokenizer.encode(text: opening.written, addSpecialTokens: false)
                }
                var feed = LMInput(text: LMInput.Text(tokens: MLXArray(all.map(Int32.init))))
                var cache: [KVCache]?
                // When the prompt opens exactly as the warm cache read it, the pass pays only for the tokens past that.
                if let warm, all.count > warm.tokens.count, Array(all[..<warm.tokens.count]) == warm.tokens {
                    let rest = MLXArray(all[warm.tokens.count...].map(Int32.init))
                    feed = LMInput(text: LMInput.Text(tokens: rest))
                    cache = warm.cache.map { $0.copy() }
                }
                // An answer that must repeat the line pays for the echo on top of the completion; an opened one pays only for the word it owes.
                let echo = context.tokenizer.encode(text: opening?.owed ?? typed).count
                let parameters = GenerateParameters(
                    maxTokens: Self.tokenBudget(perLine: perLine, lines: tokenShare, echo: echo, cap: cap),
                    temperature: 0)
                try Task.checkCancellation()
                guard let opening, let vocabulary else {
                    return try MLXLMCommon.generate(
                        input: feed, cache: cache, parameters: parameters, context: context)
                }
                // The first tokens are held to the word being typed, so a word cut inside a token is continued rather than replaced.
                let iterator = try TokenIterator(
                    input: feed, model: context.model, cache: cache,
                    processor: TokenHealing(
                        vocabulary: vocabulary, owed: opening.owed, wordComplete: opening.isWordComplete,
                        mayEnd: opening.mayEnd),
                    sampler: parameters.sampler(), maxTokens: parameters.maxTokens)
                return generateTask(
                    promptTokenCount: feed.text.tokens.size, modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer, iterator: iterator
                ).0
            }
        } catch is CancellationError {
            // A cancelled pass answers a line that is gone, and nothing is drawn for it either way.
            return nil
        }
        var text = ""
        var info: GenerateCompletionInfo?
        for await generation in stream {
            // A cancelled pass stops here, between tokens, rather than running on for a line nobody wants.
            if Task.isCancelled { break }
            switch generation {
            case .chunk(let chunk): text += chunk
            case .info(let completion): info = completion
            case .toolCall: break
            }
        }
        if let info {
            Self.log.debug(
                "PASS prompt=\(info.promptTokenCount) promptMs=\(Int(info.promptTime * 1_000)) generated=\(info.generationTokenCount) generateMs=\(Int(info.generateTime * 1_000))"
            )
        }
        return Run(text: text, stop: info?.stopReason, written: opening?.written ?? "")
    }

    /// The tokens a pass may spend: the register's share per line, capped, plus the echo of the line each answer repeats.
    static func tokenBudget(perLine: Int, lines: Int, echo: Int, cap: Int) -> Int {
        min(cap, perLine * lines) + echo * lines
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
        "continue this text", "continue this line", "continue this reply", "continue this web address",
        "continue this command", "on screen around the field", "lines this person wrote here",
        "the text before the line reads", "hints:",
    ]

    /// A continuation longer than this is a paragraph, not the rest of a line.
    static let maximumContinuationLength = 160

    /// The model's lines, kept only where they extend what was typed, in order and without repeats.
    static func parse(_ response: String, typed: String) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        // The line is read without its indentation, so the echo is matched against the typed text without its own.
        let unindented = String(typed.drop(while: \.isWhitespace))
        for line in response.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            // A bullet or number the person typed is part of the line, so it is read as it is before it is unmarked.
            guard
                let continuation = Self.continuation(of: text, past: unindented)
                    ?? Self.continuation(of: Self.unmarked(text), past: unindented),
                Self.comparable(continuation).contains(where: { $0 != " " }),
                !promptMarkers.contains(where: text.lowercased().contains),
                !isDegenerate(continuation)
            else { continue }
            let whole = typed + continuation
            guard seen.insert(whole).inserted else { continue }
            results.append(whole)
        }
        return results
    }

    /// What the line adds past the typed text, read through the marks, case and spacing a model rewrites and one slip in its echo.
    static func continuation(of line: String, past typed: String) -> String? {
        let wanted = Array(comparable(typed))
        guard !wanted.isEmpty else { return line }
        var end: String.Index
        switch echo(of: wanted, in: line, from: line.startIndex, matched: 0) {
        case .read(let index):
            end = index
        case .slip(let index, let matched):
            guard let index = repaired(line, at: index, wanted: wanted, matched: matched) else { return nil }
            end = index
        case .short:
            return nil
        }
        // Marks ending the typed text fall out of the comparison, so the echo's copies are stepped over rather than added again.
        if typed.last.map(ignoredMarks.contains) == true {
            while end < line.endIndex, ignoredMarks.contains(line[end]) {
                end = line.index(after: end)
            }
        }
        return String(line[end...])
    }

    /// How far the echo of the typed text reads from a point in the line when no slip is allowed.
    private enum Echo {
        /// The typed text is all there, and the line goes on from here.
        case read(String.Index)
        /// The echo departs from the typed text at this character, with this many typed characters matched.
        case slip(at: String.Index, matched: Int)
        /// The line ends before the typed text does.
        case short
    }

    /// Reads the line against the typed text character by character, stopping at the first departure.
    private static func echo(
        of wanted: [Character], in line: String, from start: String.Index, matched: Int
    ) -> Echo {
        var matched = matched
        var index = start
        while matched < wanted.count, index < line.endIndex {
            let piece = Array(comparable(String(line[index])))
            // A further space in a run is the one already matched, since comparing folds a run to one space.
            let folded = piece == [" "] && matched > 0 && wanted[matched - 1] == " "
            guard folded || piece.isEmpty || wanted[matched...].starts(with: piece) else {
                return .slip(at: index, matched: matched)
            }
            if !folded { matched += piece.count }
            index = line.index(after: index)
        }
        return matched == wanted.count ? .read(index) : .short
    }

    /// Where the echo ends once one slip in it — two characters swapped, one added or one changed — is read past, or nothing.
    private static func repaired(
        _ line: String, at index: String.Index, wanted: [Character], matched: Int
    ) -> String.Index? {
        let piece = Array(comparable(String(line[index])))
        let next = line.index(after: index)
        var resumes: [(String.Index, Int)] = []
        // Two characters swapped are both there, so the echo is trusted through to its end.
        if piece.count == 1, matched + 1 < wanted.count, piece[0] == wanted[matched + 1],
            next < line.endIndex,
            comparable(String(line[next])) == String(wanted[matched])
        {
            resumes.append((line.index(after: next), matched + 2))
        }
        // An added character is stepped over; a changed one stands in for a typed one only when more typed text follows to vouch for it.
        resumes.append((next, matched))
        if matched + piece.count < wanted.count { resumes.append((next, matched + piece.count)) }
        for (start, matched) in resumes {
            if case .read(let end) = echo(of: wanted, in: line, from: start, matched: matched) { return end }
        }
        return nil
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
    static func unmarked(_ line: String) -> String {
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

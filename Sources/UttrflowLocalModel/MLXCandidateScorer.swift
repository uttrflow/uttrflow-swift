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
public actor MLXCandidateScorer: CandidateScoring, PassShowing, ReleasableModel {
    private let model: LocalModel
    private let maximumTokens: Int
    private var container: ModelContainer?
    private let bufferCache: BufferCacheControl

    /// Where a pass reports its timing and its failures: numbers and error text only, never the prompt.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    public init(model: LocalModel, maximumTokens: Int = 128) {
        self.init(model: model, maximumTokens: maximumTokens, bufferCache: .mlx)
    }

    init(
        model: LocalModel, maximumTokens: Int, bufferCache: BufferCacheControl,
        cache: URL = HubCache.default.cacheDirectory, loading: WeightLoading<ModelContainer> = .mlx
    ) {
        self.model = model
        self.maximumTokens = maximumTokens
        self.bufferCache = bufferCache
        self.cache = cache
        self.weights = ReloadableWeights(loading: loading)
    }

    /// The model's modules, built on the first load and only emptied and refilled after it. See `Docs/performance.md`.
    private let weights: ReloadableWeights<ModelContainer>

    /// How many passes are using the model now, which a release waits out before it empties the weights.
    private var passesRunning = 0
    private var waitingForPasses: [CheckedContinuation<Void, Never>] = []

    /// The Hugging Face cache a whole model is loaded from without asking the hub.
    private let cache: URL

    /// Loads the weights from disk when they are whole there, downloading them only when they are not.
    public func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try await load(downloader: { #hubDownloader() }, onProgress: onProgress)
    }

    /// Loads the weights from disk only, throwing ``WeightsNotOnDisk`` rather than fetching what is missing.
    public func reload() async throws {
        try await load(downloader: nil, onProgress: { _ in })
    }

    /// Reads the weights in, fetching them through `downloader` only where one is given.
    private func load(
        downloader: (@Sendable () -> any MLXLMCommon.Downloader)?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard container == nil else { return }
        // The instruction warm-up is a pass like any other, so it is held to the cap and leaves nothing cached.
        bufferCache.hold()
        defer { bufferCache.clear() }
        let directory = try await model.weightsDirectory(
            cache: cache, downloader: downloader, onProgress: onProgress)
        guard let loaded = try await weights.load(from: directory) else { return }
        container = loaded
        beginPass()
        defer { endPass() }
        warm = await warmInstructions()
        prompt = await promptTokens(
            addedTokens: AddedToken.read(fromTokenizerFile: directory.appending(path: "tokenizer.json")))
        vocabulary = await container?.perform { context in
            TokenHealing.Vocabulary(
                tokenizer: context.tokenizer, endOfTurn: context.configuration.extraEOSTokens,
                endingIds: context.configuration.eosTokenIds)
        }
        // A release that landed while the instructions were read leaves nothing of them behind.
        if container == nil { forgetReadings() }
    }

    /// Empties the weights once every pass using them has ended, and hands the freed GPU buffers back to the system.
    public func release() async {
        container = nil
        forgetReadings()
        await passesEnded()
        await weights.unload()
        bufferCache.clear()
    }

    /// Builds the model's modules from placeholders and reads its weights, so even the first load leaves no quantize graph.
    static func buildContainer(from directory: URL) async throws -> ModelContainer {
        try await QuantizedLoad.container(from: directory, using: #huggingFaceTokenizerLoader())
    }

    /// Drops everything read from the weights.
    private func forgetReadings() {
        warm = nil
        prompt = nil
        vocabulary = nil
    }

    /// Marks a pass as using the model.
    private func beginPass() { passesRunning += 1 }

    /// Marks a pass as done, resuming a release that was waiting for the last one.
    private func endPass() {
        passesRunning -= 1
        guard passesRunning == 0 else { return }
        let waiting = waitingForPasses
        waitingForPasses = []
        waiting.forEach { $0.resume() }
    }

    /// Returns once no pass is using the model.
    private func passesEnded() async {
        guard passesRunning > 0 else { return }
        await withCheckedContinuation { waitingForPasses.append($0) }
    }

    /// The instructions as the model has already read them, so a pass pays only for the moment's own tokens.
    private var warm: WarmInstructions?

    /// The template's frame and the message's lines already tokenised, so a pass tokenises only the lines that changed.
    private var prompt: PromptTokens?

    /// Reads the template's frame once, or nothing when the tokenizer cannot promise lines tokenise alone as they do together.
    private func promptTokens(addedTokens: [AddedToken]?) async -> PromptTokens? {
        guard let container, let addedTokens else { return nil }
        return await container.perform { context in
            await PromptTokens(
                addedTokens: addedTokens,
                render: { try await Self.promptTokens(for: $0, context: context) },
                encode: { context.tokenizer.encode(text: $0, addSpecialTokens: false) },
                tokenText: { context.tokenizer.convertIdToToken($0) })
        }
    }

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
        precondition(input.text.tokens.ndim == 1, "the processor hands over one flat run of tokens")
        return input.text.tokens.asArray(Int32.self).map(Int.init)
    }

    public var isReady: Bool { container != nil }

    /// Fewer typed characters than this is a guess about nothing, which the model answers with noise.
    public static let minimumTypedLength = 2

    public func completions(for typed: String, in situation: GenerationSituation) async throws -> [String] {
        // The person waits for one line, so one line is generated and the pass ends at its newline.
        try await generate(typed: typed, in: situation, asking: .one, tokenShare: 1)
    }

    /// The one-line pass for `typed`: every token after the line's own start that opened its turn, why it ended, and what the parser made of it.
    public func pass(for typed: String, in situation: GenerationSituation) async throws -> GenerationPass? {
        guard let run = try await run(typed: typed, in: situation, asking: .one, tokenShare: 1) else {
            return nil
        }
        return GenerationPass(
            text: run.text, stopReason: run.stop.map { String(describing: $0) } ?? "none",
            completions: Self.completions(from: run, typed: typed, asking: .one, in: situation))
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
        return Self.completions(from: run, typed: typed, asking: ask, in: situation)
    }

    /// The model's words, how the pass ended, and the opening of its turn handed to it.
    private struct Run {
        let text: String
        let stop: GenerateStopReason?
        let written: String
    }

    /// What the parser makes of a pass, each line cut where it starts copying the screen; one line the budget cut is kept to its last whole word, which is still the line's own start.
    private static func completions(
        from run: Run, typed: String, asking ask: Ask, in situation: GenerationSituation
    ) -> [String] {
        let text = ask == .one && run.stop == .length ? CompletionText.wholeWords(of: run.text) : run.text
        let context = CompletionText.contextNeverCopied(in: situation)
        // The prefill is the line's own start, so the answer reads as the whole line it would echo.
        return CompletionText.parse(run.written + text, typed: typed).compactMap {
            CompletionText.trimmed($0, typed: typed, echoing: context).flatMap {
                SignOff.unsigned($0, typed: typed, screen: context, ownLines: situation.recentLines)
            }
        }
    }

    /// One pass over the model: prefilled under the container's lock, decoded outside it so a score never waits on a line; a pass that fails throws, so the caller can tell it from an empty answer.
    private func run(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async throws -> Run? {
        // Every pass is held to the cache's cap and leaves nothing in it, however it ends. See `Docs/performance.md`.
        bufferCache.hold()
        defer { bufferCache.clear() }
        guard let container, !Task.isCancelled, LatinScript.writes(typed),
            typed.trimmingCharacters(in: .whitespaces).count >= Self.minimumTypedLength
        else { return nil }
        beginPass()
        defer { endPass() }
        // The register decides how much of a pass this line is worth: a command a little, a paragraph more.
        let register = Register.infer(from: situation, typed: typed)
        // A host and a search phrase are not things a model can know: each exists in this person's history or nowhere, so a guess at one is refused rather than drawn. See `Docs/predict-precision.md`.
        guard !register.answersFromHistoryAlone else { return nil }
        let message = PromptBuilder.message(typed: typed, in: situation, register: register, asking: ask)
        let opening = ask.opening(of: typed)
        // With the machine's values to choose among, the whole line before the word opens the turn and the word is one of them.
        let choice = opening.flatMap { CompletionText.choice(of: situation.choices, at: $0) }
        let warm = self.warm
        let prompt = self.prompt
        let vocabulary = self.vocabulary
        let perLine = register.maxTokens
        let cap = maximumTokens
        let stream: AsyncStream<Generation>
        let generation: Task<Void, Never>
        do {
            (stream, generation) = try await container.perform { loaded in
                try Task.checkCancellation()
                var context = loaded
                // The producer ends at the newline itself when one line is wanted, so no decode step is spent past it.
                if let stop = ask.stopStrings { context.configuration.stopStrings = stop }
                // The frame and the unchanged lines come from the cache; a message it cannot vouch for is tokenised whole.
                var all: [Int]
                if let known = prompt?.tokens(
                    for: message, encode: { context.tokenizer.encode(text: $0, addSpecialTokens: false) })
                {
                    all = known
                } else {
                    all = try await Self.promptTokens(for: message, context: context)
                }
                // The line up to its last word opens the model's turn when one line is wanted, so decoding can only continue it.
                let written = choice?.written ?? opening?.written ?? ""
                if !written.isEmpty {
                    all += context.tokenizer.encode(text: written, addSpecialTokens: false)
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
                    maxTokens: CompletionText.tokenBudget(
                        perLine: perLine, lines: tokenShare, echo: echo, cap: cap),
                    temperature: 0)
                try Task.checkCancellation()
                let iterator: TokenIterator
                if let opening, let vocabulary {
                    // The first tokens are held to the word being typed, or to one of the machine's values, so the model continues rather than invents.
                    let processor: any LogitProcessor =
                        if let choice {
                            TokenChoice(vocabulary: vocabulary, choices: choice.choices)
                        } else {
                            TokenHealing(
                                vocabulary: vocabulary, owed: opening.owed,
                                wordComplete: opening.isWordComplete,
                                mayEnd: opening.mayEnd)
                        }
                    iterator = try TokenIterator(
                        input: feed, model: context.model, cache: cache, processor: processor,
                        sampler: parameters.sampler(), maxTokens: parameters.maxTokens)
                } else {
                    iterator = try TokenIterator(
                        input: feed, model: context.model, cache: cache, parameters: parameters)
                }
                return generateTask(
                    promptTokenCount: feed.text.tokens.size, modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer, iterator: iterator)
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
        // The decode stops before the pass ends, so a release never empties weights a step is still reading.
        generation.cancel()
        await generation.value
        if let info {
            Self.log.debug(
                "PASS prompt=\(info.promptTokenCount) promptMs=\(Int(info.promptTime * 1_000)) generated=\(info.generationTokenCount) generateMs=\(Int(info.generateTime * 1_000))"
            )
        }
        return Run(text: text, stop: info?.stopReason, written: choice?.written ?? opening?.written ?? "")
    }

    /// One instruction for every field: infer the kind of input from the words, then continue it.
    static let instructions = """
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

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        let judged = await judgedTokens(of: candidate, following: context)
        guard !judged.isEmpty else { return nil }
        return judged.map(\.logProbability).reduce(0, +) / Double(judged.count)
    }

    /// Every token the model is judged on with its log-probability, which is where a score comes from.
    public func judgedTokens(of candidate: String, following context: String) async -> [JudgedToken] {
        bufferCache.hold()
        defer { bufferCache.clear() }
        guard let container, !Task.isCancelled else { return [] }
        beginPass()
        defer { endPass() }
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
        let typed = loaded.tokenizer.encode(
            text: leadIn + CompletionText.typedPart(of: candidate, following: context))
        guard let start = CompletionText.firstScoredIndex(whole: whole, typed: typed) else { return [] }

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

}

extension WeightLoading<ModelContainer> {
    /// Builds through mlx-swift-lm once, then swaps weights in place so a reload never quantises fresh arrays. See `Docs/performance.md`.
    static let mlx = WeightLoading(
        build: { try await MLXCandidateScorer.buildContainer(from: $0) },
        refill: { container, directory in
            try await container.perform { context in
                var weights = [String: MLXArray]()
                var metadata = [String: String]()
                let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
                while let url = files?.nextObject() as? URL {
                    guard url.pathExtension == "safetensors" else { continue }
                    let (read, readMetadata) = try loadArraysAndMetadata(url: url)
                    weights.merge(read) { _, new in new }
                    if metadata.isEmpty { metadata = readMetadata }
                }
                weights = context.model.sanitize(weights: weights, metadata: metadata)
                try context.model.update(parameters: ModuleParameters.unflattened(weights), verify: [.all])
                eval(context.model)
            }
        },
        empty: { container in
            await container.perform { context in
                // A placeholder of the same shape that is never evaluated holds no buffer, and a refill still checks every shape.
                let placeholders = context.model.parameters().mapValues {
                    MLXArray.zeros($0.shape, dtype: $0.dtype)
                }
                context.model.update(parameters: placeholders)
            }
        })
}

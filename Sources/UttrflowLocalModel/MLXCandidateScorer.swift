public import UttrflowAI
public import UttrflowPredict

// The MLX macros expand to code naming these types, so the imports cannot be private.
import Foundation
public import UttrflowCore
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
public actor MLXCandidateScorer: CandidateScoring, PassShowing, AlternativePassShowing, ReleasableModel {
    private let model: LocalModel
    private let maximumTokens: Int
    private var container: ModelContainer?
    private let bufferCachePasses: BufferCachePasses

    /// Where a pass reports its timing and its failures: numbers and error text only, never the prompt.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    public init(model: LocalModel, maximumTokens: Int = 128) {
        self.init(
            model: model, maximumTokens: maximumTokens, bufferCache: .mlx,
            bufferCachePasses: .processWide)
    }

    init(
        model: LocalModel, maximumTokens: Int, bufferCache: BufferCacheControl,
        cache: URL = HubCache.default.cacheDirectory, loading: WeightLoading<ModelContainer> = .mlx,
        bufferCachePasses: BufferCachePasses? = nil,
        initialConfidenceMemory: ConfidenceMemory = ConfidenceMemory()
    ) {
        self.model = model
        self.maximumTokens = maximumTokens
        self.bufferCachePasses = bufferCachePasses ?? BufferCachePasses(control: bufferCache)
        self.cache = cache
        self.weights = ReloadableWeights(loading: loading)
        self.confidenceMemory = initialConfidenceMemory
    }

    /// The model's modules, built on the first load and only emptied and refilled after it. See `Docs/performance-suggestions.md`.
    private let weights: ReloadableWeights<ModelContainer>

    /// How many passes are using the model now, which a release waits out before it empties the weights.
    private var passesRunning = 0
    private var waitingForPasses: [CheckedContinuation<Void, Never>] = []

    /// The Hugging Face cache a whole model is loaded from without asking the hub.
    private let cache: URL

    /// Shares model loading and lets a download caller retry a disk-only miss.
    private let inFlightLoad = InFlightModelLoad()

    /// Loads the weights from disk when they are whole there, downloading them only when they are not.
    public func prepare(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try await load(downloader: { #hubDownloader(AnonymousHub.client()) }, onProgress: onProgress)
    }

    /// Loads the weights from disk only, throwing ``WeightsNotOnDisk`` rather than fetching what is missing.
    public func reload() async throws {
        try await load(downloader: nil, onProgress: { _ in })
    }

    /// Reads the weights in once however many callers ask at the same time.
    private func load(
        downloader: (@Sendable () -> any MLXLMCommon.Downloader)?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard container == nil else { return }
        try await inFlightLoad.run(
            downloads: downloader != nil,
            onProgress: onProgress,
            shouldRetry: { $0 is WeightsNotOnDisk },
            operation: { report in try await self.fill(downloader: downloader, onProgress: report) })
    }

    /// Reads the weights in, fetching them through `downloader` only where one is given.
    private func fill(
        downloader: (@Sendable () -> any MLXLMCommon.Downloader)?,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Loading and the instruction warm-up share ownership with every other model pass.
        beginPass()
        defer { endPass() }
        let directory = try await model.weightsDirectory(
            cache: cache, downloader: downloader, onProgress: onProgress)
        // A load stopped during the fetch reads no weights, and one stopped during the read keeps none for the warm-up.
        try Task.checkCancellation()
        guard let loaded = try await weights.load(from: directory) else { return }
        try Task.checkCancellation()
        container = loaded
        // Lines judged with no model loaded are empty, so they are dropped once there is one.
        judgementCache.forgetEverything()
        warm = await warmInstructions()
        prompt = await promptTokens(
            addedTokens: AddedToken.read(fromTokenizerFile: directory.appending(path: "tokenizer.json")))
        vocabulary = await container?.perform { context in
            TokenHealing.Vocabulary(
                tokenizer: context.tokenizer, endOfTurn: context.configuration.extraEOSTokens,
                endingIds: context.configuration.eosTokenIds, prefixIndex: prefixIndex)
        }
        // A release that landed while the instructions were read leaves nothing of them behind.
        if container == nil { forgetReadings() }
    }

    /// Empties the weights once every pass using them has ended, and hands the freed GPU buffers back to the system.
    public func release() async {
        container = nil
        await inFlightLoad.cancel()
        forgetReadings()
        await passesEnded()
        bufferCachePasses.begin()
        await weights.unload()
        bufferCachePasses.end()
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
        kept = nil
        judgementCache.forgetEverything()
        confidenceMemory.forgetEverything()
    }

    /// How sure each recent pass was of the lines it wrote.
    private var confidenceMemory = ConfidenceMemory()

    /// Changes whenever retained model output is forgotten, so an older in-flight pass cannot restore it.
    private var forgetGeneration = 0

    public func confidence(ofGenerated line: String) -> Double? {
        confidenceMemory.confidence(of: line)
    }

    /// Forgets every judged candidate and generated confidence without releasing the model.
    public func forgetEverything() async {
        forgetGeneration &+= 1
        kept = nil
        judgementCache.forgetEverything()
        confidenceMemory.forgetEverything()
    }

    /// Per-candidate log-softmax rows the model has already produced, so a keystroke only re-averages from the new `start`.
    private var judgementCache = JudgementCache()

    /// How many candidate lines remain cached, for diagnostics and tests of forgetting.
    var judgementCacheCount: Int { judgementCache.count }

    /// Times `judgedTokens` read a previously-cached line instead of running the forward pass, for the tests about a cache that holds.
    public private(set) var judgementCacheHits = 0

    /// Times `judgedTokens` had to run the forward pass because nothing for this candidate was cached, for the tests about a cache that holds.
    public private(set) var judgementCacheMisses = 0

    /// Marks a pass as using the model.
    func beginPass() {
        bufferCachePasses.begin()
        passesRunning += 1
    }

    /// Marks a pass as done, resuming a release that was waiting for the last one.
    func endPass() {
        passesRunning -= 1
        bufferCachePasses.end()
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

    /// Keeps queried prefix indexes for this scorer's pinned tokenizer across weight releases.
    private let prefixIndex = TokenHealing.Vocabulary.PrefixIndex()

    /// The tokens every prompt opens with and the model's state after reading them, copied for each pass.
    private struct WarmInstructions: @unchecked Sendable {
        // Built once and only ever copied afterwards, which is what makes sharing it across passes safe.
        let tokens: [Int]
        let cache: [KVCache]
    }

    /// The last pass's prompt tokens and the model's state after them, so the next pass reads only what changed. See `Docs/performance-suggestions.md`.
    struct KeptPrefix<Cache>: @unchecked Sendable {
        // Held by one pass at a time, which is what makes writing to it safe.
        let tokens: [Int]
        let cache: Cache
    }

    /// What the last pass read, or nothing while a pass holds it and until a pass has read something.
    private var kept: KeptPrefix<[KVCache]>?

    /// Restores a prefix a pass took only while no newer pass has left one and the model remains loaded.
    static func restoring<Cache>(
        current: KeptPrefix<Cache>?, taken: KeptPrefix<Cache>?, weightsLoaded: Bool
    )
        -> KeptPrefix<Cache>?
    {
        current ?? (weightsLoaded ? taken : nil)
    }

    /// How many opening tokens two prompts share, the last one always left to be read again so the model has a token to answer from, or nothing when that is no more than the warmed instructions hold.
    static func sharedPrefix(of read: [Int], and all: [Int], beating warmed: Int) -> Int? {
        guard !all.isEmpty else { return nil }
        let shared = min(zip(read, all).prefix { $0 == $1 }.count, all.count - 1)
        guard shared > warmed else { return nil }
        return shared
    }

    /// How many of `all`'s opening tokens the kept cache holds once the rest is trimmed off it, or nothing when it shares too little or cannot be trimmed.
    private static func trimmed(_ kept: KeptPrefix<[KVCache]>, to all: [Int], beating warmed: Int) -> Int? {
        // Every layer's cache has to have counted the same tokens for one trim to leave them all at the shared prefix.
        guard let shared = sharedPrefix(of: kept.tokens, and: all, beating: warmed),
            canTrimPromptCache(kept.cache), let offset = kept.cache.first?.offset,
            kept.cache.allSatisfy({ $0.offset == offset }), offset >= shared
        else { return nil }
        trimPromptCache(kept.cache, numTokens: offset - shared)
        return shared
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
        try await generationPass(typed: typed, in: situation, asking: .one, tokenShare: 1)
    }

    public func alternativesPass(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws -> GenerationPass? {
        try await generationPass(
            typed: typed, in: situation, asking: .others(excluding: leader), tokenShare: 3)
    }

    private func generationPass(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async throws -> GenerationPass? {
        let generation = forgetGeneration
        guard let run = try await run(typed: typed, in: situation, asking: ask, tokenShare: tokenShare) else {
            return nil
        }
        guard generation == forgetGeneration else { return nil }
        let completions = Self.completions(from: run, typed: typed, asking: ask, in: situation)
        if run.forgetGeneration == forgetGeneration {
            confidenceMemory.remember(Self.confidences(of: completions, from: run, typed: typed))
        }
        return GenerationPass(
            text: run.text, stopReason: run.stop.map { String(describing: $0) } ?? "none",
            completions: completions)
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
        let pass = try await generationPass(typed: typed, in: situation, asking: ask, tokenShare: tokenShare)
        return pass?.completions ?? []
    }

    /// The model's words, how the pass ended, and the opening of its turn handed to it.
    struct Run {
        let forgetGeneration: Int
        let text: String
        let stop: GenerateStopReason?
        let written: String
        /// Every token the decode sampled, in order, with how likely the model found it.
        let tokens: [Int]
        let logProbabilities: [Double]
        let bytes: [[UInt8]]
    }

    /// Each line's confidence as the pass that wrote it measured it, so no second pass is spent scoring it.
    private static func confidences(of lines: [String], from run: Run, typed: String) -> [String: Double] {
        GeneratedConfidence.confidences(
            of: lines, typed: typed, written: run.written, text: run.text, tokens: run.tokens,
            logProbabilities: run.logProbabilities, bytes: run.bytes)
    }

    /// What the parser makes of a pass, withholding a budget-cut line that has not ended.
    static func completions(
        from run: Run, typed: String, asking ask: Ask, in situation: GenerationSituation
    ) -> [String] {
        guard !(ask == .one && run.stop == .length) else { return [] }
        var response = run.written + run.text
        if ask != .one, run.stop == .length, let last = response.last, !last.isNewline {
            if let newline = response.lastIndex(where: \.isNewline) {
                response = String(response[..<newline])
            } else {
                response = ""
            }
        }
        return CompletionText.modelCompletions(
            from: response, typed: typed, echoPolicy: .required, in: situation)
    }

    /// One pass over the model: prefilled under the container's lock, decoded outside it so a score never waits on a line; a pass that fails throws, so the caller can tell it from an empty answer.
    private func run(
        typed: String, in situation: GenerationSituation, asking ask: Ask, tokenShare: Int
    ) async throws -> Run? {
        guard
            let choices = CompletionPromptBuilder.choiceValuesIfPassAllowed(
                situation.choices, asking: ask)
        else {
            return nil
        }
        let forgetGeneration = self.forgetGeneration
        let promptTyped = PromptText.promptValue(typed)
        // The line also opens the model's own turn, so refuse it if sanitising would change that prefix.
        guard promptTyped == typed, let container, !Task.isCancelled, LatinScript.writesOnlyLatin(typed),
            typed.trimmingCharacters(in: .whitespaces).count >= Self.minimumTypedLength
        else { return nil }
        beginPass()
        defer { endPass() }
        // The register decides how much of a pass this line is worth: a command a little, a paragraph more.
        let register = Register.infer(from: situation, typed: typed)
        // A host and a search phrase are not things a model can know: each exists in this person's history or nowhere, so a guess at one is refused rather than drawn. See `Docs/predict-precision.md`.
        guard !register.answersFromHistoryAlone else { return nil }
        let message = CompletionPromptBuilder.message(
            typed: promptTyped, in: situation, register: register, asking: ask)
        let opening = ask.opening(of: promptTyped)
        // With the machine's values to choose among, the whole line before the word opens the turn and the word is one of them.
        let choice = opening.flatMap { CompletionText.choice(of: choices, at: $0) }
        let warm = self.warm
        let prompt = self.prompt
        // Taken out for this pass, so two passes that overlap never write one cache.
        let kept = self.kept
        self.kept = nil
        let keptCopy = kept.map { KeptPrefix(tokens: $0.tokens, cache: $0.cache.map { $0.copy() }) }
        let vocabulary = self.vocabulary
        let perLine = register.maxTokens
        let cap = maximumTokens
        let stream: AsyncStream<Generation>
        let generation: Task<Void, Never>
        let read: KeptPrefix<[KVCache]>?
        let ledger = SampleLedger()
        do {
            (stream, generation, read) = try await container.perform { loaded in
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
                // The tokens this prompt shares with the last one are already read, so the pass pays only for the rest.
                if let keptCopy,
                    let shared = Self.trimmed(keptCopy, to: all, beating: warm?.tokens.count ?? 0)
                {
                    feed = LMInput(text: LMInput.Text(tokens: MLXArray(all[shared...].map(Int32.init))))
                    cache = keptCopy.cache
                } else if let warm, all.count > warm.tokens.count,
                    Array(all[..<warm.tokens.count]) == warm.tokens
                {
                    // When the prompt opens exactly as the warm cache read it, the pass pays only for the tokens past that.
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
                        sampler: RecordingSampler(inner: parameters.sampler(), ledger: ledger),
                        maxTokens: parameters.maxTokens)
                } else {
                    iterator = try TokenIterator(
                        input: feed, model: context.model, cache: cache, processor: parameters.processor(),
                        sampler: RecordingSampler(inner: parameters.sampler(), ledger: ledger),
                        prefillStepSize: parameters.prefillStepSize, maxTokens: parameters.maxTokens)
                }
                let (stream, generation) = generateTask(
                    promptTokenCount: feed.text.tokens.size, modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer, iterator: iterator)
                return (stream, generation, cache.map { KeptPrefix(tokens: all, cache: $0) })
            }
        } catch is CancellationError {
            self.kept = Self.restoring(current: self.kept, taken: kept, weightsLoaded: self.container != nil)
            // A cancelled pass answers a line that is gone, and nothing is drawn for it either way.
            return nil
        } catch {
            self.kept = Self.restoring(current: self.kept, taken: kept, weightsLoaded: self.container != nil)
            throw error
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
        // Kept only now the decode has stopped writing to the cache, and only while the weights it was read from are loaded.
        if self.container != nil, self.forgetGeneration == forgetGeneration { self.kept = read }
        if let info {
            Self.log.debug(
                "PASS prompt=\(info.promptTokenCount) promptMs=\(Int(info.promptTime * 1_000)) generated=\(info.generationTokenCount) generateMs=\(Int(info.generateTime * 1_000))"
            )
        }
        let sampled = ledger.read()
        return Run(
            forgetGeneration: forgetGeneration,
            text: text, stop: info?.stopReason, written: choice?.written ?? opening?.written ?? "",
            tokens: sampled.tokens, logProbabilities: sampled.logProbabilities, bytes: vocabulary?.bytes ?? []
        )
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
        let generation = forgetGeneration
        // Reuse the candidate's token scores when its requested prefix-mass position is still current.
        if let cachedLine = judgementCache.recall(candidate: candidate) {
            guard let container else {
                judgementCacheHits += 1
                return []
            }
            guard let vocabulary = self.vocabulary else { return [] }
            // Only a call that reaches the model holds the process-wide cache; an unloaded scorer never does.
            beginPass()
            defer { endPass() }
            let result = await container.perform { loaded -> (JudgedLine, [JudgedToken], Bool) in
                let requestedStart = Self.requestedStart(
                    cachedLine.tokens, candidate: candidate, context: context,
                    vocabulary: vocabulary, tokenizer: loaded.tokenizer)
                guard cachedLine.isEmpty || cachedLine.prefixMassIndex == requestedStart else {
                    let line = Self.judge(
                        candidate, context: context, vocabulary: vocabulary, with: loaded)
                    let judged = Self.judgedFromCache(
                        line, candidate: candidate, context: context, vocabulary: vocabulary,
                        tokenizer: loaded.tokenizer)
                    return (line, judged, false)
                }
                let judged = Self.judgedFromCache(
                    cachedLine, candidate: candidate, context: context, vocabulary: vocabulary,
                    tokenizer: loaded.tokenizer)
                return (cachedLine, judged, true)
            }
            guard generation == forgetGeneration else { return [] }
            if result.2 {
                judgementCacheHits += 1
            } else {
                judgementCacheMisses += 1
                judgementCache.remember(result.0, for: candidate)
            }
            return result.1
        }
        judgementCacheMisses += 1
        // A cancelled pass says nothing about the candidate, so it leaves the cache as it found it.
        if Task.isCancelled { return [] }
        guard let container else {
            judgementCache.remember(
                JudgedLine(tokens: [], tokenLogProbabilities: [], prefixLogMasses: [], texts: []),
                for: candidate)
            return []
        }
        guard let scoringVocabulary = self.vocabulary else { return [] }
        beginPass()
        defer { endPass() }
        let result = await container.perform { loaded -> (JudgedLine, [JudgedToken]) in
            let line = Self.judge(
                candidate, context: context, vocabulary: scoringVocabulary, with: loaded)
            let judged = Self.judgedFromCache(
                line, candidate: candidate, context: context, vocabulary: scoringVocabulary,
                tokenizer: loaded.tokenizer)
            return (line, judged)
        }
        guard generation == forgetGeneration else { return [] }
        judgementCache.remember(result.0, for: candidate)
        return result.1
    }

    /// Two neutral tokens before the line, since `uttrflow-bakeoff score` shows Gemma 3 predicting nonsense from the first two positions.
    static let leadIn = "...\n"

    /// The whole candidate as the model reads it, keeping only the scores needed for typed-prefix judgements.
    private static func judge(
        _ candidate: String, context: String, vocabulary: TokenHealing.Vocabulary,
        with loaded: ModelContext
    ) -> JudgedLine {
        let whole = loaded.tokenizer.encode(text: leadIn + candidate)
        guard !whole.isEmpty else {
            return JudgedLine(tokens: [], tokenLogProbabilities: [], prefixLogMasses: [], texts: [])
        }
        let requestedStart = requestedStart(
            whole, candidate: candidate, context: context, vocabulary: vocabulary,
            tokenizer: loaded.tokenizer)
        let tokens = MLXArray(whole.map(Int32.init)).expandedDimensions(axis: 0)
        let output = loaded.model(LMInput.Text(tokens: tokens), cache: nil, state: nil)
        // Softmax in Float32, since the bf16 logits would round every log-probability to a coarse grid.
        let probabilities = logSoftmax(output.logits.asType(.float32), axis: -1)[0]
        var tokenScores: [MLXArray] = []
        var prefixMasses = [MLXArray?](repeating: nil, count: whole.count)
        tokenScores.reserveCapacity(whole.count)
        for position in whole.indices {
            let row = probabilities[position]
            let token = whole[position]
            tokenScores.append(row[token])
            guard position == requestedStart else { continue }
            let bytes = ScoredSpan.written(by: token, in: vocabulary.bytes)
            let continuing = ScoredSpan.continuing(bytes, in: vocabulary).filter { $0 != token }
            prefixMasses[position] = Self.logMass(of: continuing, in: row)
        }
        let readback = JudgementReadback.read(
            tokenScores: tokenScores, prefixMasses: prefixMasses
        ) { scalars in
            concatenated(scalars.map { $0.expandedDimensions(axis: 0) }).asArray(Float.self)
        }
        let texts = whole.map { loaded.tokenizer.decode(tokenIds: [$0]) }
        return JudgedLine(
            tokens: whole, tokenLogProbabilities: readback.tokenScores,
            prefixLogMasses: readback.prefixMasses, prefixMassIndex: requestedStart,
            texts: texts)
    }

    private static func requestedStart(
        _ whole: [Int], candidate: String, context: String,
        vocabulary: TokenHealing.Vocabulary, tokenizer: any MLXLMCommon.Tokenizer
    ) -> Int? {
        let typed = tokenizer.encode(
            text: leadIn + CompletionText.typedPart(of: candidate, following: context))
        return ScoredSpan(whole: whole, typed: typed, bytes: vocabulary.bytes)?.start
    }

    /// The log probability mass of a token prefix, accumulated without copying a vocabulary-sized row.
    private static func logMass(of tokens: [Int], in row: MLXArray) -> MLXArray? {
        guard !tokens.isEmpty else { return nil }
        let indices = MLXArray(tokens.map(Int32.init))
        return row[indices].logSumExp()
    }

    /// The judged tokens for a typed prefix, cut from the cached line so a re-typed keystroke skips the forward pass.
    private static func judgedFromCache(
        _ line: JudgedLine, candidate: String, context: String, vocabulary: TokenHealing.Vocabulary,
        tokenizer: any MLXLMCommon.Tokenizer
    ) -> [JudgedToken] {
        guard !line.isEmpty else { return [] }
        let typed = tokenizer.encode(
            text: leadIn + CompletionText.typedPart(of: candidate, following: context))
        return JudgedLine.judged(from: line, typedTokens: typed, vocabulary: vocabulary)
    }
}

extension WeightLoading<ModelContainer> {
    /// Builds through mlx-swift-lm once, then swaps weights in place so a reload never quantises fresh arrays. See `Docs/performance-suggestions.md`.
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

/// The same loaded weights tidy dictation, so the app holds one copy of the model for suggestions and clean-up.
extension MLXCandidateScorer: CleanupModel {
    /// The most tokens one tidied utterance may produce.
    static let tidyTokens = 256

    /// A reply a little longer than the prompt it tidies, so a runaway stops early and the guard declines it.
    static func tidyBudget(for prompt: String) -> Int {
        min(tidyTokens, 32 + prompt.utf8.count / 2)
    }

    /// Available only while the weights are loaded; a dictation never waits on a load.
    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        guard container != nil else { return .unavailable(reason: .other("the local model is not loaded")) }
        guard let language else { return .available }
        return model.supports(language) ? .available : .unsupportedLanguage(language)
    }

    /// One block of instructions, with no examples apart from it.
    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await tidy(text, system: instructions, examples: [], kind: kind)
    }

    /// The rules as the system turn and each worked example as an earlier exchange, so the model answers rather than reads on.
    public func rewrite(
        _ text: String, prompt: ModelPrompt, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await tidy(text, system: prompt.rules, examples: prompt.examples, kind: kind)
    }

    /// Answers `text` after the system turn and the examples in a fresh session, so one utterance cannot bleed into the next.
    private func tidy(
        _ text: String, system: String, examples: [WorkedExample], kind: TransformerKind
    ) async throws(TransformationError) -> String {
        guard let container else { throw .transformFailed(kind: kind, failure: .notReady) }
        beginPass()
        defer { endPass() }
        do {
            return try await Self.answer(text, system: system, examples: examples, in: container)
        } catch {
            throw .transformFailed(kind: kind, failure: .of(error))
        }
    }

    /// Runs the session off the actor, which owns no part of it.
    private nonisolated static func answer(
        _ text: String, system: String, examples: [WorkedExample], in container: ModelContainer
    ) async throws -> String {
        let turns = examples.flatMap { [Chat.Message.user($0.question), .assistant($0.cleaned)] }
        let history = [Chat.Message.system(system)] + turns
        let session = ChatSession(
            container, history: history,
            generateParameters: GenerateParameters(maxTokens: tidyBudget(for: text), temperature: 0))
        return try await session.respond(to: text)
    }
}

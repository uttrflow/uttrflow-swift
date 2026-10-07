// The WhisperKit recogniser, and the decoding rules a conditioning prompt would otherwise cost it.
public import Foundation
public import UttrflowCore
import CoreML
import OSLog
import WhisperKit

/// The real WhisperKit recogniser, kept thin; excluded from coverage. See Docs/speech-engines.md.
public actor WhisperKitBackend: TranscriptionBackend {
    private let model: SpeechModel
    private let modelFolder: URL
    /// On: only prewarm holds the first compile's peak down, and that peak is still unread (#481).
    private let prewarm: Bool
    private let compute: SpeechComputePlan
    private let fallback: SpeechFallbackPlan
    private var kit: LoadedKit?
    private var modelUseLease: ModelDirectoryUseLease?
    /// Where each finished load is kept for the Diagnostics page; `nil` in a measurement harness.
    private let loadLog: SpeechModelLoadLog?
    /// Log-odds that help a begun dictionary word finish; zero turns the bias off.
    private let phraseBias: Float

    public init(
        model: SpeechModel, modelFolder: URL, prewarm: Bool = true, compute: SpeechComputePlan = .shipping,
        fallback: SpeechFallbackPlan = .shipping, loadLog: SpeechModelLoadLog? = nil,
        phraseBias: Float = 0
    ) {
        self.phraseBias = phraseBias
        self.model = model
        self.modelFolder = modelFolder
        self.prewarm = prewarm
        self.compute = compute
        self.fallback = fallback
        self.loadLog = loadLog
    }

    /// One frame past the end-of-clip window it is driven with, since a clip no longer than that decodes to nothing.
    static let shortestClip = Duration.seconds(Double(VocabularyPrompt.windowClipTime)) + .milliseconds(20)

    public nonisolated var minimumDuration: Duration { Self.shortestClip }

    /// Where each Core ML stage runs, named so a package upgrade cannot move the model to other hardware.
    static let computeOptions = options(for: .shipping)

    /// The Core ML units each stage of a plan runs on.
    static func options(for plan: SpeechComputePlan) -> ModelComputeOptions {
        switch plan {
        case .shipping:
            ModelComputeOptions(
                melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine)
        case .gpu: uniform(.cpuAndGPU)
        case .neuralEngine: uniform(.cpuAndNeuralEngine)
        case .all: uniform(.all)
        case .cpu: uniform(.cpuOnly)
        }
    }

    private static func uniform(_ units: MLComputeUnits) -> ModelComputeOptions {
        ModelComputeOptions(melCompute: units, audioEncoderCompute: units, textDecoderCompute: units)
    }

    /// Where the load's own measurements go; `Docs/startup.md` is the only record of what this costs.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "speech")

    public func load() async throws(SpeechEngineError) {
        guard kit == nil else { return }
        let started = ContinuousClock.now
        guard FileManager.default.fileExists(atPath: modelFolder.deletingLastPathComponent().path) else {
            throw .modelNotInstalled
        }
        guard let lease = ModelDirectoryUseLease.acquireShared(for: modelFolder) else {
            throw .modelLoadFailed(description: "the speech model is being removed")
        }
        modelUseLease = lease
        // A missing tokenizer is "not installed", or WhisperKit visits Hugging Face instead of failing.
        guard FileManager.default.fileExists(atPath: modelFolder.path),
            TokenizerAssets.arePresent(in: modelFolder)
        else {
            modelUseLease = nil
            throw .modelNotInstalled
        }

        do {
            // `download: false`, so a missing model is a clear error rather than a silent stall.
            let whisper = try await WhisperKit(
                WhisperKitConfig(
                    model: model.variant,
                    modelFolder: modelFolder.path,
                    // Tokenizer search stays in the model's directory, never the Hugging Face cache.
                    tokenizerFolder: modelFolder,
                    computeOptions: Self.options(for: compute),
                    verbose: false,
                    logLevel: .error,
                    prewarm: prewarm,
                    load: true,
                    download: false
                )
            )
            // Detection may only answer in a language the product transcribes, so Hindi is never heard as Urdu.
            whisper.textDecoder = LanguageHeldDecoder(
                wrapping: whisper.textDecoder, languages: LanguageCode.transcribed)
            kit = LoadedKit(whisper, fallback: fallback, phraseBias: phraseBias)
        } catch {
            modelUseLease = nil
            throw WeightsAssets.loadFailure(
                of: model, in: modelFolder, description: error.localizedDescription)
        }
        report(started.duration(to: ContinuousClock.now))
    }

    /// Drops the recogniser and its weights; the next `load` reads them from disk again.
    public func unload() async {
        guard kit != nil else { return }
        kit = nil
        modelUseLease = nil
        Self.log.info("speech model released from memory")
    }

    /// Says where the load's seconds went, and keeps the load so a slow one can be explained later.
    private func report(_ elapsed: Duration) {
        let timings = kit?.timings
        let parts = timings.map {
            SpeechModelLoadParts(
                prewarm: $0.prewarmLoadTime, specialiseEncoder: $0.encoderSpecializationTime,
                specialiseDecoder: $0.decoderSpecializationTime, loadEncoder: $0.encoderLoadTime,
                loadDecoder: $0.decoderLoadTime, tokenizer: $0.tokenizerLoadTime)
        }
        do {
            try loadLog?.record(
                seconds: elapsed.inSeconds, parts: parts, modelRevision: model.weightsRevision)
        } catch {
            Self.log.error("speech model load not kept: \(ErrorLog.failure(error), privacy: .public)")
        }
        guard let timings else {
            Self.log.info("speech model loaded in \(elapsed.inSeconds, format: .fixed(precision: 2))s")
            return
        }
        Self.log.info(
            """
            speech model loaded in \(elapsed.inSeconds, format: .fixed(precision: 2))s: \
            prewarm \(timings.prewarmLoadTime, format: .fixed(precision: 2))s, \
            specialise encoder \(timings.encoderSpecializationTime, format: .fixed(precision: 2))s \
            decoder \(timings.decoderSpecializationTime, format: .fixed(precision: 2))s, \
            load encoder \(timings.encoderLoadTime, format: .fixed(precision: 2))s \
            decoder \(timings.decoderLoadTime, format: .fixed(precision: 2))s, \
            tokenizer \(timings.tokenizerLoadTime, format: .fixed(precision: 2))s
            """)
    }

    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: vocabulary, after: nil)
    }

    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String],
        after precedingText: String?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await load()
        guard let kit else { throw .modelLoadFailed(description: "the recogniser did not load") }
        let backend = RetryBackend(kit: kit)

        do {
            let transcript = try await CappedDecodeRetry.transcribeRecoveringEmptyPrompt(
                samples: samples, languageHint: languageHint, vocabulary: vocabulary,
                precedingText: precedingText, using: backend)
            Self.report(transcript.effort)
            return transcript
        } catch {
            throw .transcriptionFailed(description: error.localizedDescription)
        }
    }

    /// Says in the log what a piece cost beyond one decode, so a slow dictation can name its cause.
    fileprivate static func report(_ effort: DecodeEffort) {
        guard !effort.isPlain else { return }
        // Counted, not named: the log audit reads a name holding "prompt" as text somebody typed.
        let retried = effort.retriedWithoutPrompt ? 1 : 0
        let unresolved = effort.capUnresolved ? 1 : 0
        let budgetSpent = effort.retryBudgetSpent ? 1 : 0
        log.info(
            "decoded piece: fallbacks=\(effort.fallbacks, privacy: .public) fallbackSeconds=\(effort.fallbackSeconds, format: .fixed(precision: 2), privacy: .public) encoderRuns=\(effort.encoderRuns, privacy: .public) retried=\(retried, privacy: .public) capUnresolved=\(unresolved, privacy: .public) retryBudgetSpent=\(budgetSpent, privacy: .public)"
        )
    }
}

/// Flattens WhisperKit's per-window results into one transcript.
fileprivate func rawTranscript(
    from results: [TranscriptionResult], promptPositions: Int = 0, vocabularyPrompt: [String] = [],
    conditioning: DecodeConditioning = .available, split: RecognitionTimings = .zero
) -> RawTranscript {
    TranscriptAssembly.whisper(
        results.enumerated().map { index, result in
            WhisperTranscriptWindow(
                text: result.text,
                languageIdentifier: result.language,
                segments: result.segments.map {
                    RawSegment(
                        text: $0.text, start: Double($0.start), end: Double($0.end),
                        words: $0.words.map { words in
                            words.map {
                                RawWord(
                                    text: $0.word, start: Double($0.start), end: Double($0.end),
                                    probability: Double($0.probability))
                            }
                        },
                        reliability: SegmentReliability(
                            temperature: Double($0.temperature), averageLogProbability: Double($0.avgLogprob),
                            noSpeechProbability: Double($0.noSpeechProb),
                            compressionRatio: Double($0.compressionRatio)))
                },
                // The split is the whole call's, so it is counted once, on the first window.
                effort: effort(of: [result]).adding(DecodeEffort(timings: index == 0 ? split : .zero)),
                tokensUsed: result.segments.reduce(0) { $0 + $1.tokens.count },
                promptPositions: promptPositions,
                vocabularyPrompt: vocabularyPrompt,
                conditioning: conditioning)
        })
}

/// What WhisperKit's own timings say this piece cost beyond one decode.
fileprivate func effort(of results: [TranscriptionResult]) -> DecodeEffort {
    DecodeEffort(
        fallbacks: results.reduce(0) { $0 + Int($1.timings.totalDecodingFallbacks) },
        fallbackSeconds: results.reduce(0) { $0 + $1.timings.decodingFallback },
        encoderRuns: results.reduce(0) { $0 + Int($1.timings.totalEncodingRuns) },
        timings: results.reduce(.zero) { $0.adding(recognitionTimings(of: $1.timings)) })
}

/// WhisperKit's per-result timings in the sub-stages ``RecognitionTimings`` names.
fileprivate func recognitionTimings(of timings: TranscriptionTimings) -> RecognitionTimings {
    RecognitionTimings(
        melSeconds: timings.logmels, encodeSeconds: timings.encoding,
        decoderSetupSeconds: timings.decodingInit, decodeSteps: Int(timings.totalDecodingLoops),
        decodeSeconds: timings.decodingPredictions, wordTimingRuns: Int(timings.totalTimestampAlignmentRuns),
        wordTimingSeconds: timings.decodingWordTimestamps, recognitionSeconds: timings.fullPipeline,
        decodeOverheadSeconds: timings.decodingNonPrediction)
}

/// Adapts ``LoadedKit`` to ``TranscriptionBackend`` so ``CappedDecodeRetry`` can call it without knowing about WhisperKit.
private struct RetryBackend: TranscriptionBackend {
    let kit: LoadedKit

    var minimumDuration: Duration { .zero }

    func load() async throws(SpeechEngineError) {}

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: [])
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await transcribe(samples, languageHint: languageHint, biasedTowards: vocabulary, after: nil)
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String],
        after precedingText: String?
    ) async throws(SpeechEngineError) -> RawTranscript {
        do {
            let decoded = try await kit.transcribe(
                samples, languageHint: languageHint, biasedTowards: vocabulary, after: precedingText)
            return rawTranscript(
                from: decoded.results, promptPositions: decoded.promptPositions,
                vocabularyPrompt: decoded.vocabularyPrompt,
                conditioning: decoded.conditioning, split: decoded.split)
        } catch {
            throw .transcriptionFailed(description: error.localizedDescription)
        }
    }
}

extension FileSystemSpeechModelStore {
    /// A store that fetches pinned public speech assets without sending local Hugging Face tokens.
    public static func whisperKit(root: URL = FileSystemSpeechModelStore.defaultRoot()) -> Self {
        FileSystemSpeechModelStore(root: root) { model, component, destination, onProgress in
            switch component {
            case .weights:
                try await downloadWeights(for: model, into: destination, onProgress: onProgress)
            case .tokenizer:
                // Reports no progress: a second scale after the weights would run the bar backwards.
                try await downloadTokenizer(for: model, into: destination)
            }
        }
    }
}

/// Owns the loaded recogniser; `WhisperKit` is not `Sendable`, and `BackedSpeechEngine` admits one call at a time.
private final class LoadedKit: @unchecked Sendable {
    private let kit: WhisperKit
    private let fallback: SpeechFallbackPlan
    private let phraseBias: Float

    init(_ kit: WhisperKit, fallback: SpeechFallbackPlan, phraseBias: Float) {
        self.kit = kit
        self.fallback = fallback
        self.phraseBias = phraseBias
    }

    /// What the load cost, as WhisperKit measured it while doing it.
    var timings: TranscriptionTimings { kit.currentTimings }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String],
        after precedingText: String?
    ) async throws -> (
        results: [TranscriptionResult], promptPositions: Int, vocabularyPrompt: [String],
        conditioning: DecodeConditioning, split: RecognitionTimings
    ) {
        // Passed through optional, so a half-loaded kit gives an unbiased dictation, reported as unconditioned.
        let tokenizer = kit.tokenizer
        let promptTokenizer = tokenizer.map { WhisperPromptTokenizer(tokenizer: $0) }
        let packing = promptTokenizer.map {
            VocabularyPrompt.packing(for: vocabulary, after: precedingText, using: $0)
        }
        let options = VocabularyPrompt.decodingOptions(
            languageHint: languageHint,
            vocabulary: vocabulary,
            precedingText: precedingText,
            tokenizer: promptTokenizer,
            fallback: fallback
        )
        // Reassigned on every call, including to nothing, so a rule never outlives the prompt it was measured for.
        kit.textDecoder.logitsFilters = Self.rules(
            for: options, tokenizer: tokenizer,
            bias: promptTokenizer.map {
                PhraseBias(words: packing?.words ?? [], using: $0, strength: phraseBias)
            })
        // Reassigned with the rules, so word timings always read the rows this call's prompt left them.
        kit.segmentSeeker = Self.seeker(for: options, tokenizer: tokenizer)
        let held = kit.textDecoder as? LanguageHeldDecoder
        _ = held?.drainSplit()
        let results = try await kit.transcribe(
            audioArray: samples, decodeOptions: options, callback: Self.loopStop(windowOf: samples.count))
        return (
            results,
            tokenizer.map {
                DecoderPrefill(
                    promptTokens: options.promptTokens, specialTokenBegin: $0.specialTokens.specialTokenBegin,
                    isMultilingual: !$0.allLanguageTokens.isEmpty
                ).transcriptStart
            } ?? 0,
            packing?.words ?? [],
            tokenizer == nil ? .unavailable(.tokenizerUnavailable) : .available,
            held?.drainSplit() ?? .zero
        )
    }

    /// Stops a window's decode once its text is a loop that `RecognitionLoop.undone` would cut anyway.
    static func loopStop(windowOf sampleCount: Int) -> TranscriptionCallback {
        let samples = min(sampleCount, Constants.defaultWindowSamples)
        let audio = Duration.seconds(Double(samples) / Double(AudioSamples.canonicalSampleRate))
        return { progress in RecognitionLoop.isLooping(progress.text, within: audio) ? false : nil }
    }

    /// The segment seeker for this call, lined up past the prompt that precedes the transcript in the alignment weights.
    private static func seeker(
        for options: DecodingOptions, tokenizer: (any WhisperTokenizer)?
    ) -> any SegmentSeeking {
        guard let tokenizer else { return SegmentSeeker() }
        return DecoderPrefill(
            promptTokens: options.promptTokens,
            specialTokenBegin: tokenizer.specialTokens.specialTokenBegin,
            isMultilingual: !tokenizer.allLanguageTokens.isEmpty
        ).segmentSeeker()
    }

    /// The prompt's own rules: the timestamp rules it loses and the bias towards its words; nothing without a prompt.
    private static func rules(
        for options: DecodingOptions, tokenizer: (any WhisperTokenizer)?, bias: PhraseBias?
    ) -> [any LogitsFiltering] {
        guard options.promptTokens != nil, let tokenizer else {
            return []
        }
        let prefill = DecoderPrefill(
            promptTokens: options.promptTokens,
            specialTokenBegin: tokenizer.specialTokens.specialTokenBegin,
            isMultilingual: !tokenizer.allLanguageTokens.isEmpty
        )
        let timestamps =
            options.withoutTimestamps ? [] : prefill.logitsFilters(specialTokens: tokenizer.specialTokens)
        guard let bias, bias.isActive else { return timestamps }
        return timestamps + [
            PhraseBiasFilter(
                bias: bias, sampleBegin: prefill.count,
                firstSpecialToken: tokenizer.specialTokens.specialTokenBegin)
        ]
    }
}

/// WhisperKit's own tokeniser behind the ``PromptTokenizer`` seam, in the one file that knows WhisperKit.
private struct WhisperPromptTokenizer: PromptTokenizer {
    let tokenizer: any WhisperTokenizer

    func encode(text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    var firstSpecialToken: Int {
        tokenizer.specialTokens.specialTokenBegin
    }
}

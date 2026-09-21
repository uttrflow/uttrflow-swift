// The WhisperKit recogniser, and the decoding rules a conditioning prompt would otherwise cost it.
public import Foundation
public import UttrflowCore
import OSLog
import WhisperKit

/// The real WhisperKit recogniser, kept thin; excluded from coverage. See Docs/speech-engines.md.
public actor WhisperKitBackend: TranscriptionBackend {
    private let model: SpeechModel
    private let modelFolder: URL
    private var kit: LoadedKit?

    public init(model: SpeechModel, modelFolder: URL) {
        self.model = model
        self.modelFolder = modelFolder
    }

    /// One frame past the end-of-clip window it is driven with, since a clip no longer than that decodes to nothing.
    static let shortestClip = Duration.seconds(Double(VocabularyPrompt.windowClipTime)) + .milliseconds(20)

    public nonisolated var minimumDuration: Duration { Self.shortestClip }

    /// Where the load's own measurements go; `Docs/startup.md` is the only record of what this costs.
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "speech")

    public func load() async throws(SpeechEngineError) {
        guard kit == nil else { return }
        let started = ContinuousClock.now
        // A missing tokenizer is "not installed", or WhisperKit visits Hugging Face instead of failing.
        guard FileManager.default.fileExists(atPath: modelFolder.path),
            TokenizerAssets.arePresent(in: modelFolder)
        else {
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
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true,
                    download: false
                )
            )
            // Detection may only answer in a language the product transcribes, so Hindi is never heard as Urdu.
            whisper.textDecoder = LanguageHeldDecoder(
                wrapping: whisper.textDecoder, languages: LanguageCode.transcribed)
            kit = LoadedKit(whisper)
        } catch {
            throw .modelLoadFailed(description: error.localizedDescription)
        }
        report(started.duration(to: ContinuousClock.now))
    }

    /// Says where the load's seconds went, since WhisperKit measures the parts and nothing reads them.
    private func report(_ elapsed: Duration) {
        guard let timings = kit?.timings else {
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
        try await load()
        guard let kit else { throw .modelLoadFailed(description: "the recogniser did not load") }

        do {
            let biased = Self.rawTranscript(
                from: try await kit.transcribe(
                    samples, languageHint: languageHint, biasedTowards: vocabulary))
            guard !vocabulary.isEmpty, biased.text.isEmpty else {
                Self.report(biased.effort)
                return biased
            }

            // The net: a prompt that decodes to nothing costs a second decode, never the words.
            let retried = Self.rawTranscript(
                from: try await kit.transcribe(
                    samples, languageHint: languageHint, biasedTowards: []))
            let effort = biased.effort.addingRetry(retried.effort)
            Self.report(effort)
            return RawTranscript(
                text: retried.text, languageIdentifier: retried.languageIdentifier,
                languageProbability: retried.languageProbability, segments: retried.segments,
                effort: effort)
        } catch {
            throw .transcriptionFailed(description: error.localizedDescription)
        }
    }

    /// Says in the log what a piece cost beyond one decode, so a slow dictation can name its cause.
    private static func report(_ effort: DecodeEffort) {
        guard !effort.isPlain else { return }
        // Counted, not named: the log audit reads a name holding "prompt" as text somebody typed.
        let retried = effort.retriedWithoutPrompt ? 1 : 0
        log.info(
            "decoded piece: fallbacks=\(effort.fallbacks, privacy: .public) fallbackSeconds=\(effort.fallbackSeconds, format: .fixed(precision: 2), privacy: .public) encoderRuns=\(effort.encoderRuns, privacy: .public) retried=\(retried, privacy: .public)"
        )
    }

    /// What WhisperKit's own timings say this piece cost beyond one decode.
    private static func effort(of results: [TranscriptionResult]) -> DecodeEffort {
        DecodeEffort(
            fallbacks: results.reduce(0) { $0 + Int($1.timings.totalDecodingFallbacks) },
            fallbackSeconds: results.reduce(0) { $0 + $1.timings.decodingFallback },
            encoderRuns: results.reduce(0) { $0 + Int($1.timings.totalEncodingRuns) })
    }

    /// Flattens WhisperKit's per-window results into one transcript.
    private static func rawTranscript(from results: [TranscriptionResult]) -> RawTranscript {
        RawTranscript(
            text: results.map(\.text).joined(separator: " "),
            languageIdentifier: results.first?.language,
            // WhisperKit surfaces a verdict but not a probability from `transcribe`.
            languageProbability: nil,
            segments: results.flatMap(\.segments).map {
                RawSegment(
                    text: $0.text, start: Double($0.start), end: Double($0.end),
                    words: $0.words.map { words in
                        words.map {
                            RawWord(
                                text: $0.word, start: Double($0.start), end: Double($0.end),
                                probability: Double($0.probability))
                        }
                    })
            },
            effort: effort(of: results)
        )
    }
}

extension FileSystemSpeechModelStore {
    /// A store that fetches from WhisperKit's model repository.
    public static func whisperKit(root: URL = FileSystemSpeechModelStore.defaultRoot()) -> Self {
        FileSystemSpeechModelStore(root: root) { model, component, destination, onProgress in
            switch component {
            case .weights:
                // The hub nests its output under the download base; the store wants the files at the top.
                let downloaded = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: destination,
                    progressCallback: { onProgress($0.fractionCompleted) }
                )
                try FileSystemSpeechModelStore.hoist(contentsOf: downloaded, into: destination)
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

    init(_ kit: WhisperKit) {
        self.kit = kit
    }

    /// What the load cost, as WhisperKit measured it while doing it.
    var timings: TranscriptionTimings { kit.currentTimings }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws -> [TranscriptionResult] {
        // Passed through optional, so a half-loaded kit gives an unbiased dictation, not a crash.
        let tokenizer = kit.tokenizer
        let options = VocabularyPrompt.decodingOptions(
            languageHint: languageHint,
            vocabulary: vocabulary,
            tokenizer: tokenizer.map { WhisperPromptTokenizer(tokenizer: $0) }
        )
        // Reassigned on every call, including to nothing, so a rule never outlives the prompt it was measured for.
        kit.textDecoder.logitsFilters = Self.rules(for: options, tokenizer: tokenizer)
        // Reassigned with the rules, so word timings always read the rows this call's prompt left them.
        kit.segmentSeeker = Self.seeker(for: options, tokenizer: tokenizer)
        return try await kit.transcribe(audioArray: samples, decodeOptions: options)
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

    /// The timestamp rules a prompted decode loses, and nothing at all without a prompt, where WhisperKit's own still fire.
    private static func rules(
        for options: DecodingOptions, tokenizer: (any WhisperTokenizer)?
    ) -> [any LogitsFiltering] {
        guard options.promptTokens != nil, let tokenizer, !options.withoutTimestamps else {
            return []
        }
        let prefill = DecoderPrefill(
            promptTokens: options.promptTokens,
            specialTokenBegin: tokenizer.specialTokens.specialTokenBegin,
            isMultilingual: !tokenizer.allLanguageTokens.isEmpty
        )
        return prefill.logitsFilters(specialTokens: tokenizer.specialTokens)
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

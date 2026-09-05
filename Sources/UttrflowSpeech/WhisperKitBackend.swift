public import Foundation
private import CoreML
public import UttrflowCore
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

    public func load() async throws(SpeechEngineError) {
        guard kit == nil else { return }
        // A missing tokenizer is "not installed", or WhisperKit visits Hugging Face instead of failing.
        guard FileManager.default.fileExists(atPath: modelFolder.path),
            TokenizerAssets.arePresent(in: modelFolder)
        else {
            throw .modelNotInstalled
        }

        do {
            // `download: false`, so a missing model is a clear error rather than a silent stall.
            kit = LoadedKit(
                try await WhisperKit(
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
                ))
        } catch {
            throw .modelLoadFailed(description: error.localizedDescription)
        }
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
            guard !vocabulary.isEmpty, biased.text.isEmpty else { return biased }

            // The net: a prompt that decodes to nothing costs a second decode, never the words.
            return Self.rawTranscript(
                from: try await kit.transcribe(
                    samples, languageHint: languageHint, biasedTowards: []))
        } catch {
            throw .transcriptionFailed(description: error.localizedDescription)
        }
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
            }
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

/// Owns the loaded recogniser; `WhisperKit` is not `Sendable`, and the actor above serialises every call.
private final class LoadedKit: @unchecked Sendable {
    private let kit: WhisperKit

    init(_ kit: WhisperKit) {
        self.kit = kit
    }

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
        // Reassigned on every call, including to nothing, so a guard never outlives its prompt.
        kit.textDecoder.logitsFilters = Self.guards(for: options, tokenizer: tokenizer)
        return try await kit.transcribe(audioArray: samples, decodeOptions: options)
    }

    /// The one filter a conditioning prompt needs, and nothing at all without one.
    private static func guards(
        for options: DecodingOptions, tokenizer: (any WhisperTokenizer)?
    ) -> [any LogitsFiltering] {
        guard let prompt = options.promptTokens, let tokenizer else { return [] }
        return [
            PromptPrefillGuard(
                forcedPrefillLength: VocabularyPrompt.forcedPrefillLength(
                    promptLength: prompt.count, isMultilingual: !tokenizer.allLanguageTokens.isEmpty
                ),
                endToken: tokenizer.specialTokens.endToken
            )
        ]
    }
}

/// Holds the end token shut while the decoder is fed a conditioning prompt. See Docs/speech-engines.md.
private final class PromptPrefillGuard: LogitsFiltering {
    private let forcedPrefillLength: Int
    private let endTokenIndex: [[NSNumber]]

    init(forcedPrefillLength: Int, endToken: Int) {
        self.forcedPrefillLength = forcedPrefillLength
        self.endTokenIndex = [[0, 0, endToken as NSNumber]]
    }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        guard tokens.count == forcedPrefillLength else { return logits }
        logits.fill(indexes: endTokenIndex, with: -FloatType.infinity)
        return logits
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

public import Foundation
private import CoreML
public import UttrflowCore
import WhisperKit

/// The real WhisperKit recogniser.
///
/// Deliberately thin: it loads a model and returns raw text. Every rule about that
/// text — cleaning it, mapping it, refusing audio too short to mean anything — lives
/// in the tested layer above. Excluded from the coverage gate because exercising it
/// means downloading a model and decoding real speech, which `uttrflow-dev` does.
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
        // The tokenizer is checked as carefully as the weights because WhisperKit treats
        // a missing one as a reason to visit Hugging Face rather than a reason to fail.
        // Calling it "not installed" here is the difference between an offer to finish
        // the download and a retry that will fail identically for ever.
        guard FileManager.default.fileExists(atPath: modelFolder.path),
            TokenizerAssets.arePresent(in: modelFolder)
        else {
            throw .modelNotInstalled
        }

        do {
            // `download: false` keeps this honest: the store owns installing, so a
            // missing model surfaces as a clear error rather than a silent stall on
            // a slow connection.
            kit = LoadedKit(
                try await WhisperKit(
                    WhisperKitConfig(
                        model: model.variant,
                        modelFolder: modelFolder.path,
                        // Points the tokenizer search at the model's own directory.
                        // Left unset, WhisperKit searches the shared Hugging Face cache
                        // under ~/Documents first and downloads into it when it finds
                        // nothing — a network round trip on the dictation path, and
                        // state outside anything this app installs or removes.
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

            // The net under everything above. A conditioning prompt changes how the
            // decoder is driven, and ``PromptPrefillGuard`` exists because one way of
            // driving it returns nothing at all; a WhisperKit release or a model variant
            // that finds another such way must cost the user a slower dictation, never a
            // silent one. Silence transcribes to nothing too, so this can decode twice
            // for no gain — which is the right price for never losing a dictation.
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
                // The hub nests its output under the download base; the store's contract
                // is that a model's files sit directly in its own directory.
                let downloaded = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: destination,
                    progressCallback: { onProgress($0.fractionCompleted) }
                )
                try FileSystemSpeechModelStore.hoist(contentsOf: downloaded, into: destination)
            case .tokenizer:
                // Reports no progress on purpose. It is well under a percent of the
                // download, and a second scale running from zero after the first had
                // reached one would send the bar backwards.
                try await downloadTokenizer(for: model, into: destination)
            }
        }
    }
}

/// Owns the loaded recogniser.
///
/// `WhisperKit` is a class with async methods and no `Sendable` conformance. This box
/// is its only owner, and the actor above serialises every call into it, so the
/// guarantee the type lacks is supplied here — in one place, with a reason — rather
/// than at each call site.
private final class LoadedKit: @unchecked Sendable {
    private let kit: WhisperKit

    init(_ kit: WhisperKit) {
        self.kit = kit
    }

    func transcribe(
        _ samples: [Float], languageHint: LanguageCode?, biasedTowards vocabulary: [String]
    ) async throws -> [TranscriptionResult] {
        // WhisperKit's tokenizer is `nil` until its model has loaded, and the model has
        // loaded or this box would not exist. Passing the optional straight through
        // rather than asserting keeps the one unlucky ordering — a caller reaching a
        // half-loaded kit — a plain unbiased dictation instead of a crash.
        let tokenizer = kit.tokenizer
        let options = VocabularyPrompt.decodingOptions(
            languageHint: languageHint,
            vocabulary: vocabulary,
            tokenizer: tokenizer.map { WhisperPromptTokenizer(tokenizer: $0) }
        )
        // Reassigned on every call, including to nothing, so a prompt's guard can never
        // outlive the prompt it was measured for.
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

/// Holds the end token shut while the decoder is still being fed a conditioning prompt.
///
/// Without this, biasing does not merely work poorly — it returns nothing. WhisperKit
/// ends a window as soon as its sampler predicts the end token, and it applies that test
/// on every iteration of the decode loop, including the ones that are force-feeding the
/// prompt and discarding whatever the sampler said. Asked to transcribe five seconds of
/// clear speech, the recogniser returned an empty string for every prompt tried: three
/// words, one word, a comma-separated glossary, a sentence of prose, at nine tokens and
/// at fifty-two. With this filter in place the same audio and the same prompts decode in
/// full.
///
/// The `tokens.count == sampleBegin` shape is WhisperKit's own — `SuppressBlankFilter`
/// is built exactly this way — and it works because the token array does not grow while
/// the prompt is being forced. It is installed through `logitsFilters`, which WhisperKit
/// documents as an extension point, rather than by reaching into the decoder.
///
/// Delete it when WhisperKit stops ending a window during its own prefill. Until then
/// ``WhisperKitBackend`` also re-runs a blank biased transcription without the
/// vocabulary, because a guard that stops fitting must cost latency and not the words.
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

/// WhisperKit's own tokeniser, seen through the seam ``VocabularyPrompt`` is written
/// against.
///
/// Lives here rather than beside that seam because this is the file that is allowed to
/// know what a real recogniser looks like, and the only one whose contents cannot be
/// exercised without a downloaded model.
private struct WhisperPromptTokenizer: PromptTokenizer {
    let tokenizer: any WhisperTokenizer

    func encode(text: String) -> [Int] {
        tokenizer.encode(text: text)
    }

    var firstSpecialToken: Int {
        tokenizer.specialTokens.specialTokenBegin
    }
}

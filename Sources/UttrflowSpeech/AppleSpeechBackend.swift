// The macOS system recogniser behind the TranscriptionBackend seam.
public import Foundation
public import UttrflowCore
private import AVFoundation
private import Speech

/// The macOS system recogniser: no download, faster than Whisper, no Hindi; excluded from coverage.
public actor AppleSpeechBackend: TranscriptionBackend {
    /// Fed to the analyser in chunks rather than one buffer, matching how a live microphone delivers.
    private static let chunkFrames = 4096

    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    /// The analyser holds back no end-of-clip window, so it takes whatever the engine's own floor lets through.
    public nonisolated var minimumDuration: Duration { .zero }

    /// Whether the system can recognise a language at all.
    public static func supports(_ language: LanguageCode) async -> Bool {
        await SpeechTranscriber.supportedLocales
            .contains { LanguageCode($0.identifier(.bcp47)) == language }
    }

    /// The audio format the analyser reads, found once the locale's assets are installed.
    private var format: AVAudioFormat?
    /// A transcriber and analyser already prepared for the next piece, so it pays no setup.
    private var ready: Pair?

    /// One analyser run: an analyser is finished after one clip, so each piece takes a fresh pair.
    private struct Pair {
        let transcriber: SpeechTranscriber
        let analyzer: SpeechAnalyzer
    }

    /// Installs the locale's assets and prepares the first pair, once per lifetime. See Docs/speech-engines.md.
    public func load() async throws(SpeechEngineError) {
        guard format == nil else { return }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            break
        case .unsupported:
            throw .modelLoadFailed(description: "\(locale.identifier) is not supported on this Mac")
        case .supported, .downloading:
            do {
                try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?
                    .downloadAndInstall()
            } catch {
                throw .modelDownloadFailed(description: error.localizedDescription)
            }
        @unknown default:
            throw .modelLoadFailed(description: "unrecognised asset state")
        }
        guard let offered = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { throw .modelLoadFailed(description: "the recogniser offered no audio format") }
        format = offered
        ready = try? await Self.preparedPair(locale: locale, format: offered)
    }

    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await load()
        guard let format else {
            throw .modelLoadFailed(description: "the recogniser offered no audio format")
        }

        do {
            let pair: Pair
            if let prepared = ready {
                ready = nil
                pair = prepared
            } else {
                pair = try await Self.preparedPair(locale: locale, format: format)
            }
            defer { prepareNext(format: format) }
            return try await run(samples, on: pair, format: format)
        } catch let error as SpeechEngineError {
            forget()
            throw error
        } catch {
            forget()
            throw .transcriptionFailed(description: error.localizedDescription)
        }
    }

    /// Feeds one clip through a prepared pair and gathers its final text.
    private func run(_ samples: [Float], on pair: Pair, format: AVAudioFormat) async throws -> RawTranscript {
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        // Start collecting before feeding: results arrive while audio is analysed.
        async let text = Self.collect(pair.transcriber.results)

        try await pair.analyzer.start(inputSequence: stream)
        for chunk in samples.chunked(into: Self.chunkFrames) {
            guard let buffer = AnalyserInput.buffer(chunk, format: format) else {
                continuation.finish()
                throw SpeechEngineError.transcriptionFailed(description: "could not build an input buffer")
            }
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        continuation.finish()
        try await pair.analyzer.finalizeAndFinishThroughEndOfInput()

        return RawTranscript(
            text: try await text,
            languageIdentifier: locale.language.languageCode?.identifier,
            // The system reports a verdict per locale, never a probability.
            languageProbability: nil
        )
    }

    /// Prepares the next piece's pair after this one answers, off the wait for the words.
    private func prepareNext(format: AVAudioFormat) {
        let locale = locale
        Task {
            guard let pair = try? await Self.preparedPair(locale: locale, format: format) else { return }
            self.keep(pair)
        }
    }

    private func keep(_ pair: Pair) {
        if ready == nil, format != nil { ready = pair }
    }

    /// Drops everything learned, so the next call checks the assets and the format again.
    private func forget() {
        format = nil
        ready = nil
    }

    private static func preparedPair(locale: Locale, format: AVAudioFormat) async throws -> Pair {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        return Pair(transcriber: transcriber, analyzer: analyzer)
    }

    private static func collect(
        _ results: some AsyncSequence<SpeechTranscriber.Result, any Error> & Sendable
    ) async throws -> String {
        var pieces: [String] = []
        for try await result in results where result.isFinal {
            pieces.append(String(result.text.characters))
        }
        return pieces.joined(separator: " ")
    }
}

extension Array {
    /// Splits into consecutive slices of at most `size` elements.
    fileprivate func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

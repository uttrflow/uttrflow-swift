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

    /// Whether the system can recognise a language at all.
    public static func supports(_ language: LanguageCode) async -> Bool {
        await SpeechTranscriber.supportedLocales
            .contains { LanguageCode($0.identifier(.bcp47)) == language }
    }

    /// Prepares the recogniser, downloading its locale asset if absent. See Docs/speech-engines.md.
    public func load() async throws(SpeechEngineError) {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
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
    }

    public func transcribe(
        _ samples: [Float], languageHint: LanguageCode?
    ) async throws(SpeechEngineError) -> RawTranscript {
        try await load()

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else { throw .modelLoadFailed(description: "the recogniser offered no audio format") }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        do {
            // Start collecting before feeding: results arrive while audio is analysed.
            async let text = Self.collect(transcriber.results)

            try await analyzer.start(inputSequence: stream)
            for chunk in samples.chunked(into: Self.chunkFrames) {
                guard let buffer = Self.buffer(chunk, format: format) else {
                    continuation.finish()
                    throw SpeechEngineError.transcriptionFailed(
                        description: "could not build an input buffer")
                }
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()

            return RawTranscript(
                text: try await text,
                languageIdentifier: locale.language.languageCode?.identifier,
                // The system reports a verdict per locale, never a probability.
                languageProbability: nil
            )
        } catch let error as SpeechEngineError {
            throw error
        } catch {
            throw .transcriptionFailed(description: error.localizedDescription)
        }
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

    /// Wraps canonical float samples in the interleaved 16-bit buffer the analyser asks for.
    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
            )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let int16 = buffer.int16ChannelData {
            for (index, sample) in samples.enumerated() {
                int16[0][index] = Int16(clampingAudioSample: sample)
            }
            return buffer
        }
        if let float = buffer.floatChannelData {
            for (index, sample) in samples.enumerated() { float[0][index] = sample }
            return buffer
        }
        return nil
    }
}

extension Array {
    /// Splits into consecutive slices of at most `size` elements.
    fileprivate func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

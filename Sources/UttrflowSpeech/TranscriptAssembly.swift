// The recogniser-independent steps between framework output and the transcript.
import UttrflowCore

/// One WhisperKit window reduced to values that carry into the raw transcript.
struct WhisperTranscriptWindow: Sendable {
    let text: String
    let languageIdentifier: String?
    let segments: [RawSegment]
    let effort: DecodeEffort
    let tokensUsed: Int
    let promptPositions: Int
    let vocabularyPrompt: [String]
    var conditioning: DecodeConditioning = .available
}

/// One result from Apple's recogniser, with its finality kept as plain data.
struct FinalTranscriptPiece: Sendable {
    let text: String
    let isFinal: Bool
    let segment: RawSegment?

    init(text: String, isFinal: Bool, segment: RawSegment? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.segment = segment
    }
}

/// Joins framework results after their values have crossed the recogniser boundary.
enum TranscriptAssembly {
    /// Flattens ordered WhisperKit windows while retaining their reported values.
    static func whisper(_ windows: [WhisperTranscriptWindow]) -> RawTranscript {
        RawTranscript(
            text: windows.map(\.text).joined(separator: " "),
            languageIdentifier: windows.first?.languageIdentifier,
            languageProbability: nil,
            segments: windows.flatMap(\.segments),
            effort: windows.reduce(.none) { $0.adding($1.effort) },
            tokensUsed: windows.reduce(0) { $0 + $1.tokensUsed },
            promptPositions: windows.first?.promptPositions ?? 0,
            vocabularyPrompt: windows.first?.vocabularyPrompt ?? [],
            conditioning: windows.reduce(.available) { $0.adding($1.conditioning) })
    }

    /// Joins only final Apple results in the order the recogniser emitted them.
    static func finalText(from pieces: [FinalTranscriptPiece]) -> String {
        pieces.filter(\.isFinal).map(\.text).joined(separator: " ")
    }

    /// Joins final Apple results and retains timing/confidence data only where it was reported.
    static func apple(from pieces: [FinalTranscriptPiece]) -> RawTranscript {
        let final = pieces.filter(\.isFinal)
        return RawTranscript(
            text: final.map(\.text).joined(separator: " "),
            segments: final.compactMap(\.segment))
    }
}

extension Array {
    /// Splits into consecutive slices of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

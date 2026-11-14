// What a piece is decoded and tidied after, made in one place for every path. See `Docs/early-transcription.md`.
import UttrflowCore

/// The previous piece's words as corrected and not yet tidied, which every path has once a piece is corrected.
struct RollingContext: Sendable, Equatable {
    let text: String

    /// A run of this many words shared with the context before it marks a piece that echoed its own prompt.
    static let echoWords = 6
    /// Whisper's own limits: above this compression ratio a segment is a repetition loop.
    static let loopCompressionRatio = 2.4
    /// Whisper's own limits: a segment above this no-speech probability and below this mean log-probability holds no speech.
    static let silenceProbability = 0.6
    static let silenceLogProbability = -1.0

    /// The context the next piece reads after these words, or `nil` when they said nothing.
    init?(after corrected: CorrectedTranscript) {
        guard corrected.text.contains(where: { !$0.isWhitespace }) else { return nil }
        text = corrected.text
    }

    /// What follows a corrected piece: its words, nothing new, or none because it echoed `previous` or scored as a loop.
    static func carried(
        after corrected: CorrectedTranscript, heard: Transcription, following previous: RollingContext?
    ) -> Carried {
        guard let own = RollingContext(after: corrected) else { return .nothing }
        guard heard.segments.allSatisfy({ isReliable($0.reliability) }) else { return .withheld }
        if let previous, sharesRun(own.text, with: previous.text) { return .withheld }
        return .context(own)
    }

    /// What the piece after a corrected one is decoded and tidied after.
    enum Carried: Sendable, Equatable {
        /// The piece said nothing, so the context before it still stands.
        case nothing
        /// The piece cannot be trusted as conditioning, so there is none.
        case withheld
        case context(RollingContext)

        func after(_ previous: RollingContext?) -> RollingContext? {
            switch self {
            case .nothing: previous
            case .withheld: nil
            case .context(let context): context
            }
        }
    }

    private static func isReliable(_ reliability: SegmentReliability?) -> Bool {
        guard let reliability else { return true }
        if reliability.compressionRatio > loopCompressionRatio { return false }
        let holdsNoSpeech =
            reliability.noSpeechProbability > silenceProbability
            && reliability.averageLogProbability < silenceLogProbability
        return !holdsNoSpeech
    }

    /// Whether `text` holds `echoWords` words in a row that `earlier` also holds, by their letters alone.
    private static func sharesRun(_ text: String, with earlier: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map {
                $0.lowercased().filter { $0.isLetter || $0.isNumber }
            }.filter { !$0.isEmpty }
        }
        let now = words(text)
        let before = words(earlier)
        guard now.count >= echoWords, before.count >= echoWords else { return false }
        var runs: Set<[String]> = []
        for start in 0...(before.count - echoWords) { runs.insert(Array(before[start..<start + echoWords])) }
        return (0...(now.count - echoWords)).contains { runs.contains(Array(now[$0..<$0 + echoWords])) }
    }
}

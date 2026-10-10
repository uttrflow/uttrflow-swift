// The pieces a live dictation and a retry of its kept recording cut the same audio into.
public import UttrflowCore

/// How the live path and the retry path window one recording, so the two can be decoded and compared.
public enum RetryParity {
    /// The samples a retry reads back: each one stored as 16-bit PCM and decoded as the recording file does.
    public static func roundTripped(_ samples: [Float]) -> [Float] {
        samples.map { Float(Int16(clampingAudioSample: $0)) / Float(Int16.max) }
    }

    /// The pieces a live dictation cuts while the key is held, one cut per poll, then the remainder at key-up.
    public static func livePieces(
        _ samples: [Float], sampleRate: Int, pollSamples: Int, windowing: SpeechWindowing = .standard
    ) -> [Range<Int>] {
        guard pollSamples > 0 else { return windowing.windows(in: samples, sampleRate: sampleRate) }
        var pieces: [Range<Int>] = []
        var cut = 0
        var lastStart: Int?
        var captured = pollSamples
        while captured < samples.count {
            // One sample before the cut is kept, as the pipeline does, so a later piece is never the whole recording.
            let lead = cut > 0 ? 1 : 0
            let heard = Array(samples[(cut - lead)..<captured])
            if let end = windowing.nextCut(in: heard, sampleRate: sampleRate, from: lead) {
                lastStart = cut
                pieces.append(cut..<(cut - lead + end))
                cut = cut - lead + end
            }
            captured += pollSamples
        }
        let remainder = windowing.windows(
            in: samples, sampleRate: sampleRate, from: cut, joiningPreviousWindowFrom: lastStart)
        // A fragment left at key-up joins the piece before it, which is then decoded again.
        if let first = remainder.first, first.lowerBound < cut, !pieces.isEmpty { pieces.removeLast() }
        if pieces.isEmpty, remainder.isEmpty { return [cut..<samples.count] }
        return pieces + remainder
    }

    /// The pieces a retry cuts, in one pass over the whole recording read back from disk.
    public static func retryPieces(
        _ samples: [Float], sampleRate: Int, windowing: SpeechWindowing = .standard
    ) -> [Range<Int>] {
        let windows = windowing.windows(in: samples, sampleRate: sampleRate)
        return windows.isEmpty ? [0..<samples.count] : windows
    }
}

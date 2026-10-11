// How the live piece cutter treats one clip at one pace, with no recogniser involved.
public import UttrflowCore

/// The pieces `SpeechWindowing` cuts one clip into, and where its cuts fall.
public struct PaceStructure: Sendable, Equatable {
    /// Pieces the clip is cut into.
    public let pieces: Int
    /// Cuts that end a piece sooner than `SpeechWindowing.minimumLength` after it began.
    public let earlyCuts: Int
    /// Where each cut falls, in seconds from the start of the clip.
    public let cuts: [Double]
    /// Speech seconds in the clip, by the same trim the recogniser is given.
    public let speechSeconds: Double

    /// Cuts `samples` the way a finished recording is cut.
    public init(samples: [Float], sampleRate: Int, windowing: SpeechWindowing = .standard) {
        let windows = windowing.windows(in: samples, sampleRate: sampleRate)
        let rate = Double(sampleRate)
        pieces = windows.count
        cuts = windows.dropLast().map { Double($0.upperBound) / rate }
        earlyCuts = windows.dropLast().filter { Double($0.count) < windowing.minimumLength * rate }.count
        speechSeconds =
            AudioSamples(samples: samples, sampleRate: sampleRate)?.speechOnly()
            .map { $0.audio.duration.inSeconds } ?? 0
    }

    /// How many cuts fall strictly inside one of `words`, each a start and end in seconds.
    public func cutsInsideWords(_ words: [ClosedRange<Double>]) -> Int {
        cuts.filter { cut in words.contains { $0.lowerBound < cut && cut < $0.upperBound } }.count
    }
}

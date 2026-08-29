/// The language a speech engine believes it heard.
///
/// Confidence is optional because recognisers differ: some report a probability,
/// others only a verdict. Encoding "did not say" as zero would read as "certainly
/// wrong" to anything that routes on it.
public struct DetectedLanguage: Hashable, Sendable, Codable {
    public let code: LanguageCode
    /// Engine-reported confidence, clamped to `0...1`, or `nil` when it reports none.
    public let confidence: Double?

    public init(code: LanguageCode, confidence: Double? = nil) {
        self.code = code
        self.confidence = confidence?.clampedToUnitInterval
    }
}

extension Double {
    /// Clamps to `0...1`, mapping non-finite values to `0`.
    var clampedToUnitInterval: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}

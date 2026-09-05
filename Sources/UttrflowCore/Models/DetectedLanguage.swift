/// The language a speech engine believes it heard; confidence is optional because "did not say" is not zero.
public struct DetectedLanguage: Hashable, Sendable, Codable {
    /// The language.
    public let code: LanguageCode
    /// Engine-reported confidence, clamped to `0...1`, or `nil` when it reports none.
    public let confidence: Double?

    /// A verdict, with a confidence when the engine gives one.
    public init(code: LanguageCode, confidence: Double? = nil) {
        self.code = code
        self.confidence = confidence?.clampedToUnitInterval
    }
}

/// The clamp a confidence goes through.
extension Double {
    /// Clamps to `0...1`, mapping non-finite values to `0`.
    var clampedToUnitInterval: Double {
        guard isFinite else { return 0 }
        return Swift.min(Swift.max(self, 0), 1)
    }
}

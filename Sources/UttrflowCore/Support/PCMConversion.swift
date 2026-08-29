extension Int16 {
    /// Converts a normalised audio sample in `-1...1` to 16-bit PCM.
    ///
    /// Clamps rather than wrapping: resampling routinely nudges a sample just past
    /// the limit, and wrapping turns a loud moment into a loud click. A non-finite
    /// sample becomes silence, which is the only safe reading of it.
    public init(clampingAudioSample sample: Float) {
        guard sample.isFinite else {
            self = 0
            return
        }
        let scaled = (sample * Float(Int16.max)).rounded()
        self = Int16(Swift.min(Swift.max(scaled, Float(Int16.min)), Float(Int16.max)))
    }
}

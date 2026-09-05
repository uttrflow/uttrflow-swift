/// The one conversion from normalised float audio to 16-bit PCM.
extension Int16 {
    /// A normalised sample as 16-bit PCM, clamped so an overshoot is loud, not a click; `nan` is silence.
    public init(clampingAudioSample sample: Float) {
        guard sample.isFinite else {
            self = 0
            return
        }
        let scaled = (sample * Float(Int16.max)).rounded()
        self = Int16(Swift.min(Swift.max(scaled, Float(Int16.min)), Float(Int16.max)))
    }
}

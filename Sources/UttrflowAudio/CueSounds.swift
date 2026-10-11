// The recording cues, one line each; change a sound here and nowhere else. See `Docs/audio-capture.md`.
import Foundation

/// A system sound reshaped at play time: pitched by varispeed, softened by a low-pass, then scaled.
public struct CueSound: Hashable, Sendable {
    /// The macOS sound to start from, looked up by name the way `NSSound(named:)` finds it.
    public let sound: SystemSound
    /// Semitones to shift by; negative is lower, and the sound lengthens as it drops, like a slowed tape.
    public let semitones: Double
    /// The low-pass cutoff in hertz.
    public let lowPassHz: Double
    /// Linear gain from 0 to 1.
    public let volume: Float

    public init(_ name: String, semitones: Double, lowPassHz: Double, volume: Float) {
        sound = SystemSound(name)
        self.semitones = semitones
        self.lowPassHz = lowPassHz
        self.volume = volume
    }

    /// Played when the microphone goes live.
    public static let start = CueSound("Pop", semitones: -3, lowPassHz: 3000, volume: 0.7)

    /// Played when the recording ends.
    public static let stop = CueSound("Tink", semitones: -9, lowPassHz: 2200, volume: 0.7)

    /// Played once when the recording reaches its warning point.
    public static let warning = CueSound("Glass", semitones: -3, lowPassHz: 3000, volume: 0.7)

    /// Played when a recording is cancelled: lower and quieter than the stop, so it is not mistaken for one.
    public static let discarded = CueSound("Bottle", semitones: -7, lowPassHz: 1800, volume: 0.5)

    /// The low-pass resonance in decibels, the unit a browser's biquad reads its `Q` in.
    public static let lowPassResonanceDecibels = 0.5

    /// How much faster the source is read: 2^(semitones/12), so -12 plays at half speed and twice the length.
    public var playbackRate: Double { pow(2, semitones / 12) }
}

import CoreGraphics
import Foundation

/// Turns what the microphone is doing into what the meter draws.
///
/// Pure and free of SwiftUI on purpose. The old waveform was seventeen bars running a
/// canned `easeInOut` loop — the same animation whether somebody shouted, whispered or
/// said nothing at all — and the reason that was never noticed is that there was nothing
/// to test. Every decision the meter makes now lives here, where a test can hold it to
/// account.
enum DockLevel {
    /// The quietest signal the meter shows at all, in dBFS.
    ///
    /// Speech at a normal distance from a laptop microphone sits around −30 dBFS and
    /// room tone around −55. Anchoring the floor at −50 puts a spoken sentence in the
    /// upper half of the meter and leaves silence flat, which is the distinction the
    /// meter exists to draw.
    static let floorDecibels: Float = -50

    /// Maps a root-mean-square level in `0...1` onto the bar scale, also `0...1`.
    ///
    /// Decibels rather than the raw amplitude: hearing is logarithmic, and a linear
    /// meter spends nine tenths of its travel on the loudest tenth of speech, so it
    /// looks broken — barely moving, then slamming to full.
    static func scale(rms: Float) -> CGFloat {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels.isFinite else { return 0 }
        let normalised = (decibels - floorDecibels) / -floorDecibels
        return CGFloat(min(max(normalised, 0), 1))
    }
}

/// The row of capsules, one per arrival.
///
/// A bar here is a *moment*, not a sample of a curve: each 20 Hz arrival pushes one
/// entry and every entry then walks across the panel until it falls off the far end. That
/// is what makes the meter a recording of the last second rather than a decoration that
/// happens to wobble — the horizontal axis is time, and every bar on screen is something
/// that was actually said.
///
/// Newest first, so index zero is the edge where sound arrives and the walk is a simple
/// increasing offset.
struct DockBars {
    /// Enough to fill the widest meter with two to spare, so a bar exists to enter from
    /// beyond the edge and one to leave past it.
    static let capacity = 24

    /// Above this, a bar takes the mark's accent instead of the waveform teal.
    ///
    /// Half scale, chosen because it is the only threshold that needs no explanation.
    /// It is worth being clear about what it does and does not mean: it says this instant
    /// was louder than half, and nothing more. It is not a second measurement and the
    /// meter has no second thing to measure — one microphone, one number.
    static let accentThreshold: CGFloat = 0.5

    private(set) var levels: [CGFloat]

    init() { levels = Array(repeating: 0, count: Self.capacity) }

    /// Takes one arrival. Anything outside the scale is clamped rather than drawn.
    mutating func arrive(_ level: CGFloat) {
        levels.insert(min(max(level, 0), 1), at: 0)
        if levels.count > Self.capacity { levels.removeLast() }
    }

    /// Empties the row, so a new dictation cannot open showing the end of the last one.
    mutating func clear() { levels = Array(repeating: 0, count: Self.capacity) }

    /// Which of the app's two teals a bar is drawn in.
    static func isLoud(_ level: CGFloat) -> Bool { level > accentThreshold }
}

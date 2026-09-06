// Microphone level to meter height, and the row of bars the meter draws.

import CoreGraphics
import Foundation

/// Turns what the microphone is doing into what the meter draws; pure, so a test can hold it to account.
enum DockLevel {
    /// The quietest signal shown, in dBFS: speech sits around −30, room tone around −55.
    static let floorDecibels: Float = -50

    /// Maps an RMS level in `0...1` onto the bar scale in decibels, because hearing is logarithmic.
    static func scale(rms: Float) -> CGFloat {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels.isFinite else { return 0 }
        let normalised = (decibels - floorDecibels) / -floorDecibels
        return CGFloat(min(max(normalised, 0), 1))
    }
}

/// The row of capsules, one per 20 Hz arrival, newest first; the horizontal axis is time.
struct DockBars {
    /// Enough to fill the widest meter with one bar entering and one leaving.
    static let capacity = 24

    /// Above this a bar takes the mark's accent: half scale, the one threshold needing no explanation.
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

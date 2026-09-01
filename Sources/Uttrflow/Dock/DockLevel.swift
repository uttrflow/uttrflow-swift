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

/// Eight bars following one signal, each at its own rate.
///
/// There is one microphone and therefore one number, so a row of bars claiming to be a
/// spectrum would be the original lie in a new shape. What each bar honestly *can* be is
/// a differently damped follower of the real level: they all rise together the instant
/// you speak, and fall at their own speeds afterwards, the way a row of resonators
/// would. The result moves like something being driven rather than something being
/// played back.
///
/// The damping is deliberately **not** ordered along the row. Neighbours that lag each
/// other in sequence read as a single wave travelling across the panel — motion the
/// microphone never made, and the exact effect this design was asked to remove — so the
/// rates are scattered instead, and no two adjacent bars are near each other's.
struct DockMeter {
    /// How much of a bar's height survives one update with nothing being said.
    ///
    /// Scattered, not sorted. Sorting these is what would reintroduce the travelling
    /// wave, so the order is part of the design rather than an accident of writing them
    /// down.
    static let damping: [CGFloat] = [0.55, 0.78, 0.62, 0.86, 0.58, 0.81, 0.66, 0.73]

    /// A fixed share of the level each bar shows, so the row has a shape at all.
    ///
    /// Without this the meter has a failure mode that only appears on a *sustained*
    /// sound: attack is immediate for every bar, so while the level holds steady they
    /// all sit at exactly the same height and the row becomes a solid block. Speech
    /// fluctuates enough to hide it most of the time, and a held vowel does not.
    ///
    /// This is a fixed face rather than anything measured — the meter is one number and
    /// says so — which is why the profile never changes and never moves. Scattered for
    /// the same reason the damping is: a smooth hump would imply a spectrum, and a
    /// gradient across the row would read as travel.
    static let gain: [CGFloat] = [0.74, 1.0, 0.82, 0.93, 0.68, 0.97, 0.78, 0.88]

    /// The fraction of full height a bar shows when its follower is at zero, so the row
    /// reads as a resting meter rather than as a panel with nothing in it.
    static let floor: CGFloat = 0.12

    private(set) var heights: [CGFloat]

    init() {
        heights = Array(repeating: Self.floor, count: Self.damping.count)
    }

    var count: Int { Self.damping.count }

    /// Advances every follower towards the level just measured.
    ///
    /// Attack is immediate: a bar jumps to the new level the moment that level is higher
    /// than where the bar already is. Only the fall is damped, which is what makes the
    /// row arrive together and disperse.
    mutating func advance(to level: CGFloat) {
        let level = min(max(level, 0), 1)
        for index in heights.indices {
            let target = level * Self.gain[index]
            let released = heights[index] * Self.damping[index]
            heights[index] = max(max(target, released), Self.floor)
        }
    }

    /// Freezes the row where it stands, for the hand-over from listening to working.
    ///
    /// The panel must not change shape at the moment the key is released — a box that
    /// jumps exactly when somebody stops talking reads as an error even when nothing
    /// went wrong — so the last real frame of their voice is what the working animation
    /// starts from.
    func frozen() -> [CGFloat] { heights }
}

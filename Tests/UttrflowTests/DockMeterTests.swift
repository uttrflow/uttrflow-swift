import CoreGraphics
import Foundation
import Testing

@testable import Uttrflow

/// The old waveform was seventeen bars running a canned loop — the same animation
/// whether somebody shouted, whispered or said nothing at all — and nothing caught it
/// because there was nothing to catch. These are the claims the new meter makes, written
/// down so it cannot quietly go back to being a decoration.
@Suite("The level the floating button draws")
struct DockLevelTests {
    @Test("silence is flat")
    func silenceIsFlat() {
        #expect(DockLevel.scale(rms: 0) == 0)
    }

    @Test("a signal at or below the floor is flat")
    func floorIsFlat() {
        // −50 dBFS, the quietest thing the meter shows at all.
        #expect(DockLevel.scale(rms: 0.00316) < 0.01)
        #expect(DockLevel.scale(rms: 0.0001) == 0)
    }

    @Test("full scale is full")
    func fullScaleIsFull() {
        #expect(DockLevel.scale(rms: 1) == 1)
    }

    /// The reason for using decibels at all. Speech at a laptop microphone sits around
    /// −30 dBFS, which is an amplitude of about 0.03 — on a linear meter that is three
    /// percent of the travel, and the meter looks broken.
    @Test("ordinary speech lands in the upper half, not the bottom three percent")
    func speechIsVisible() {
        let speech = DockLevel.scale(rms: 0.0316)  // −30 dBFS
        #expect(speech > 0.35)
        #expect(speech < 0.75)
    }

    @Test("louder is always higher")
    func monotonic() {
        var previous: CGFloat = -1
        for step in stride(from: 0.005, through: 1.0, by: 0.05) {
            let value = DockLevel.scale(rms: Float(step))
            #expect(value >= previous)
            previous = value
        }
    }

    /// A microphone can hand over a block that fails to convert. A meter that answered
    /// with a non-finite height would take the whole panel's layout with it — and an
    /// unreadable sample is not a loud one, so the meter goes flat rather than full.
    /// Flat is at worst "I am not hearing you", which is recoverable; full scale on
    /// garbage would be the panel telling somebody they are being heard.
    @Test("a broken sample reads as flat, not as loud")
    func rejectsNonFinite() {
        #expect(DockLevel.scale(rms: .nan) == 0)
        #expect(DockLevel.scale(rms: .infinity) == 0)
        #expect(DockLevel.scale(rms: .signalingNaN) == 0)
        #expect(DockLevel.scale(rms: -1) == 0)
    }
}

@Suite("The bars that follow it")
struct DockMeterTests {
    @Test("starts at a resting row rather than at nothing")
    func startsAtFloor() {
        let meter = DockMeter()

        #expect(meter.heights.count == 8)
        #expect(meter.heights.allSatisfy { $0 == DockMeter.floor })
    }

    /// Attack is immediate, and this is the property that makes the meter feel connected
    /// to the voice rather than trailing it.
    @Test("every bar rises on the first loud frame")
    func attackIsImmediate() {
        var meter = DockMeter()

        meter.advance(to: 0.9)

        #expect(meter.heights.allSatisfy { $0 > DockMeter.floor })
        #expect(meter.heights.max()! > 0.8)
    }

    /// The failure a still frame finds and a moving one hides. Attack is immediate for
    /// every bar, so on a held vowel — where the level stops changing — a meter with no
    /// fixed profile has all eight bars at the same height and draws a solid block.
    @Test("a sustained level still has a shape, rather than becoming a wall")
    func sustainedLevelIsNotFlat() {
        var meter = DockMeter()

        for _ in 0..<20 { meter.advance(to: 0.8) }

        #expect(Set(meter.heights).count > 4, "\(meter.heights) is flat")
    }

    /// And the profile is a face, not a reading: it must not imply a spectrum, and must
    /// not ramp across the row, which is the travelling wave in another form.
    @Test("the fixed profile is scattered, not a hump and not a ramp")
    func gainIsScattered() {
        let gain = DockMeter.gain

        #expect(gain.count == DockMeter.damping.count)
        #expect(gain != gain.sorted())
        #expect(gain != gain.sorted(by: >))
    }

    /// And the property that makes it look alive rather than like one rigid shape being
    /// scaled: they leave at different speeds.
    @Test("bars fall at their own rates, so the row disperses")
    func releaseIsPerBar() {
        var meter = DockMeter()
        meter.advance(to: 0.9)

        meter.advance(to: 0)

        #expect(Set(meter.heights).count > 1)
        // and specifically because the damping differs, not only because the gain does
        #expect(meter.heights.max()! - meter.heights.min()! > 0.1)
    }

    /// The failure this design was asked to remove. Damping sorted along the row makes
    /// neighbours lag each other in sequence, which the eye reads as one wave travelling
    /// across the panel — so the scatter is a requirement, not a preference.
    @Test("the damping is not ordered along the row")
    func dampingIsScattered() {
        let damping = DockMeter.damping

        #expect(damping != damping.sorted())
        #expect(damping != damping.sorted(by: >))
        for (left, right) in zip(damping, damping.dropFirst()) {
            #expect(abs(left - right) > 0.02, "\(left) and \(right) are neighbours and alike")
        }
    }

    @Test("no bar ever falls below the resting row")
    func neverBelowFloor() {
        var meter = DockMeter()
        meter.advance(to: 1)

        for _ in 0..<200 { meter.advance(to: 0) }

        #expect(meter.heights.allSatisfy { $0 >= DockMeter.floor })
    }

    @Test("a level outside the scale is clamped rather than drawn")
    func clampsOutOfRange() {
        var meter = DockMeter()

        meter.advance(to: 4)

        #expect(meter.heights.allSatisfy { $0 <= 1 })
    }

    /// The hand-over from listening to working starts on the last real frame of the
    /// voice, so the panel does not change shape at the moment the key is released.
    @Test("the frozen row is the row that was on screen")
    func frozenMatchesHeights() {
        var meter = DockMeter()
        meter.advance(to: 0.7)
        meter.advance(to: 0.2)

        #expect(meter.frozen() == meter.heights)
    }
}

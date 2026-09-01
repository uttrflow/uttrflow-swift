import CoreGraphics
import Foundation
import Testing
import UttrflowPipeline

@testable import Uttrflow

/// The old waveform was seventeen bars running a canned loop — the same animation
/// whether somebody shouted, whispered or said nothing at all — and nothing caught it
/// because there was nothing to catch. These are the claims the meter makes now, written
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

@Suite("The row of capsules")
struct DockBarsTests {
    @Test("starts empty, and stays the width it started")
    func startsEmpty() {
        let bars = DockBars()

        #expect(bars.levels.count == DockBars.capacity)
        #expect(bars.levels.allSatisfy { $0 == 0 })
    }

    /// The property the whole design rests on: a bar is a moment. The newest arrival is
    /// at the edge sound comes in at, and everything else has moved one place along.
    @Test("an arrival lands at the front and pushes the rest along")
    func arrivalsLandAtTheFront() {
        var bars = DockBars()

        bars.arrive(0.3)
        bars.arrive(0.9)

        #expect(bars.levels[0] == 0.9)
        #expect(bars.levels[1] == 0.3)
    }

    @Test("the row never grows past what the meter can show")
    func boundedLength() {
        var bars = DockBars()

        for _ in 0..<200 { bars.arrive(0.5) }

        #expect(bars.levels.count == DockBars.capacity)
    }

    @Test("the oldest arrival falls off the end")
    func oldestFallsOff() {
        var bars = DockBars()
        bars.arrive(0.77)

        for _ in 0..<DockBars.capacity { bars.arrive(0.1) }

        #expect(!bars.levels.contains(0.77))
    }

    @Test("a level outside the scale is clamped rather than drawn")
    func clamps() {
        var bars = DockBars()

        bars.arrive(4)
        bars.arrive(-2)

        #expect(bars.levels[0] == 0)
        #expect(bars.levels[1] == 1)
    }

    /// A new dictation must not open showing the tail of the last one.
    @Test("clearing empties the row")
    func clearing() {
        var bars = DockBars()
        for _ in 0..<10 { bars.arrive(0.8) }

        bars.clear()

        #expect(bars.levels.allSatisfy { $0 == 0 })
        #expect(bars.levels.count == DockBars.capacity)
    }

    /// Two teals the app already owns, split at half scale. The threshold says this
    /// instant was louder than half and nothing else — it is not a second measurement,
    /// because there is one microphone and one number.
    /// Hue alone cannot carry this. Measured on the app's own values: the pair
    /// separates at 2.24:1 on a light desktop and at 1.05:1 on a dark one, where the
    /// accent is also the fractionally darker of the two. The weight step is what makes
    /// the threshold survive the ground most desktops actually use, so it has to stay a
    /// real difference rather than a rounding error.
    @Test("quiet bars are held back by enough to see")
    func quietBarsAreHeldBack() {
        #expect(DockMetrics.meterQuietOpacity < 0.75)
        #expect(DockMetrics.meterQuietOpacity > 0.4)
    }

    @Test("half scale is where the accent starts")
    func accentThreshold() {
        #expect(!DockBars.isLoud(0))
        #expect(!DockBars.isLoud(DockBars.accentThreshold))
        #expect(DockBars.isLoud(DockBars.accentThreshold + 0.01))
        #expect(DockBars.isLoud(1))
    }
}

@MainActor
@Suite("What one arrival does to the panel")
struct DockArrivalTests {
    private func model() -> DockViewModel {
        DockViewModel(
            presentation: DictationPresenter.dock(for: .idle), shortcut: "⌥Space",
            anchor: .bottomRight)
    }

    @Test("an arrival records the level, the bar and the moment")
    func meterRecordsAll() {
        let dock = model()
        let when = Date(timeIntervalSinceReferenceDate: 700_000_000)

        dock.meter(0.0316, now: when)  // −30 dBFS

        #expect(dock.level == 0.0316)
        #expect(dock.bars.levels[0] > 0.35)
        #expect(dock.lastArrival == when)
    }

    /// The row has to outlive the microphone by exactly one state: the working animation
    /// settles the bars the voice actually left behind.
    @Test("the row survives the end of a recording")
    func rowSurvivesTheEnd() {
        let dock = model()
        dock.show(DictationPresenter.dock(for: .recording))
        dock.meter(0.5)

        dock.show(DictationPresenter.dock(for: .transcribing))

        #expect(dock.bars.levels[0] > 0)
        #expect(dock.level == 0)
    }

    @Test("and is cleared by the next recording, not by the last one ending")
    func nextRecordingClears() {
        let dock = model()
        dock.show(DictationPresenter.dock(for: .recording))
        dock.meter(0.5)
        dock.show(
            DictationPresenter.dock(
                for: .inserted(
                    DictationOutcome(text: "ship it", method: .accessibility, cleanedBy: .rules))))

        dock.show(DictationPresenter.dock(for: .recording))

        #expect(dock.bars.levels.allSatisfy { $0 == 0 })
    }

    /// A run of identical recording presentations is what arrives while somebody holds
    /// the key. Clearing on each of them would wipe the row sixty times a second.
    @Test("a repeated recording presentation does not wipe the row")
    func repeatedPresentationKeepsTheRow() {
        let dock = model()
        dock.show(DictationPresenter.dock(for: .recording))
        dock.meter(0.5)

        dock.show(DictationPresenter.dock(for: .recording))

        #expect(dock.bars.levels[0] > 0)
    }
}

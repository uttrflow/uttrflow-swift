// Tests for the meter's level, bars and arrivals.

import CoreGraphics
import Foundation
import Testing
import UttrflowPipeline

@testable import Uttrflow

/// The claims the meter makes, written down so it cannot go back to being a decoration.
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

    /// Speech at −30 dBFS is 0.03 amplitude, three percent of a linear meter's travel.
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

    /// A block that fails to convert reads as flat, not loud; flat is at worst "I am not hearing you".
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

    /// A bar is a moment: the newest arrival is at the edge sound comes in at.
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

    /// Quiet bars are held back by weight, because hue alone separates at only 1.05:1 on a dark desktop.
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

    /// The row outlives the microphone by one state, so the working animation settles the real bars.
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

    /// Identical recording presentations arrive while the key is held; clearing on each would wipe the row.
    @Test("a repeated recording presentation does not wipe the row")
    func repeatedPresentationKeepsTheRow() {
        let dock = model()
        dock.show(DictationPresenter.dock(for: .recording))
        dock.meter(0.5)

        dock.show(DictationPresenter.dock(for: .recording))

        #expect(dock.bars.levels[0] > 0)
    }
}

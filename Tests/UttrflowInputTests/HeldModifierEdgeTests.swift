import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Turning flag changes into a press and a release. See `Docs/stuck-recording.md`.
@Suite("Holding a modifier")
struct HeldModifierEdgeTests {
    @Test("the first change to down is a press")
    func downIsAPress() {
        var edge = HeldModifierEdge()
        #expect(edge.flagsChanged(isDownNow: true) == .pressed)
        #expect(edge.isDown)
    }

    /// macOS sends several flag changes for one press: the flags say what they are, not what changed.
    @Test("repeats of the same state are not events")
    func repeatsAreNotEvents() {
        var edge = HeldModifierEdge()
        #expect(edge.flagsChanged(isDownNow: true) == .pressed)
        #expect(edge.flagsChanged(isDownNow: true) == nil)
        #expect(edge.flagsChanged(isDownNow: true) == nil)
        #expect(edge.isDown)
    }

    @Test("letting go is a release, and letting go twice is not")
    func upIsARelease() {
        var edge = HeldModifierEdge()
        _ = edge.flagsChanged(isDownNow: true)
        #expect(edge.flagsChanged(isDownNow: false) == .released)
        #expect(edge.flagsChanged(isDownNow: false) == nil)
        #expect(!edge.isDown)
    }

    @Test("a key that was never down cannot be released")
    func upWithoutDownIsNothing() {
        var edge = HeldModifierEdge()
        #expect(edge.flagsChanged(isDownNow: false) == nil)
        #expect(!edge.isDown)
    }

    @Test("holds one after another are each their own press and release")
    func repeatedHolds() {
        var edge = HeldModifierEdge()
        for _ in 0..<3 {
            #expect(edge.flagsChanged(isDownNow: true) == .pressed)
            #expect(edge.flagsChanged(isDownNow: false) == .released)
        }
    }

    /// The one that keeps the microphone from being left open when watching stops mid-hold.
    @Test("stopping while the key is held still owes a release")
    func stoppingMidHoldReleases() {
        var edge = HeldModifierEdge()
        _ = edge.flagsChanged(isDownNow: true)
        #expect(edge.stopped() == .released)
        #expect(!edge.isDown)
    }

    @Test("stopping when nothing was held owes nothing")
    func stoppingIdleOwesNothing() {
        var edge = HeldModifierEdge()
        #expect(edge.stopped() == nil)

        _ = edge.flagsChanged(isDownNow: true)
        _ = edge.flagsChanged(isDownNow: false)
        #expect(edge.stopped() == nil)
    }

    /// A stop is not a release the key made, so the next press has to start from nothing held.
    @Test("a press after a stop is still a press")
    func pressAfterStopIsAPress() {
        var edge = HeldModifierEdge()
        _ = edge.flagsChanged(isDownNow: true)
        _ = edge.stopped()
        #expect(edge.flagsChanged(isDownNow: true) == .pressed)
    }
}

@Suite("Which held keys the polled state can answer for")
struct PolledStateTests {
    /// Fn arrives as a flags change and never appears in the polled state, so polling it reads "up".
    @Test("will not reconcile a key the polled state does not report, which is how Fn cancelled itself")
    func refusesAKeyTheStateCannotSee() {
        #expect(!HeldModifierMonitor.polledStateReports(.function, whileHeld: []))
        #expect(!HeldModifierMonitor.polledStateReports([.function], whileHeld: [.command]))
    }

    @Test("reconciles a key the polled state does report")
    func reconcilesAKeyTheStateReports() {
        #expect(HeldModifierMonitor.polledStateReports(.command, whileHeld: [.command]))
        #expect(HeldModifierMonitor.polledStateReports([.control, .shift], whileHeld: [.control, .shift]))
        #expect(HeldModifierMonitor.polledStateReports(.option, whileHeld: [.option, .shift]))
    }

    @Test("a partly reported combination is not reconciled, since the missing half would read as up")
    func refusesAPartlyReportedCombination() {
        #expect(!HeldModifierMonitor.polledStateReports([.command, .function], whileHeld: [.command]))
    }
}

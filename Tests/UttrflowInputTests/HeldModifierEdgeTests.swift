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
    /// Fn arrives as a flags change and never shows in the polled state, so polling it reads "up".
    @Test("does not reconcile a held Fn, which polling would report as released mid-hold")
    func refusesToReconcileFunction() {
        #expect(!HeldModifierMonitor.polledStateCanSee(.function))
        #expect(!HeldModifierMonitor.polledStateCanSee([.function, .command]))
    }

    @Test("reconciles every modifier the polled state does report")
    func reconcilesTheRest() {
        #expect(HeldModifierMonitor.polledStateCanSee(.command))
        #expect(HeldModifierMonitor.polledStateCanSee(.option))
        #expect(HeldModifierMonitor.polledStateCanSee([.control, .shift]))
    }
}

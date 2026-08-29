import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Turning flag changes into a press and a release.
///
/// Both rules here fail invisibly. Yielding on every flag change starts a dictation
/// inside a dictation; forgetting the release owed by an interrupted hold leaves the
/// microphone open with nothing on screen saying so.
@Suite("Holding a modifier")
struct HeldModifierEdgeTests {
    @Test("the first change to down is a press")
    func downIsAPress() {
        var edge = HeldModifierEdge()
        #expect(edge.flagsChanged(isDownNow: true) == .pressed)
        #expect(edge.isDown)
    }

    /// macOS sends several flag changes for one press — the flags say what they *are*,
    /// not what changed. Each extra one used to be another press.
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

    /// The one that keeps the microphone from being left open: the shortcut is changed,
    /// or watching stops, while somebody is still holding the key.
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

    /// Stopping is not a release the *key* made, so the next press has to start clean:
    /// a stop that left the edge thinking the key was still down would swallow it.
    @Test("a press after a stop is still a press")
    func pressAfterStopIsAPress() {
        var edge = HeldModifierEdge()
        _ = edge.flagsChanged(isDownNow: true)
        _ = edge.stopped()
        #expect(edge.flagsChanged(isDownNow: true) == .pressed)
    }
}

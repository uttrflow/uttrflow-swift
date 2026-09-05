import Foundation
import Testing

@testable import UttrflowUX

/// When a downloaded update is allowed to replace the running app.
///
/// The rule is worth this much testing because its failures are silent and expensive: an
/// update that installs a second too early takes a sentence somebody was in the middle of
/// saying, and nothing anywhere reports that it happened.
@Suite("Updating: when it may install")
struct UpdateGateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func later(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test("never before anything has been observed")
    func nothingKnownMeansNo() {
        let gate = UpdateGate()
        #expect(!gate.mayInstall(at: start))
        #expect(gate.quietDuration(at: start) == nil)
    }

    @Test("not while the app is doing any of the four things")
    func busyMeansNo() {
        let busy: [UpdateActivity] = [
            UpdateActivity(isDictating: true),
            UpdateActivity(isPanelOpen: true),
            UpdateActivity(isEditing: true),
            UpdateActivity(isOnboarding: true),
        ]
        for activity in busy {
            var gate = UpdateGate()
            gate.note(activity, at: start)
            // Even an hour later: the app never went quiet, so the clock never started.
            #expect(!gate.mayInstall(at: later(3600)), "\(activity) allowed an install")
        }
    }

    @Test("not the instant the app goes quiet")
    func quietIsNotEnoughOnItsOwn() {
        var gate = UpdateGate()
        gate.note(UpdateActivity(), at: start)
        #expect(!gate.mayInstall(at: start))
        #expect(!gate.mayInstall(at: later(59)))
    }

    @Test("once it has been quiet for the settling time")
    func quietForLongEnough() {
        var gate = UpdateGate()
        gate.note(UpdateActivity(), at: start)
        #expect(gate.mayInstall(at: later(60)))
        #expect(gate.mayInstall(at: later(6000)))
    }

    /// The one that matters. A gate that merely paused its clock would install at the
    /// fifty-ninth second of a minute the user never had.
    @Test("anything at all starts the minute again")
    func speakingResetsTheClock() {
        var gate = UpdateGate()
        gate.note(UpdateActivity(), at: start)
        gate.note(UpdateActivity(isDictating: true), at: later(50))
        gate.note(UpdateActivity(), at: later(51))

        #expect(!gate.mayInstall(at: later(60)), "the interrupted minute was allowed to count")
        #expect(!gate.mayInstall(at: later(110)))
        #expect(gate.mayInstall(at: later(111)))
    }

    /// The app reports what it is doing whenever anything redraws, which is often. A gate
    /// that restarted its clock on every report would never open.
    @Test("being told the same quiet thing repeatedly does not restart the minute")
    func repeatedQuietDoesNotResetTheClock() {
        var gate = UpdateGate()
        for second in stride(from: 0.0, through: 59.0, by: 1) {
            gate.note(UpdateActivity(), at: later(second))
        }
        #expect(gate.mayInstall(at: later(60)))
    }

    @Test("says how long it has been quiet, for a page that has to explain the wait")
    func reportsHowLongItHasBeenQuiet() {
        var gate = UpdateGate()
        gate.note(UpdateActivity(), at: start)
        #expect(gate.quietDuration(at: later(30)) == 30)

        gate.note(UpdateActivity(isPanelOpen: true), at: later(31))
        #expect(gate.quietDuration(at: later(32)) == nil)
    }

    @Test("an activity is quiet only when every one of the four is false")
    func quietMeansAllFour() {
        #expect(UpdateActivity().isQuiet)
        #expect(!UpdateActivity(isDictating: true).isQuiet)
        #expect(!UpdateActivity(isPanelOpen: true).isQuiet)
        #expect(!UpdateActivity(isEditing: true).isQuiet)
        #expect(!UpdateActivity(isOnboarding: true).isQuiet)
        #expect(!UpdateActivity(isDictating: true, isOnboarding: true).isQuiet)
    }
}

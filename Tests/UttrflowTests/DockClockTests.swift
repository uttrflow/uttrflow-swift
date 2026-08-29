import Foundation
import UttrflowPipeline
import Testing

@testable import Uttrflow

/// The clock on the floating button is drawn from a moment the window stamps, because
/// when a recording started is a fact about this run of the app rather than about the
/// pipeline's state. Which means the stamping is a decision, and these are the two ways
/// it goes wrong: a clock that restarts under somebody's finger, and one that keeps
/// running after they let go.
@MainActor
@Suite("The clock on the floating button")
struct DockClockTests {
    private func model() -> DockViewModel {
        DockViewModel(
            presentation: DictationPresenter.dock(for: .idle), shortcut: "⌥Space",
            anchor: .bottomRight)
    }

    private let start = Date(timeIntervalSinceReferenceDate: 700_000_000)

    @Test("has no clock until something is being recorded")
    func idleHasNoClock() {
        let dock = model()

        dock.show(DictationPresenter.dock(for: .idle), now: start)

        #expect(dock.recordingStartedAt == nil)
    }

    @Test("starts when the recording does")
    func startsWithTheRecording() {
        let dock = model()

        dock.show(DictationPresenter.dock(for: .recording), now: start)

        #expect(dock.recordingStartedAt == start)
    }

    /// The presentation is handed over again on every redraw, and a run of identical
    /// recording presentations is exactly what arrives while somebody holds the key. A
    /// clock restarted by each of them would sit at nought however long they talked.
    @Test("does not restart while the recording continues")
    func survivesRepeatedPresentations() {
        let dock = model()

        dock.show(DictationPresenter.dock(for: .recording), now: start)
        dock.show(DictationPresenter.dock(for: .recording), now: start.addingTimeInterval(3))
        dock.show(DictationPresenter.dock(for: .recording), now: start.addingTimeInterval(9))

        #expect(dock.recordingStartedAt == start)
    }

    /// And the opposite failure: a clock still counting on a button that has finished is
    /// a button claiming the microphone is open when it is not.
    @Test("stops the moment the recording does")
    func clearedWhenItEnds() {
        let dock = model()

        dock.show(DictationPresenter.dock(for: .recording), now: start)
        dock.show(DictationPresenter.dock(for: .transcribing), now: start.addingTimeInterval(5))

        #expect(dock.recordingStartedAt == nil)
    }

    /// A second dictation is a second clock, not a continuation of the first.
    @Test("the next recording starts a new clock")
    func nextRecordingRestarts() {
        let dock = model()
        let later = start.addingTimeInterval(120)

        dock.show(DictationPresenter.dock(for: .recording), now: start)
        dock.show(DictationPresenter.dock(for: .idle), now: start.addingTimeInterval(6))
        dock.show(DictationPresenter.dock(for: .recording), now: later)

        #expect(dock.recordingStartedAt == later)
    }
}

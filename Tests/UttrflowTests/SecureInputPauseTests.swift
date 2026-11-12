// Secure keyboard entry pauses suggestions once per change, and a recheck lifts the pause in the same app.

import Foundation
import Synchronization
import Testing
import UttrflowInput

@testable import Uttrflow

@MainActor
@Suite struct SecureInputPauseTests {
    /// What the pause did, in order, and the recheck it scheduled, which the test runs by hand.
    @MainActor
    private final class Recorder {
        var steps: [String] = []
        var recheck: (@MainActor () -> Void)?
        var intervals: [TimeInterval] = []
    }

    /// Whether secure keyboard entry is on, as the system would answer.
    private final class Secure: Sendable {
        private let on = Mutex(false)
        var isOn: Bool { on.withLock { $0 } }
        func set(_ value: Bool) { on.withLock { $0 = value } }
    }

    private let secure = Secure()
    private let recorder = Recorder()
    private let pause: SecureInputPause

    init() {
        let secure = secure
        let recorder = recorder
        pause = SecureInputPause(
            watch: SecureInputWatch(isSecureInputOn: { secure.isOn }),
            schedule: { interval, check in
                recorder.intervals.append(interval)
                recorder.recheck = check
                return { recorder.steps.append("stop recheck") }
            })
    }

    private var effects: SecureInputPauseEffects {
        let recorder = recorder
        return SecureInputPauseEffects(
            paused: { recorder.steps.append("paused") },
            resumed: { recorder.steps.append("resumed") })
    }

    @Test("secure entry starting pauses once and schedules one recheck at the ticking interval")
    func startingPausesOnce() {
        secure.set(true)

        pause.check(mayRecheck: true, effects: effects)
        pause.check(mayRecheck: true, effects: effects)

        #expect(recorder.steps == ["paused"])
        #expect(pause.isBlocking)
        #expect(pause.isRecheckScheduled)
        #expect(recorder.intervals == [SuggestionTicking.interval])
    }

    @Test("a recheck that finds secure entry still on does nothing more")
    func recheckWhileOnIsQuiet() {
        secure.set(true)
        pause.check(mayRecheck: true, effects: effects)

        recorder.recheck?()

        #expect(recorder.steps == ["paused"])
        #expect(recorder.intervals.count == 1)
    }

    @Test("a recheck that finds secure entry off stops rechecking before it resumes")
    func recheckLiftsThePause() {
        secure.set(true)
        pause.check(mayRecheck: true, effects: effects)

        secure.set(false)
        recorder.recheck?()

        #expect(recorder.steps == ["paused", "stop recheck", "resumed"])
        #expect(!pause.isBlocking)
        #expect(!pause.isRecheckScheduled)
    }

    @Test("a pause found while stopped schedules no recheck, so nothing wakes a stopped coordinator")
    func stoppedSchedulesNoRecheck() {
        secure.set(true)

        pause.check(mayRecheck: false, effects: effects)

        #expect(recorder.steps == ["paused"])
        #expect(!pause.isRecheckScheduled)
    }

    @Test("stopping the recheck stops its timer once")
    func stopRecheckingStopsTheTimer() {
        secure.set(true)
        pause.check(mayRecheck: true, effects: effects)

        pause.stopRechecking()
        pause.stopRechecking()

        #expect(recorder.steps == ["paused", "stop recheck"])
        #expect(!pause.isRecheckScheduled)
    }

    @Test("nothing happens while secure entry stays off")
    func offStaysQuiet() {
        pause.check(mayRecheck: true, effects: effects)

        #expect(recorder.steps.isEmpty)
        #expect(!pause.isRecheckScheduled)
    }
}

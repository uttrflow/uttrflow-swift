// Tests that tab-to-complete's clock runs only while activity or a drawn suggestion can use it.

import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

/// The clock that notices pauses, which must stop once nothing is happening.
@Suite("When tab-to-complete's clock runs")
struct SuggestionTickingTests {
    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("does not run before anything has happened")
    func idleFromTheStart() {
        let ticking = SuggestionTicking()

        #expect(!ticking.isRunning)
    }

    @Test("starts on the first activity and not again while it runs")
    func startsOnce() {
        var ticking = SuggestionTicking()

        let answer1 = ticking.noteActivity(at: noon)
        #expect(answer1)
        #expect(ticking.isRunning)
        let answer2 = ticking.noteActivity(at: noon.addingTimeInterval(1))
        #expect(!answer2)
    }

    @Test("keeps waking turns inside the window after the last activity")
    func wakesInsideTheWindow() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)

        let answer3 = ticking.tick(
            at: noon.addingTimeInterval(SuggestionTicking.window - 0.5), isShowing: false)
        #expect(answer3)
        #expect(ticking.isRunning)
    }

    @Test("stops once the window has passed with nothing drawn")
    func stopsWhenIdle() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)

        let answer4 = ticking.tick(
            at: noon.addingTimeInterval(SuggestionTicking.window + 0.5), isShowing: false)
        #expect(!answer4)
        #expect(!ticking.isRunning)
    }

    @Test("keeps running past the window while a suggestion is on screen")
    func followsADrawnSuggestion() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)

        let answer5 = ticking.tick(
            at: noon.addingTimeInterval(SuggestionTicking.window * 10), isShowing: true)
        #expect(answer5)
        #expect(ticking.isRunning)
    }

    @Test("restarts on the next activity after stopping, measured from that activity")
    func restarts() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)
        let later = noon.addingTimeInterval(SuggestionTicking.window * 3)
        _ = ticking.tick(at: later, isShowing: false)

        let answer6 = ticking.noteActivity(at: later)
        #expect(answer6)
        let answer7 = ticking.tick(at: later.addingTimeInterval(1), isShowing: false)
        #expect(answer7)
    }

    @Test("a tick after the clock stopped wakes nothing")
    func aStrayTickIsIgnored() {
        var copy = SuggestionTicking()

        let answer8 = copy.tick(at: noon, isShowing: false)
        #expect(!answer8)
    }

    @Test("lasts long enough for the idle commit to be made by a tick")
    func coversTheIdleCommit() {
        #expect(SuggestionTicking.window >= CommitDetector.idleInterval + SuggestionTicking.interval * 2)
    }

    @Test("lasts past the prose pause, which is booked on its own")
    func coversTheProsePause() {
        #expect(SuggestionTicking.window * 1000 > Double(Quieting.proseHesitationInMilliseconds))
    }

    @Test("lets the system move a tick, by less than the interval")
    func carriesATolerance() {
        #expect(SuggestionTicking.tolerance > 0)
        #expect(SuggestionTicking.tolerance < SuggestionTicking.interval)
    }
}

/// The coordinator is wiring, so these read its source to say the clock goes through the tested rule.
@Suite("The suggestion coordinator's clock wiring")
struct SuggestionCoordinatorClockTests {
    private var source: String {
        get throws {
            let file = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift")
            return try String(contentsOf: file, encoding: .utf8)
        }
    }

    @Test("asks SuggestionTicking whether to keep the clock, rather than repeating for ever")
    func goesThroughTheRule() throws {
        let text = try source
        #expect(text.contains("ticking.tick("))
        #expect(text.contains("ticking.noteActivity("))
    }

    @Test("gives the timer a tolerance so the system can coalesce it")
    func setsATolerance() throws {
        #expect(try source.contains("tolerance = SuggestionTicking.tolerance"))
    }
}

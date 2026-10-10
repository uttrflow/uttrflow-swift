// Tests that tab-to-complete observes active fields quickly and visible ghosts slowly.

import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

/// The clock that notices pauses and watches fields beneath visible ghosts.
@Suite("When tab-to-complete's clock runs")
struct SuggestionTickingTests {
    private let noon = ContinuousClock.now

    private func after(_ seconds: Double) -> ContinuousClock.Instant {
        noon.advanced(by: .milliseconds(Int64(seconds * 1_000)))
    }

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
        let answer2 = ticking.noteActivity(at: after(1))
        #expect(!answer2)
    }

    @Test("keeps waking turns inside the window after the last activity")
    func wakesInsideTheWindow() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)

        let answer3 = ticking.tick(
            at: after(SuggestionTicking.window - 0.5), ghostIsVisible: true)
        #expect(answer3 == .wake)
        #expect(ticking.isRunning)
    }

    @Test("stops once the window has passed with nothing drawn")
    func stopsWhenIdle() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)

        let answer4 = ticking.tick(
            at: after(SuggestionTicking.window + 0.5), ghostIsVisible: false)
        #expect(answer4 == .stop)
        #expect(!ticking.isRunning)
    }

    @Test("continues field reads slowly after idle while a ghost remains visible")
    func aDrawnSuggestionKeepsTheSafetyNet() {
        var ticking = SuggestionTicking()
        var session = SuggestionSession()
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextField")
        _ = ticking.noteActivity(at: noon)
        guard
            case .query(let query) = session.turn(
                in: surface, at: PredictionContext(typed: "git c")
            ).step
        else {
            Issue.record("the initial field read should ask for a suggestion")
            return
        }
        let initial = session.resolveGenerated(
            ["git commit -m"], for: query, elapsedMilliseconds: 0,
            scores: ["git commit -m": Verification.certainFloor + 1])
        #expect(initial?.suggestion == .certain("git commit -m"))

        let changedField = "rewritten by the host application"
        let answer5 = ticking.tick(
            at: after(SuggestionTicking.window + 0.5), ghostIsVisible: true)
        #expect(answer5 == .wakeAndSlow)
        if answer5 == .wakeAndSlow {
            let changed = session.turn(in: surface, at: PredictionContext(typed: changedField))
            guard case .query(let changedQuery) = changed.step else {
                Issue.record("the slow tick should re-read the changed field")
                return
            }
            let replacement = session.resolveGenerated(
                [], for: changedQuery, elapsedMilliseconds: 0, whenEmpty: .nothingOffered, scores: [:])
            #expect(replacement?.suggestion == .silent)
            #expect(session.suggestion == .silent)
        }
        #expect(ticking.isRunning)
        #expect(SuggestionTicking.ghostInterval > SuggestionTicking.interval)

        let answer6 = ticking.tick(
            at: after(SuggestionTicking.window + SuggestionTicking.ghostInterval),
            ghostIsVisible: true)
        #expect(answer6 == .wake)
        #expect(ticking.isRunning)

        let answer7 = ticking.tick(
            at: after(SuggestionTicking.window + SuggestionTicking.ghostInterval * 2),
            ghostIsVisible: false)
        #expect(answer7 == .stop)
        #expect(!ticking.isRunning)
    }

    @Test("restarts on the next activity after stopping, measured from that activity")
    func restarts() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)
        let later = after(SuggestionTicking.window * 3)
        _ = ticking.tick(at: later, ghostIsVisible: false)

        let answer6 = ticking.noteActivity(at: later)
        #expect(answer6)
        let answer8 = ticking.tick(at: later.advanced(by: .seconds(1)), ghostIsVisible: true)
        #expect(answer8 == .wake)
    }

    @Test("restores fast field reads after activity during ghost polling")
    func activityRestartsFastPolling() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)
        let later = after(SuggestionTicking.window + 0.5)
        #expect(ticking.tick(at: later, ghostIsVisible: true) == .wakeAndSlow)

        let activity = later.advanced(by: .seconds(1))
        let startedClock = ticking.noteActivity(at: activity)
        #expect(startedClock)
        #expect(ticking.tick(at: activity.advanced(by: .seconds(1)), ghostIsVisible: true) == .wake)
    }

    @Test("checks the caret every 200 ms while active and every 5 s once a visible ghost is idle")
    func selectionCadenceFollowsThePhase() {
        var ticking = SuggestionTicking()
        _ = ticking.noteActivity(at: noon)
        #expect(ticking.selectionInterval == 0.2)

        let later = after(SuggestionTicking.window + 0.5)
        _ = ticking.tick(at: later, ghostIsVisible: true)
        #expect(ticking.selectionInterval == 5)

        _ = ticking.noteActivity(at: later.advanced(by: .seconds(1)))
        #expect(ticking.selectionInterval == 0.2)
    }

    @Test("a tick after the clock stopped wakes nothing")
    func aStrayTickIsIgnored() {
        var copy = SuggestionTicking()

        let answer9 = copy.tick(at: noon, ghostIsVisible: true)
        #expect(answer9 == .stop)
    }

    @Test("lasts long enough for the idle commit to be made by a tick")
    func coversTheIdleCommit() {
        #expect(SuggestionTicking.window >= CommitDetector.idleInterval + SuggestionTicking.interval * 2)
    }

    @Test("lasts past the prose pause, which is booked on its own")
    func coversTheProsePause() {
        #expect(SuggestionTicking.window * 1000 > Double(Quieting.proseHesitationInMilliseconds))
    }

    @Test("keeps slow ticks coalescible")
    func carriesToleranceForGhostTicks() {
        #expect(SuggestionTicking.tolerance > 0)
        #expect(SuggestionTicking.tolerance < SuggestionTicking.ghostInterval)
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
        #expect(try source.contains("timer.tolerance = min(SuggestionTicking.tolerance"))
    }

    @Test("switches to slower field reads while a ghost remains visible")
    func slowsForVisibleGhost() throws {
        let text = try source
        #expect(text.contains("ticking.tick(at: ContinuousClock.now, ghostIsVisible: panel.isShowing)"))
        #expect(text.contains("scheduleTicker(every: SuggestionTicking.ghostInterval)"))
        #expect(text.contains("wake(.tick)"))
    }

    @Test("monotonic elapsed time enforces the turn budget", .bug(id: 5041))
    func monotonicElapsedTimeEnforcesTurnBudget() {
        let started = ContinuousClock.now
        let finished = started.advanced(
            by: .milliseconds(Int64(SuggestionSession.turnBudgetInMilliseconds + 1)))
        let elapsed = SuggestionCoordinator.elapsedMilliseconds(since: started, now: finished)
        var session = SuggestionSession()
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextField")
        guard case .query(let query) = session.turn(in: surface, at: PredictionContext(typed: "git c")).step
        else {
            Issue.record("the initial field read should ask for a suggestion")
            return
        }
        let update = session.resolveGenerated(
            ["git commit -m"], for: query, elapsedMilliseconds: elapsed,
            scores: ["git commit -m": Verification.certainFloor + 1])
        #expect(elapsed == SuggestionSession.turnBudgetInMilliseconds + 1)
        #expect(SuggestionCoordinator.elapsedMilliseconds(since: finished, now: started) == 0)
        #expect(update?.silence == .overBudget)
    }

    @Test("wakes once when dictation ends, including a canceled dictation")
    func dictationEndWakesOnlyOnTransition() throws {
        let text = try source
        let handler = try #require(
            text.components(separatedBy: "func dictationChanged(isDictating: Bool) {").last)
        let body = try #require(handler.components(separatedBy: "\n    }").first)

        #expect(body.contains("guard self.isDictating != isDictating else { return }"))
        #expect(body.contains("guard isDictating else {"))
        #expect(body.contains("captureFeed.noteInsertion()"))
        #expect(body.contains("wake(.tick)"))
        let feed = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/Uttrflow/Suggestion/SuggestionCaptureFeed.swift"),
            encoding: .utf8)
        let noting = try #require(feed.components(separatedBy: "func noteInsertion() {").last)
        #expect(noting.components(separatedBy: "\n    }").first?.contains("insertionPending = true") == true)
    }

    @Test("watches scrolls only once a ghost is drawn, and stops when none is")
    func scrollsWatchedOnlyWithAGhost() throws {
        let text = try source
        #expect(text.contains("watchScrolls()"))
        #expect(text.contains("guard panel.isShowing else { return stopWatchingScrolls() }"))
        #expect(!text.contains("if let scrolls { monitors.append(scrolls) }"))
    }

    @Test("a scroll or a key that keeps focus drops the field's kept frames")
    func keysAndScrollsDropKeptFieldAnswers() throws {
        let text = try source
        let scrolled = try #require(text.components(separatedBy: "private func scrolled() {").last)
        let scrollBody = try #require(scrolled.components(separatedBy: "\n    }").first)
        #expect(scrollBody.contains("FocusedFieldReader.fieldMayHaveChanged()"))
        let keys = try #require(
            text.components(
                separatedBy: "if Self.mayMoveFocus(keyCode: event.keyCode, modifiers: event.modifierFlags) {"
            )
            .last)
        let branch = try #require(keys.components(separatedBy: "self.keyPressed(").first)
        #expect(branch.contains("} else {\n                    FocusedFieldReader.fieldMayHaveChanged()"))
    }

    @Test("withdraws on mouse-up and rereads after a drop reaches the field")
    func mouseUpWithdrawsAndSchedulesFreshRead() throws {
        let text = try source
        #expect(text.contains("matching: [.leftMouseDown, .leftMouseUp]"))
        #expect(text.contains("event.type == .leftMouseUp ? Self.mouseUpReadDelayInMilliseconds : 0"))
        #expect(text.contains("self?.withdraw()"))
        #expect(text.contains("wake(.tick, afterMilliseconds: delay)"))
        #expect(SuggestionCoordinator.mouseUpReadDelayInMilliseconds > 0)
    }
}

/// The coordinator hides a ghost for the whole time a mouse button can move its window.
@Suite("The suggestion coordinator's pointer gesture wiring")
struct SuggestionCoordinatorPointerGestureTests {
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

    @Test("keeps the ghost withdrawn from mouse down through mouse up")
    func hidesDuringPointerGesture() throws {
        let text = try source
        #expect(text.contains("self?.isPointerGestureActive = true"))
        #expect(
            text.contains(
                "} else if event.type == .leftMouseUp {\n                    self?.isPointerGestureActive = false"
            ))
        #expect(
            text.components(separatedBy: "guard !wakeState.isStopped, !isPointerGestureActive").count - 1 == 3
        )
    }
}

/// Quiet mode keeps the drawn line and skips every alternatives path.
@Suite("Quiet suggestion alternative wiring")
struct QuietSuggestionAlternativeWiringTests {
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

    @Test("returns from Quiet mode before machine values are attested")
    func quietReturnsBeforeAttestingAlternatives() throws {
        let text = try source
        let drawnLine = try #require(text.range(of: "await drawFresh(update, for: snapshot, turn: number)"))
        let quietGuard = try #require(
            text.range(
                of: "guard !preferences.isQuiet else { return }", range: drawnLine.upperBound..<text.endIndex)
        )
        let machineValues = try #require(
            text.range(of: "ModelPass.alternativesSource(", range: drawnLine.upperBound..<text.endIndex))
        let alternativesAttestation = try #require(
            text.range(
                of: "let others = await attested(listed, for: query)",
                range: drawnLine.upperBound..<text.endIndex))

        #expect(quietGuard.lowerBound < machineValues.lowerBound)
        #expect(quietGuard.lowerBound < alternativesAttestation.lowerBound)
    }
}

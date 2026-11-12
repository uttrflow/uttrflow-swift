// Each key the tap took is carried out in order, and a stopped tap rests and then starts again.

import Foundation
import Testing
import UttrflowCore
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SwallowedKeyHandlingTests {
    /// Every step the handling took, in order, and what the session answers it.
    @MainActor
    private final class Recorder {
        var steps: [String] = []
        var action: SuggestionAction = .giveBack(KeyStroke(.tab))
        var outcome: UttrflowPredict.AcceptanceOutcome = .inserted
        var isSessionEnabled = true
        var mayRestartTap = true
        var startFailure: KeyInterceptorFailure?
        var insertingDuringTake: Bool?
        /// Called with each rest result, so a test can wait for the restart.
        var onRestResult: (() -> Void)?
    }

    @MainActor
    private final class Tap: SuggestionKeyTap {
        let recorder: Recorder
        init(_ recorder: Recorder) { self.recorder = recorder }
        func arm(_ keys: ArmedKeys) { recorder.steps.append(keys.isEmpty ? "disarm" : "arm") }
        func releaseHeldKeys() { recorder.steps.append("release") }
        func start() throws(KeyInterceptorFailure) {
            recorder.steps.append("start")
            if let failure = recorder.startFailure { throw failure }
        }
        func stop() { recorder.steps.append("stop") }
    }

    private static let typed = "git co"
    private static let tab = KeyStroke(.tab)
    private static let update = SuggestionUpdate(
        suggestion: .certain("git commit"), armed: [.tab], silence: nil)

    private let recorder: Recorder
    private let handling: SwallowedKeyHandling

    init() {
        let recorder = Recorder()
        self.recorder = recorder
        handling = SwallowedKeyHandling(
            tap: Tap(recorder), rest: TapRest(), restDelay: .milliseconds(10),
            giveBack: { [recorder] in recorder.steps.append("give back \($0.key)") })
    }

    private func effects() -> SwallowedKeyEffects {
        let recorder = recorder
        let handling = handling
        return SwallowedKeyEffects(
            route: { _ in
                recorder.steps.append("route")
                return SwallowedKeyRoute(action: recorder.action, typed: Self.typed, reading: nil)
            },
            withdraw: { recorder.steps.append("withdraw") },
            take: { text, route, recordsAcceptance in
                recorder.insertingDuringTake = handling.isInserting
                recorder.steps.append("take \(text) after \(route.typed) recording \(recordsAcceptance)")
                return recorder.outcome
            },
            requestFreshRead: { recorder.steps.append("fresh read") },
            redraw: { recorder.steps.append("redraw \($0.suggestion.accepting ?? "")") },
            noteActivity: { recorder.steps.append("activity") },
            isSessionEnabled: { recorder.isSessionEnabled },
            turnOffEverywhere: { recorder.steps.append("turn off") },
            hidePanel: { recorder.steps.append("hide") },
            mayRestartTap: { recorder.mayRestartTap },
            tapRestChanged: { state in
                switch state {
                case nil: recorder.steps.append("resting")
                case .some(.success): recorder.steps.append("back")
                case .some(.failure): recorder.steps.append("could not restart")
                }
                if state != nil { recorder.onRestResult?() }
            },
            tapRestRestarting: { recorder.steps.append("restarting") })
    }

    @Test func anAcceptTakesTheLineWithTheTapDisarmedAndReleasesHeldKeysAfter() async {
        recorder.action = .accept("git commit")
        await handling.handle(.swallowed(Self.tab), effects: effects())
        #expect(
            recorder.steps == [
                "route", "withdraw", "disarm", "take git commit after git co recording true", "activity",
                "release",
            ])
        #expect(recorder.insertingDuringTake == true)
        #expect(!handling.isInserting)
    }

    @Test func takingOneWordIsNotRecordedAsAnAcceptance() async {
        recorder.action = .acceptWord("git commit")
        await handling.handle(.swallowed(Self.tab), effects: effects())
        #expect(recorder.steps.contains("take git commit after git co recording false"))
    }

    @Test func aRefusedTakeGivesTheAcceptKeyBack() async {
        recorder.action = .accept("git commit")
        recorder.outcome = .refused
        await handling.handle(.swallowed(Self.tab), effects: effects())
        #expect(
            recorder.steps == [
                "route", "withdraw", "disarm", "take git commit after git co recording true", "give back tab",
                "activity", "release",
            ])
    }

    @Test func aTakeThatMayHaveWrittenAsksForAFreshReadAndKeepsTheKey() async {
        recorder.action = .accept("git commit")
        recorder.outcome = .mayHaveWritten
        await handling.handle(.swallowed(Self.tab), effects: effects())
        #expect(
            recorder.steps == [
                "route", "withdraw", "disarm", "take git commit after git co recording true", "fresh read",
                "activity", "release",
            ])
    }

    @Test func aMoveRedrawsAndThenReleasesHeldKeys() async {
        recorder.action = .redraw(Self.update)
        await handling.handle(.swallowed(KeyStroke(.downArrow)), effects: effects())
        #expect(recorder.steps == ["route", "redraw git commit", "release"])
    }

    @Test func aRefusedKeyIsGivenBackAfterWhatItLeftIsDrawn() async {
        recorder.action = .giveBack(Self.tab, after: Self.update)
        await handling.handle(.swallowed(Self.tab), effects: effects())
        #expect(recorder.steps == ["route", "redraw git commit", "give back tab", "release"])
    }

    @Test func aKeyThatTurnsTheSessionOffTurnsTheFeatureOffEverywhereLast() async {
        recorder.action = .redraw(Self.update)
        recorder.isSessionEnabled = false
        await handling.handle(.swallowed(KeyStroke(.escape, modifiers: .option)), effects: effects())
        #expect(recorder.steps == ["route", "redraw git commit", "release", "turn off"])
    }

    @Test func aStoppedTapRestsAndThenStartsAgain() async {
        await withCheckedContinuation { (restarted: CheckedContinuation<Void, Never>) in
            recorder.onRestResult = { restarted.resume() }
            Task { await handling.handle(.stopped(.disabledTwice), effects: effects()) }
        }
        #expect(recorder.steps == ["resting", "disarm", "stop", "hide", "restarting", "start", "back"])
    }

    @Test func aTapThatCannotStartAgainSaysSo() async {
        recorder.startFailure = .accessibilityDenied
        await withCheckedContinuation { (restarted: CheckedContinuation<Void, Never>) in
            recorder.onRestResult = { restarted.resume() }
            Task { await handling.handle(.stopped(.disabledTwice), effects: effects()) }
        }
        #expect(recorder.steps.suffix(3) == ["restarting", "start", "could not restart"])
    }

    @Test func aRestThatMayNotEndLeavesTheTapStopped() async {
        recorder.mayRestartTap = false
        await handling.handle(.stopped(.disabledTwice), effects: effects())
        // A later rest on the same clock fires only after the first one's wait has run out.
        await withCheckedContinuation { (fired: CheckedContinuation<Void, Never>) in
            TapRest().schedule(after: .milliseconds(100)) { fired.resume() }
        }
        #expect(recorder.steps == ["resting", "disarm", "stop", "hide"])
    }

    @Test func watchingHandlesEachEventInTurnUntilStopped() async {
        recorder.action = .redraw(Self.update)
        let (events, continuation) = AsyncStream<InterceptedEvent>.makeStream()
        handling.watch(events, effects: effects())
        continuation.yield(.swallowed(Self.tab))
        continuation.yield(.swallowed(Self.tab))
        while recorder.steps.count < 6 { await Task.yield() }
        handling.stopWatching()
        continuation.yield(.swallowed(Self.tab))
        continuation.finish()
        await Task.yield()
        #expect(
            recorder.steps == [
                "route", "redraw git commit", "release", "route", "redraw git commit", "release",
            ])
    }
}

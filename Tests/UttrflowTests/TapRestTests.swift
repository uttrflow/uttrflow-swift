// A rested tap restarts after its wait, and never once the rest is cancelled.

import AppKit
import Foundation
import os
import Testing
import UttrflowInput
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite(.timeLimit(.minutes(1))) struct TapRestTests {
    @Test func restartsAfterTheWait() async throws {
        let rest = TapRest()
        var restarts = 0
        await withCheckedContinuation { (fired: CheckedContinuation<Void, Never>) in
            rest.schedule(after: .milliseconds(20)) {
                restarts += 1
                fired.resume()
            }
            #expect(rest.isPending)
        }
        #expect(restarts == 1)
        #expect(!rest.isPending)
    }

    @Test func announcesRestartBeforeStartingIt() async throws {
        let rest = TapRest()
        var events: [String] = []
        await withCheckedContinuation { (fired: CheckedContinuation<Void, Never>) in
            rest.schedule(
                after: .milliseconds(20),
                willRestart: { events.append("restarting") }
            ) {
                events.append("started")
                fired.resume()
            }
        }
        #expect(events == ["restarting", "started"])
    }

    @Test func doesNotAnnounceRestartWhenItCannotRun() async throws {
        let rest = TapRest()
        var events: [String] = []
        rest.schedule(
            after: .milliseconds(20),
            shouldRestart: { false },
            willRestart: { events.append("restarting") }
        ) {
            events.append("started")
        }
        await Self.firing(TapRest(), after: .milliseconds(100))
        #expect(events.isEmpty)
        #expect(!rest.isPending)
    }

    @Test func aCancelledRestNeverRestarts() async throws {
        let rest = TapRest()
        var restarts = 0
        rest.schedule(after: .milliseconds(20)) { restarts += 1 }
        rest.cancel()
        #expect(!rest.isPending)
        // A later rest on the same clock fires only after the cancelled one's wait has run out.
        await Self.firing(TapRest(), after: .milliseconds(100))
        #expect(restarts == 0)
    }

    @Test func aSecondRestReplacesTheFirst() async throws {
        let rest = TapRest()
        var restarts = 0
        rest.schedule(after: .milliseconds(20)) { restarts += 1 }
        await withCheckedContinuation { (fired: CheckedContinuation<Void, Never>) in
            // Waits longer than the first, so a first rest left running would have fired by now.
            rest.schedule(after: .milliseconds(100)) {
                restarts += 10
                fired.resume()
            }
        }
        #expect(restarts == 10)
    }

    @Test func stoppingTheCoordinatorCancelsItsRestingTap() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "taprest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        coordinator.tapRest.schedule(after: .seconds(90)) {}
        coordinator.stop()
        #expect(!coordinator.tapRest.isPending)
    }

    @Test func secureEntryCancelsARestingTap() async throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "taprest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let secureOn = OSAllocatedUnfairLock(initialState: false)
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            secureInput: SecureInputWatch { secureOn.withLock { $0 } })
        defer { coordinator.stop() }
        coordinator.start()
        coordinator.tapRest.schedule(after: .seconds(90)) {}
        secureOn.withLock { $0 = true }
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        while coordinator.tapRest.isPending { await Task.yield() }
        #expect(coordinator.isSecureInputBlocking)
    }

    /// Returns once `rest` has restarted after `delay`.
    private static func firing(_ rest: TapRest, after delay: Duration) async {
        await withCheckedContinuation { (fired: CheckedContinuation<Void, Never>) in
            rest.schedule(after: delay) { fired.resume() }
        }
    }
}

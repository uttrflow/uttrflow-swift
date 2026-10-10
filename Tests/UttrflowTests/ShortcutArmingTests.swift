// Tests that a shortcut that could not be armed is kept as its own state until it is armed.

import Foundation
import UttrflowCore
import UttrflowInput
import Testing

@testable import Uttrflow

@MainActor
@Suite("A dictation shortcut that could not be armed")
struct ShortcutArmingTests {
    /// Counts the redraws the arming asks for.
    private final class Redraws {
        var count = 0
    }

    @Test("stays said until a later arming works, then clears")
    func failureStaysUntilArmed() async {
        let redraws = Redraws()
        let arming = ShortcutArming { redraws.count += 1 }

        await arming.arm { () throws(HotkeyError) in throw .shortcutUnavailable }
        #expect(arming.failure == .shortcutUnavailable)
        #expect(
            ShortcutArming.unheard(secureInputBlocking: false, failure: arming.failure)
                == HotkeyError.shortcutUnavailable.userMessage)
        #expect(redraws.count == 1)

        // The retry on activation fails the same way, which is no change to redraw.
        await arming.arm { () throws(HotkeyError) in throw .shortcutUnavailable }
        #expect(redraws.count == 1)

        await arming.arm { () throws(HotkeyError) in }
        #expect(arming.failure == nil)
        #expect(ShortcutArming.unheard(secureInputBlocking: false, failure: arming.failure) == nil)
        #expect(redraws.count == 2)
    }

    @Test("is forgotten when dictation is turned off")
    func disarmingForgetsTheFailure() async {
        let arming = ShortcutArming {}
        await arming.arm { () throws(HotkeyError) in throw .observationNotPermitted }

        arming.disarm()

        #expect(arming.failure == nil)
    }

    @Test("retries after Accessibility permission becomes available")
    func retriesAfterAccessibilityGrant() async throws {
        let permission = Permission()
        let attempts = Attempts()
        let arming = ShortcutArming(
            onChange: {}, accessibilityIsGranted: { permission.granted },
            retryInterval: .milliseconds(10))

        await arming.arm { () throws(HotkeyError) in
            attempts.count += 1
            if !permission.granted { throw .observationNotPermitted }
        }
        #expect(attempts.count == 1)

        permission.granted = true
        for _ in 0..<100 where arming.failure != nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(attempts.count == 2)
        #expect(arming.failure == nil)
        arming.disarm()
    }

    @Test("does not retry unrelated arming failures")
    func doesNotRetryOtherFailures() async {
        let attempts = Attempts()
        let arming = ShortcutArming(
            onChange: {}, accessibilityIsGranted: { true }, retryInterval: .milliseconds(10))

        await arming.arm { () throws(HotkeyError) in
            attempts.count += 1
            throw .shortcutUnavailable
        }

        #expect(arming.retryTask == nil, "no retry is scheduled, so none can ever run")
        #expect(attempts.count == 1)
        #expect(arming.failure == .shortcutUnavailable)
        arming.disarm()
    }

    @Test("does not retry a refused tap while Accessibility still reads as granted")
    func staleAccessibilityGrantDoesNotCauseAnEndlessRetry() async {
        let attempts = Attempts()
        let arming = ShortcutArming(
            onChange: {}, accessibilityIsGranted: { true }, retryInterval: .milliseconds(10))

        await arming.arm { () throws(HotkeyError) in
            attempts.count += 1
            throw .accessibilityNeedsRefresh
        }

        #expect(arming.retryTask == nil, "no retry is scheduled, so none can ever run")
        #expect(attempts.count == 1)
        #expect(arming.failure == .accessibilityNeedsRefresh)
        arming.disarm()
    }

    @Test("stops retrying when dictation is turned off")
    func disarmStopsRetries() async throws {
        let attempts = Attempts()
        let arming = ShortcutArming(
            onChange: {}, accessibilityIsGranted: { true }, retryInterval: .milliseconds(10))

        await arming.arm { () throws(HotkeyError) in
            attempts.count += 1
            throw .observationNotPermitted
        }
        let retries = try #require(arming.retryTask)
        arming.disarm()
        try #require(retries.isCancelled, "a retry loop left running would retry forever")
        await retries.value

        #expect(attempts.count == 1)
        #expect(arming.failure == nil)
    }

    private final class Permission {
        var granted = false
    }

    private final class Attempts {
        var count = 0
    }

    @Test("gives way to secure input, which blocks every shortcut")
    func secureInputComesFirst() {
        #expect(
            ShortcutArming.unheard(secureInputBlocking: true, failure: .shortcutUnavailable)
                == SecureInputWatch.notice)
    }

    @Test("is never reported through the dictation state")
    func armingIsNotADictation() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Uttrflow/AppDelegate.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let arming = try #require(
            text.components(separatedBy: "private func startWatchingForTheShortcut()").dropFirst().first?
                .components(separatedBy: "// MARK:").first)
        #expect(arming.contains("arming.arm {"))
        #expect(!arming.contains("render("), "an arming failure would be counted as a dictation")
    }

    @Test("tells the launch its first outcome only, so a later re-arming is not timed as the launch")
    func firstOutcomeEndsTheLaunch() async {
        let launch = LaunchMilestone { .milliseconds(250) }
        let arming = ShortcutArming(onChange: {}, launch: launch)

        await arming.arm { () throws(HotkeyError) in throw .shortcutUnavailable }
        await arming.arm { () throws(HotkeyError) in }

        #expect(launch.report == LaunchReport(age: .milliseconds(250), outcome: .refused))
    }
}

// An armed ghost left alone is checked every 5 s, not 300 times a minute.

import AppKit
import Foundation
import Synchronization
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("Selection checks slow down once a drawn ghost is idle")
struct SuggestionSelectionCadenceTests {
    @Test("an idle ghost drops focused-selection reads from 300 to 12 a minute")
    func idleGhostSlowsSelectionReads() async throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let container = FileManager.default.temporaryDirectory
            .appending(path: "selection-cadence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let clock = ManualSelectionClock()
        let reads = SelectionReadCount()
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedSelectionReader: {
                reads.add()
                return .timedOut
            },
            focusedFieldReader: {
                try? await Task.sleep(for: .seconds(600))
                return nil
            },
            frontmostBundleIdentifier: { "com.example.editor" },
            scheduleSelectionChecks: { interval, check in clock.schedule(every: interval, check) },
            panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }
        coordinator.noteActivity()
        coordinator.armSelectionMonitor(for: .certain("completion"), at: NSRange(location: 12, length: 0))

        await clock.advance(by: 60, reads: reads)
        #expect(reads.value == 300)

        // Dating the last activity past the window lets the next tick find the ghost idle without waiting for it.
        coordinator.noteActivity(at: Date().addingTimeInterval(-(SuggestionTicking.window + 1)))
        // Shown only across the tick, with no suspension, so no other test's panel count or display change sees it.
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        panel.show(.certain("completion"), placement: .inlineGhost, caret: caret)
        #expect(panel.isShowing)
        coordinator.tick()
        panel.hide()
        #expect(
            clock.intervals == [SuggestionTicking.activeSelectionInterval, SuggestionTicking.ghostInterval])
        reads.reset()

        await clock.advance(by: 60, reads: reads)
        #expect(reads.value == 12)
        #expect(coordinator.armedOffer == "completion")
    }
}

private final class SelectionReadCount: Sendable {
    private let storage = Mutex(0)

    var value: Int { storage.withLock { $0 } }

    func add() { storage.withLock { $0 += 1 } }

    func reset() { storage.withLock { $0 = 0 } }
}

/// Runs scheduled selection checks against simulated time, waiting for each read before the next.
@MainActor
private final class ManualSelectionClock {
    private struct Scheduled {
        let interval: TimeInterval
        var nextFire: TimeInterval
        let check: @MainActor () -> Void
        var isActive = true
    }

    private var elapsed: TimeInterval = 0
    private var scheduled: [Scheduled] = []

    var intervals: [TimeInterval] { scheduled.map(\.interval) }

    func schedule(
        every interval: TimeInterval, _ check: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        let index = scheduled.count
        scheduled.append(Scheduled(interval: interval, nextFire: elapsed + interval, check: check))
        return { [weak self] in self?.scheduled[index].isActive = false }
    }

    func advance(by duration: TimeInterval, reads: SelectionReadCount) async {
        let deadline = elapsed + duration + 1e-9
        while let index = scheduled.indices
            .filter({ scheduled[$0].isActive && scheduled[$0].nextFire <= deadline })
            .min(by: { scheduled[$0].nextFire < scheduled[$1].nextFire })
        {
            elapsed = scheduled[index].nextFire
            scheduled[index].nextFire += scheduled[index].interval
            let expected = reads.value + 1
            scheduled[index].check()
            for _ in 0..<1_000 where reads.value < expected { await Task.yield() }
        }
        elapsed = deadline
    }
}

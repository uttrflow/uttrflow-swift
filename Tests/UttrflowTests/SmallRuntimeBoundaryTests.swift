// Private clocks and presentation fixtures cover the boundaries around small app components.

import AppKit
import Foundation
import Testing
import UttrflowTestSupport
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Small app runtime boundaries", .serialized, .timeLimit(.minutes(1)))
struct SmallRuntimeBoundaryTests {
    @Test("the scheduled home timer redraws once and schedules a future boundary")
    func scheduledTimerRedraws() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var now = Date(timeIntervalSince1970: 1_500_000_000)
        var redraws = 0
        let clock = HomeClock(
            calendar: calendar, center: NotificationCenter(), workspaceCenter: NotificationCenter(),
            now: { now }, redraw: { redraws += 1 })
        clock.drew(at: now)
        clock.setVisible(true)
        defer { clock.setVisible(false) }
        #expect(redraws == 0)
        now = Date().addingTimeInterval(86_400)
        try await eventually { redraws == 1 }
        #expect(try #require(clock.nextFire) > now)
        #expect(clock.isRunning)
    }

    @Test("notifications no longer redraw a home clock after its owner is released")
    func releasingClockRemovesObservers() {
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var redraws = 0
        var clock: HomeClock? = HomeClock(
            center: center, workspaceCenter: workspace,
            now: { Date().addingTimeInterval(86_400) }, redraw: { redraws += 1 })
        clock?.setVisible(true)
        weak let released = clock
        clock = nil
        #expect(released == nil)
        let before = redraws
        center.post(name: .NSSystemClockDidChange, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(redraws == before)
    }

    @Test("keyboard navigation reaches the learned-word undo before the ordinary buttons")
    func learnedUndoHasAKeyboardPlace() throws {
        let id = UUID()
        let state = MenuBarState(learned: [
            LearnedWord(id: id, word: "FixtureWord", isFromScreen: false, learnedAt: Date())
        ])
        let shown = MenuBarPresenter.present(state)
        let undo = try #require(shown.learned.first?.undo)
        let keyboard = MenuBarKeyboard(shown)
        let first = try #require(keyboard.place(after: nil, forward: true))
        #expect(keyboard.command(at: first) == undo)
        #expect(keyboard.buttonsStart == first + 1)
        let afterUndo = try #require(keyboard.place(after: first, forward: true))
        #expect(keyboard.command(at: afterUndo) == shown.buttons.first?.command)
        #expect(keyboard.place(after: afterUndo, forward: false) == first)
    }
}

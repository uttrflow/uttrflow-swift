// Private display notifications leave other suggestion fixtures armed.

import AppKit
import Foundation
import Synchronization
import Testing

@testable import Uttrflow

private final class RecordedScreenCenter: NotificationCenter, @unchecked Sendable {
    private let count = Mutex(0)
    var removals: Int { count.withLock { $0 } }
    override func removeObserver(_ observer: Any) {
        count.withLock { $0 += 1 }
        super.removeObserver(observer)
    }
}

@MainActor
@Suite("Private suggestion display notifications", .serialized, .timeLimit(.minutes(1)))
struct SuggestionDisplayIsolationTests {
    @Test("a display change withdraws only the panel registered with its private center")
    func differentCentersDoNotWithdrawEachOther() throws {
        let firstCenter = NotificationCenter()
        let secondCenter = NotificationCenter()
        let first = SuggestionPanelController(screenNotificationCenter: firstCenter)
        let second = SuggestionPanelController(screenNotificationCenter: secondCenter)
        first.systemHidesPanel = { false }
        second.systemHidesPanel = { false }
        defer { first.hide(); second.hide() }
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 100, y: screen.maxY - 100, width: 0, height: 18)
        first.show(.certain("first fixture"), placement: .inlineGhost, caret: caret)
        first.window.orderOut(nil)
        second.show(.certain("second fixture"), placement: .inlineGhost, caret: caret)
        second.window.orderOut(nil)
        var firstUnasked = 0
        var secondUnasked = 0
        first.onWithdrawnUnasked = { firstUnasked += 1 }
        second.onWithdrawnUnasked = { secondUnasked += 1 }
        let secondWithdrawals = second.withdrawals
        firstCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!first.isShowing)
        #expect(firstUnasked == 1)
        #expect(second.isShowing)
        #expect(secondUnasked == 0)
        #expect(second.withdrawals == secondWithdrawals)
        secondCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!second.isShowing)
        #expect(secondUnasked == 1)
    }

    @Test("a released panel unregisters its screen observer from the same private center")
    func releasingPanelRemovesItsScreenObserver() {
        let center = RecordedScreenCenter()
        var panel: SuggestionPanelController? = SuggestionPanelController(screenNotificationCenter: center)
        weak let released = panel
        panel = nil
        #expect(released == nil)
        #expect(center.removals == 1)
    }
}

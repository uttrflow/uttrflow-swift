import AppKit
import SwiftUI
import Testing
import UttrflowPredict
import UttrflowUX

@testable import Uttrflow

extension SuggestionSurfaceTests {
    @Test("withdrawing the shared surface cannot cancel a private controller's pending announcement")
    func competingSharedWithdrawal() async throws {
        let panel = SuggestionPanelController()
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        var heard: [String] = []
        var now = Duration.zero
        panel.announce = { heard.append($0) }
        panel.announcementNow = { now }
        panel.announcementSleep = { now += $0 }
        defer { panel.hide() }
        panel.show(.certain("synthetic"), placement: .inlineGhost, caret: caret)
        SuggestionPanelController.shared.hide()
        for _ in 0..<10_000 {
            if !heard.isEmpty { break }
            await Task.yield()
        }
        #expect(heard == ["AI suggestion: synthetic. Tab to accept."])
    }
}

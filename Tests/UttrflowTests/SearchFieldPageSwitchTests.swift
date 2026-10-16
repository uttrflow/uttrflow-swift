// That the shared search field shows History's own query again after another page used it.

import Foundation
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Search field across pages", .timeLimit(.minutes(1)), .serialized)
struct SearchFieldPageSwitchTests {
    @Test("History gets its own search text back after another page was searched")
    func historyKeepsItsOwnQuery() throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())
        let controller = app.makeMainWindow()
        let model = try #require(
            Mirror(reflecting: controller).descendant("model") as? MainWindowModel)

        model.page = .history
        model.searchQuery = "zzqxx"
        model.page = .snippets
        model.pageDidChange(from: .history)
        model.searchQuery = "nomatchzz"
        model.page = .history
        model.pageDidChange(from: .snippets)

        #expect(model.searchQuery == "zzqxx")
    }
}

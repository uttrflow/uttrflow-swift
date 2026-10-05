// That Edit ▸ Find reaches the page's search field, or Home's search on a page without one.

import AppKit
import Foundation
import Testing
import UttrflowUX

@testable import Uttrflow

/// The stored property named `label`, read by reflection because the controller keeps it private.
private func stored<T>(_ label: String, of subject: Any, as type: T.Type) -> T? {
    Mirror(reflecting: subject).descendant(label) as? T
}

/// The same page with its search field showing, which is the only state Find is offered on.
private func searchable(_ history: HistoryPresentation) -> HistoryPresentation {
    HistoryPresentation(
        days: history.days, emptyState: history.emptyState,
        retentionNotice: history.retentionNotice, showsSearch: true)
}

/// An app with its main window open, which is the state the Find item is read in.
@MainActor
private struct Opened {
    let app: AppDelegate
    let controller: MainWindowController
    let model: MainWindowModel
}

@MainActor
@Suite("Edit ▸ Find", .timeLimit(.minutes(1)), .serialized)
struct FindCommandTests {
    /// The app's real window over a sandbox, held by the app as opening a window holds it.
    private func opened(in root: URL) throws -> Opened {
        let app = AppDelegate(container: root)
        let controller = app.makeMainWindow()
        app.mainWindow = controller
        let model = try #require(stored("model", of: controller, as: MainWindowModel.self))
        model.content.history = searchable(model.content.history)
        return Opened(app: app, controller: controller, model: model)
    }

    @Test("is offered on a page whose search field is showing")
    func offeredWhereThereIsAFieldToReach() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.history)

        #expect(open.controller.canFocusSearch)
    }

    @Test("is withheld on a page that has no search field")
    func withheldWhereThereIsNone() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.home)

        #expect(!open.controller.canFocusSearch)
    }

    /// Off screen there is no caret to move, so the item is grey rather than silently doing nothing.
    @Test("is withheld while the window is not on screen")
    func withheldWithNoWindowOnScreen() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.history)
        open.controller.close()

        #expect(!open.controller.canFocusSearch)
    }

    @Test("the menu item is offered on every page while the window is on screen, and grey once it is not")
    func validationFollowsTheWindow() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        let item = try #require(MainMenu.edit.items.first { $0.title == "Find" })

        open.controller.show(.home)
        #expect(open.app.validateMenuItem(item))
        open.controller.show(.history)
        #expect(open.app.validateMenuItem(item))
        open.controller.close()
        #expect(!open.app.validateMenuItem(item))
    }

    /// The sidebar item still names itself, so the switch added for Find did not take that over.
    @Test("validating Find leaves the sidebar item's own title alone")
    func validationStillNamesTheSidebarItem() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        let toggle = try #require(MainMenu.view.items.first { !$0.isSeparatorItem })
        open.controller.show(.history)

        #expect(open.app.validateMenuItem(toggle))
        #expect(toggle.title == (open.controller.isSidebarExpanded ? "Hide Sidebar" : "Show Sidebar"))
    }

    @Test("choosing it asks the page's search field for the caret")
    func choosingItAsksForTheCaret() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.history)
        let before = open.model.searchFocusRequest

        open.app.findFromMenu(nil)

        #expect(open.model.searchFocusRequest == before + 1)
    }

    @Test("choosing it on Home opens the search, as ⌘K does")
    func choosingItOnHomeOpensTheSearch() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.home)

        open.app.findFromMenu(nil)

        #expect(open.controller.page == .history)
    }

    /// Off screen there is nowhere to search, so a stale request cannot fire when the window returns.
    @Test("choosing it with the window off screen does nothing")
    func choosingItOffScreenDoesNothing() throws {
        let sandbox = Sandbox()
        let open = try opened(in: sandbox.root)
        open.controller.show(.home)
        open.controller.close()
        let before = open.model.searchFocusRequest

        open.app.findFromMenu(nil)

        #expect(open.model.searchFocusRequest == before)
        #expect(open.model.page == .home)
    }
}

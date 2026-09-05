// Tests for the menu bar.

import AppKit
import Testing

@testable import Uttrflow

/// The menu bar, tested because its most important job is invisible: macOS routes ⌘C and ⌘V through Edit.
@MainActor
@Suite("The menu bar at the top of the screen")
struct MainMenuTests {
    private func titles(of menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    @Test("offers the menus a Mac app is expected to have, in the expected order")
    func structure() {
        let bar = MainMenu.build()
        #expect(
            bar.items.compactMap(\.submenu?.title)
                == ["Uttrflow", "Edit", "View", "Window", "Help"])
    }

    /// The sidebar toggle is the only item in View, on the system's own shortcut.
    @Test("puts the sidebar toggle in View, on the system's own shortcut")
    func sidebarToggle() {
        let items = MainMenu.view.items.filter { !$0.isSeparatorItem }

        #expect(items.count == 1)
        let toggle = items.first
        #expect(toggle?.action == #selector(AppDelegate.toggleSidebarFromMenu(_:)))
        #expect(toggle?.keyEquivalent == "s")
        #expect(toggle?.keyEquivalentModifierMask == [.control, .command])
    }

    /// Every item in Edit is a keystroke people use without looking.
    @Test("Edit carries the shortcuts macOS routes through it")
    func editShortcuts() {
        let expected = ["z": "Undo", "x": "Cut", "c": "Copy", "v": "Paste", "a": "Select All"]
        let offered = Dictionary(
            MainMenu.edit.items.filter { !$0.isSeparatorItem && !$0.keyEquivalent.isEmpty }
                .map { ($0.keyEquivalent, $0.title) },
            uniquingKeysWith: { first, _ in first })
        for (key, title) in expected {
            #expect(offered[key] == title, "⌘\(key) should be \(title)")
        }
    }

    @Test("Redo is shift-command-Z, not a second plain command-Z")
    func redo() throws {
        let redo = try #require(MainMenu.edit.items.first { $0.title == "Redo" })
        #expect(redo.keyEquivalent == "z")
        #expect(redo.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("the application menu can quit, and with the shortcut everybody knows")
    func quit() throws {
        let quit = try #require(
            MainMenu.application(named: "Uttrflow").items.first { $0.title.hasPrefix("Quit") })
        #expect(quit.keyEquivalent == "q")
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
    }

    /// The same shortcut the menu-bar item offers, so there are two ways back to the window.
    @Test("Window offers the main window on the shortcut the menu bar uses")
    func reopening() throws {
        let item = try #require(MainMenu.window.items.first { $0.title == "Uttrflow" })
        #expect(item.keyEquivalent == "0")
        #expect(item.action == #selector(AppDelegate.showMainWindowFromMenu(_:)))
    }

    @Test("Settings is where every Mac app keeps it")
    func settings() throws {
        let item = try #require(
            MainMenu.application(named: "Uttrflow").items.first { $0.title == "Settings…" })
        #expect(item.keyEquivalent == ",")
        #expect(item.keyEquivalentModifierMask == [.command])
    }

    /// The app's name reaches every menu that mentions it.
    @Test("the name is used wherever it is written")
    func naming() {
        let renamed = MainMenu.application(named: "Wossname")
        #expect(titles(of: renamed).contains("About Wossname"))
        #expect(titles(of: renamed).contains("Quit Wossname"))
        #expect(titles(of: MainMenu.help(for: "Wossname")).contains("Wossname Help"))
    }
}

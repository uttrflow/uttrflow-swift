// The menu bar, built in code.

import AppKit

/// The menu bar; without an Edit menu, macOS routes ⌘C, ⌘V, ⌘A and ⌘Z nowhere.
enum MainMenu {
    /// The whole menu bar, ready to install.
    static func build(applicationNamed name: String = "Uttrflow") -> NSMenu {
        let bar = NSMenu()
        for menu in [application(named: name), edit, view, window, help(for: name)] {
            let holder = NSMenuItem()
            holder.submenu = menu
            bar.addItem(holder)
        }
        return bar
    }

    /// The application menu; macOS draws the app's own name as its title.
    static func application(named name: String) -> NSMenu {
        let menu = NSMenu(title: name)
        menu.addItem(
            withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(
            withTitle: "Settings…", action: #selector(AppDelegate.showSettingsFromMenu(_:)),
            keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        return menu
    }

    /// The Edit menu, whose every item is a keystroke people use without looking.
    static var edit: NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    /// The View menu, which exists for the sidebar toggle at the system's own ⌃⌘S.
    static var view: NSMenu {
        let menu = NSMenu(title: "View")
        let item = menu.addItem(
            withTitle: "Show Sidebar",
            action: #selector(AppDelegate.toggleSidebarFromMenu(_:)),
            keyEquivalent: "s")
        item.keyEquivalentModifierMask = [.control, .command]
        return menu
    }

    static var window: NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(
            withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(.separator())
        // The same shortcut the menu bar item offers, so there are two ways back to the window.
        menu.addItem(
            withTitle: "Uttrflow", action: #selector(AppDelegate.showMainWindowFromMenu(_:)),
            keyEquivalent: "0")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "")
        return menu
    }

    static func help(for name: String) -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(
            withTitle: "\(name) Help", action: #selector(AppDelegate.showDiagnosticsFromMenu(_:)),
            keyEquivalent: "?")
        return menu
    }
}

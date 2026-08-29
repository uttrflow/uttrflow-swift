import AppKit

/// The menu bar at the top of the screen.
///
/// Needed the moment Uttrflow became a normal windowed app rather than an accessory. An
/// app with a Dock icon and no main menu is not merely unpolished: **macOS routes ⌘C,
/// ⌘V, ⌘A and ⌘Z through the Edit menu**, so without one every text field in the product
/// silently stops accepting the shortcuts everybody uses. Quit and Close go the same way.
///
/// Built rather than loaded from a nib, for the reason the rest of the interface is:
/// there is no `.xib` in this repository and a hand-maintained one would be a second
/// place the product is described.
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

    /// The application menu. Its title is ignored by macOS, which always draws the app's
    /// own name here, but the items are ours.
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

    /// The one menu that is not decoration. Every item here is a keystroke people use
    /// without looking, and a text field whose ⌘V does nothing reads as a broken app.
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

    /// The View menu, which exists for one item.
    ///
    /// Its own menu rather than a line in Window, because every Mac app that has a
    /// sidebar puts the toggle here and somebody looking for it looks here first.
    /// &#8963;&#8984;S is the system's own shortcut for it — the one `toggleSidebar:`
    /// carries in a split view — so it is the one already in the reader's fingers.
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
        // The same shortcut the menu bar item offers, so somebody who has closed the
        // window has two ways back to it and neither is a secret.
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

import AppKit
import UniformTypeIdentifiers
import UttrflowPredict
import UttrflowUX

/// Asks the user for an application, from those running or from the Applications folder.
@MainActor
enum ApplicationPicker {
    /// Picks a running application for clipboard history exclusion.
    static func chooseClipboardApplication(_ chosen: (String) -> Void) {
        let offered = NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let identifier = app.bundleIdentifier,
                identifier != Bundle.main.bundleIdentifier
            else { return nil }
            return (identifier, app.localizedName ?? identifier)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        guard !offered.isEmpty else { return fromFolderForClipboard(chosen) }
        let list = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        list.addItems(withTitles: offered.map(\.1))
        let alert = NSAlert()
        alert.messageText = "Exclude an app from clipboard history"
        list.setAccessibilityLabel(alert.messageText)
        alert.informativeText = "Uttrflow uses the frontmost app when it detects a copy."
        alert.accessoryView = list
        alert.addButton(withTitle: "Exclude")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Other…")
        switch alert.runModal() {
        case .alertFirstButtonReturn: chosen(offered[max(0, list.indexOfSelectedItem)].0)
        case .alertThirdButtonReturn: fromFolderForClipboard(chosen)
        default: break
        }
    }

    private static func fromFolderForClipboard(_ chosen: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK, let url = panel.url,
            let identifier = Bundle(url: url)?.bundleIdentifier
        else { return }
        chosen(identifier)
    }

    /// Offers the running applications in an alert, with a way out to the Applications folder, and hands on the one chosen.
    static func choose(given preferences: SuggestionPreferences, _ chosen: (String) -> Void) {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> SuggestionApplication? in
            guard app.activationPolicy == .regular, let identifier = app.bundleIdentifier else { return nil }
            return SuggestionApplication(
                bundleIdentifier: identifier,
                name: app.localizedName ?? SuggestionApplications.name(of: identifier))
        }
        let offered = SuggestionApplicationChoices.offered(
            running, preferences: preferences, excluding: Bundle.main.bundleIdentifier)
        guard !offered.isEmpty else { return fromFolder(chosen) }

        let list = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        list.addItems(withTitles: offered.map(\.name))
        let alert = NSAlert()
        alert.messageText = "Turn off AI suggestions in…"
        list.setAccessibilityLabel(alert.messageText)
        alert.informativeText = "Nothing is suggested or learned in the application you choose."
        alert.accessoryView = list
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Other…")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            chosen(offered[max(0, list.indexOfSelectedItem)].bundleIdentifier)
        case .alertThirdButtonReturn:
            fromFolder(chosen)
        default:
            return
        }
    }

    /// Opens the Applications folder and takes the bundle identifier of whichever application is chosen.
    private static func fromFolder(_ chosen: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Turn Off"
        guard panel.runModal() == .OK, let url = panel.url,
            let identifier = Bundle(url: url)?.bundleIdentifier
        else { return }
        chosen(identifier)
    }
}

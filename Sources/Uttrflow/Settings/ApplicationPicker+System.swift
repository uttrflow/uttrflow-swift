import AppKit
import UniformTypeIdentifiers
import UttrflowPredict
import UttrflowUX

/// Asks the user for an application, from those running or from the Applications folder.
@MainActor
enum ApplicationPicker {
    /// What one picker asks and what its confirming button says.
    private struct Question {
        let message: String
        let informative: String
        let confirm: String
        let width: CGFloat
    }

    /// Picks a running application for clipboard history exclusion.
    static func chooseClipboardApplication(_ chosen: (String) -> Void) {
        pick(
            runningOthers(),
            asking: Question(
                message: "Exclude an app from clipboard history",
                informative: "Uttrflow uses the frontmost app when it detects a copy.",
                confirm: "Exclude", width: 280),
            chosen)
    }

    /// Picks an application a snippet fires in or a word is offered in, from those running or the folder.
    static func chooseScopeApplication(_ chosen: (String) -> Void) {
        pick(
            runningOthers(),
            asking: Question(
                message: "Use only in\u{2026}",
                informative: "Leave the list empty to use it in every app.",
                confirm: "Add", width: 280),
            chosen)
    }

    /// Opens the Applications folder and hands on the installed application chosen, by identifier and name.
    static func chooseInstalled(_ chosen: (SettingsApp) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an app to say what kind of place it is."
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
            let identifier = Bundle(url: url)?.bundleIdentifier,
            identifier != Bundle.main.bundleIdentifier
        else { return }
        chosen(SettingsApp(bundleIdentifier: identifier, name: url.deletingPathExtension().lastPathComponent))
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
        pick(
            offered.map { ($0.bundleIdentifier, $0.name) },
            asking: Question(
                message: "Turn off AI suggestions in…",
                informative: "Nothing is suggested or learned in the application you choose.",
                confirm: "Turn Off", width: 260),
            chosen)
    }

    /// Every ordinary running application but this one, as identifier and name, sorted by name.
    private static func runningOthers() -> [(String, String)] {
        NSWorkspace.shared.runningApplications.compactMap { app -> (String, String)? in
            guard app.activationPolicy == .regular, let identifier = app.bundleIdentifier,
                identifier != Bundle.main.bundleIdentifier
            else { return nil }
            return (identifier, app.localizedName ?? identifier)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// Asks `question` over `offered` as identifier and name, falling back to the folder when nothing is running.
    private static func pick(
        _ offered: [(String, String)], asking question: Question, _ chosen: (String) -> Void
    ) {
        guard !offered.isEmpty else { return fromFolder(confirming: question.confirm, chosen) }
        let list = NSPopUpButton(
            frame: NSRect(x: 0, y: 0, width: question.width, height: 26), pullsDown: false)
        list.addItems(withTitles: offered.map(\.1))
        let alert = NSAlert()
        alert.messageText = question.message
        list.setAccessibilityLabel(alert.messageText)
        alert.informativeText = question.informative
        alert.accessoryView = list
        alert.addButton(withTitle: question.confirm)
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Other…")
        switch alert.runModal() {
        case .alertFirstButtonReturn: chosen(offered[max(0, list.indexOfSelectedItem)].0)
        case .alertThirdButtonReturn: fromFolder(confirming: question.confirm, chosen)
        default: return
        }
    }

    /// Opens the Applications folder and takes the bundle identifier of whichever application is chosen.
    private static func fromFolder(confirming prompt: String, _ chosen: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = prompt
        guard panel.runModal() == .OK, let url = panel.url,
            let identifier = Bundle(url: url)?.bundleIdentifier
        else { return }
        chosen(identifier)
    }
}

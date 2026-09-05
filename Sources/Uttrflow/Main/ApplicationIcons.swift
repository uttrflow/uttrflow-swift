// An app's icon for a history row, remembered per lookup.

import AppKit
import UttrflowUX

/// Where an app's icon comes from: a running app first, then the applications folders; injected for tests.
struct ApplicationIconSource {
    /// By bundle identifier — the only lookup that cannot answer with the wrong app.
    var identified: @MainActor (String) -> NSImage?
    var running: @MainActor (String) -> NSImage?
    var installed: @MainActor (String) -> NSImage?
}

/// The real icons from `NSWorkspace`, remembered while the window is open, misses included.
@MainActor
final class ApplicationIcons {
    static let shared = ApplicationIcons()

    private let source: ApplicationIconSource
    private var known: [String: NSImage?] = [:]

    init(source: ApplicationIconSource = .system) {
        self.source = source
    }

    /// The icon for the app a dictation went to, by identifier then name; `nil` draws the lettered tile.
    func icon(for application: HistoryApplication) -> NSImage? {
        let identifier = application.identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = application.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remembered against the lookup key, so an identifier and a bare name do not share an answer.
        let key = identifier.map { "id:" + $0 } ?? "name:" + name
        guard !(identifier ?? name).isEmpty else { return nil }
        if let remembered = known[key] { return remembered }
        let found =
            identifier.flatMap(source.identified)
            ?? (name.isEmpty ? nil : source.running(name) ?? source.installed(name))
        known[key] = found
        return found
    }
}

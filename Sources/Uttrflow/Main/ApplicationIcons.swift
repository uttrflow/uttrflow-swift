import AppKit
import UttrflowUX

/// Where an app's own icon comes from.
///
/// Two lookups rather than one, in the order that answers fastest and most certainly: the
/// app the user dictated into is usually still running, and a running app carries its
/// icon with it. Only if it is not do we go looking through the applications folders.
///
/// Injected rather than called directly so the order can be tested on a Mac that does not
/// happen to have Slack installed.
struct ApplicationIconSource {
    /// By bundle identifier — the only lookup that cannot answer with the wrong app.
    var identified: @MainActor (String) -> NSImage?
    var running: @MainActor (String) -> NSImage?
    var installed: @MainActor (String) -> NSImage?
}

/// The real icons, kept for as long as the window is open.
///
/// macOS already has every icon this window wants to draw, at every size, always current
/// — the one on disk changes when the app updates, and a drawn or bundled copy would not.
/// So there is no library of logos here and nothing is fetched: a name goes to
/// `NSWorkspace`, which hands back the same icon the Dock is showing.
///
/// Both answers are remembered, including "there is no such app". A row redraws on every
/// keystroke in a search field, and a miss that is not remembered is a walk through four
/// directories per row per keystroke.
@MainActor
final class ApplicationIcons {
    static let shared = ApplicationIcons()

    private let source: ApplicationIconSource
    private var known: [String: NSImage?] = [:]

    init(source: ApplicationIconSource = .system) {
        self.source = source
    }

    /// The icon for the app a dictation went to, or `nil` when this Mac has never heard
    /// of it — in which case the caller draws its own tile, which is what every row did
    /// before there were icons at all.
    ///
    /// The identifier is tried first because it is the only lookup that cannot answer
    /// with the wrong app; the name is the fallback for every dictation recorded before
    /// identifiers were kept.
    func icon(for application: HistoryApplication) -> NSImage? {
        let identifier = application.identifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = application.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remembered against whichever key was used to find it, so a row that has an
        // identifier and one that has only a name do not share an answer.
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

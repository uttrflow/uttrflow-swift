public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// Where a sidebar row leads.
///
/// Two cases rather than one because Settings is a window of its own. A sidebar that
/// pretended otherwise would have to hold a tenth page that never draws, and the row
/// would behave differently from every other one for a reason nobody could see in the
/// code.
public enum SidebarDestination: Sendable, Equatable, Hashable {
    case page(MainTab)
    case settings(SettingsTab)
}

/// One row of the sidebar.
public struct SidebarItem: Sendable, Equatable, Identifiable {
    public let destination: SidebarDestination
    public let title: String
    public let symbolName: String
    /// The figure at the right-hand end. Absent when there is nothing worth counting —
    /// a badge reading "0" is a badge that has stopped meaning anything.
    public let badge: String?
    public let isSelected: Bool

    public var id: SidebarDestination { destination }

    public init(
        destination: SidebarDestination,
        title: String,
        symbolName: String,
        badge: String? = nil,
        isSelected: Bool
    ) {
        self.destination = destination
        self.title = title
        self.symbolName = symbolName
        self.badge = badge
        self.isSelected = isSelected
    }
}

public struct SidebarSnapshot: Sendable, Equatable {
    public let selection: SidebarDestination
    /// Newest first, before retention is applied.
    public let entries: [HistoryEntry]
    /// How many changes Uttrflow made today. The only badge in the sidebar, because it
    /// is the only number a user might want to act on without opening the page.
    public let correctionsToday: Int
    /// The shortcut as it reads on a keyboard, already split into keycaps by the app —
    /// which owns the mapping from key codes to the glyphs on a physical keyboard.
    public let shortcutKeys: [String]
    public let settings: Settings
    /// Which build this is, as the app reads it out of its own bundle.
    ///
    /// Passed in rather than read here: this module has no bundle of its own, and a
    /// presenter that asked the *test runner's* bundle what version it was would answer
    /// something true and useless.
    public let version: AppVersion
    public let now: Date

    public init(
        selection: SidebarDestination,
        entries: [HistoryEntry] = [],
        correctionsToday: Int = 0,
        shortcutKeys: [String],
        settings: Settings = .default,
        version: AppVersion = .unknown,
        now: Date
    ) {
        self.selection = selection
        self.entries = entries
        self.correctionsToday = correctionsToday
        self.shortcutKeys = shortcutKeys
        self.settings = settings
        self.version = version
        self.now = now
    }
}

/// Which build is running.
///
/// Two numbers, because they answer different questions. The short version is what
/// somebody says out loud — "I'm on 0.2.0". The build is what the updater compares and
/// what tells two builds of one version apart, which is exactly what a bug report from a
/// tester needs and what "0.2.0" alone cannot give.
public struct AppVersion: Sendable, Equatable {
    public let short: String
    public let build: String

    /// What a build with no version in its bundle says. Only reachable from a test host
    /// or a bundle somebody has damaged; the sidebar draws nothing rather than a lie.
    public static let unknown = AppVersion(short: "", build: "")

    public init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    public var isKnown: Bool { !short.isEmpty }

    /// "0.2.0 (3)" where there is room for both, and nothing at all where there is no
    /// version to show.
    public var full: String {
        guard isKnown else { return "" }
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

/// What the sidebar shows.
public struct SidebarPresentation: Sendable, Equatable {
    public let productName: String
    public let items: [SidebarItem]
    /// Drawn at the foot, in both widths. It is the one fact a person reporting
    /// something needs to hand over and the one they cannot be expected to remember.
    public let version: AppVersion

    public init(productName: String, items: [SidebarItem], version: AppVersion = .unknown) {
        self.productName = productName
        self.items = items
        self.version = version
    }
}

/// Builds the one piece of the window that is on every screen.
public enum SidebarPresenter {
    public static let productName = "Uttrflow"

    /// Every row, in the order the design puts them.
    ///
    /// Written out rather than derived from ``MainTab/allCases`` because Settings sits
    /// between Diagnostics and Account and is not a page. Deriving it would mean
    /// splicing a row into a generated list at a hard-coded index, which is the same
    /// hand-maintained order with a moving part added.
    public static let order: [SidebarDestination] = [
        .page(.home), .page(.dictation), .page(.history), .page(.dictionary), .page(.corrections),
        .page(.insights), .page(.snippets), .page(.style), .page(.diagnostics),
        .settings(.general), .page(.account),
    ]

    public static func sidebar(
        for snapshot: SidebarSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> SidebarPresentation {
        SidebarPresentation(
            productName: productName,
            items: order.map { item(for: $0, in: snapshot) },
            version: snapshot.version)
    }

    // MARK: - Rows

    static func item(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> SidebarItem {
        SidebarItem(
            destination: destination,
            title: title(for: destination),
            symbolName: symbolName(for: destination),
            badge: badge(for: destination, in: snapshot),
            isSelected: isSelected(destination, given: snapshot.selection))
    }

    /// The rail is the main window's own navigation, so it lights the page the main
    /// window is showing — and nothing else.
    ///
    /// Settings never lights, deliberately. It is a window of its own rather than a
    /// page, and lighting its row while somebody is looking at Home says they are
    /// somewhere they are not. That is what it did: the row stayed lit for as long as
    /// the Settings window existed anywhere on the desktop, including behind the main
    /// window, so Home could be open with Settings highlighted beside it.
    static func isSelected(
        _ destination: SidebarDestination, given selection: SidebarDestination
    )
        -> Bool
    {
        switch destination {
        case .settings: false
        case .page: destination == selection
        }
    }

    /// The heading above the pane is the same word as the sidebar row, deliberately:
    /// two names for one page is how a user loses track of where they are.
    public static func title(for destination: SidebarDestination) -> String {
        switch destination {
        case .settings: "Settings"
        case .page(let page):
            switch page {
            case .home: "Home"
            case .dictation: "Dictation"
            case .history: "History"
            case .dictionary: "Dictionary"
            case .corrections: "Corrections"
            case .insights: "Insights"
            case .snippets: "Snippets"
            case .style: "Style"
            case .diagnostics: "Diagnostics"
            case .account: "Account"
            }
        }
    }

    public static func title(for page: MainTab) -> String { title(for: .page(page)) }

    static func symbolName(for destination: SidebarDestination) -> String {
        switch destination {
        case .settings: "gearshape"
        case .page(let page):
            switch page {
            case .home: "house"
            case .dictation: "mic"
            case .history: "clock"
            case .dictionary: "character.book.closed"
            case .corrections: "arrow.left.arrow.right"
            case .insights: "chart.bar"
            case .snippets: "doc.on.doc"
            case .style: "sparkles"
            case .diagnostics: "gauge.with.dots.needle.bottom.50percent"
            case .account: "person.crop.circle"
            }
        }
    }

    static func badge(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> String? {
        guard destination == .page(.corrections), snapshot.correctionsToday > 0 else { return nil }
        return "\(snapshot.correctionsToday)"
    }
}

// The sidebar: where each row leads, what it shows, and the build number at its foot.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// Where a sidebar row leads; two cases because Settings is a window of its own, not a page.
public enum SidebarDestination: Sendable, Equatable, Hashable {
    /// A page of the main window.
    case page(MainTab)
    /// A tab of the Settings window.
    case settings(SettingsTab)
}

/// One row of the sidebar.
public struct SidebarItem: Sendable, Equatable, Identifiable {
    /// Where the row leads.
    public let destination: SidebarDestination
    /// The words on the row.
    public let title: String
    /// The SF Symbol beside them.
    public let symbolName: String
    /// The figure at the right-hand end; absent when there is nothing worth counting, never "0".
    public let badge: String?
    /// Whether this is the page the window is showing.
    public let isSelected: Bool

    /// The destination, which is unique.
    public var id: SidebarDestination { destination }

    /// Builds a row; no badge unless given one.
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

/// Everything the sidebar is drawn from.
public struct SidebarSnapshot: Sendable, Equatable {
    /// The page the main window is showing.
    public let selection: SidebarDestination
    /// Newest first, before retention is applied.
    public let entries: [HistoryEntry]
    /// How many changes Uttrflow made today; the only badge, since it is the one number worth acting on.
    public let correctionsToday: Int
    /// The shortcut as keycaps, split by the app, which owns the key-code-to-glyph mapping.
    public let shortcutKeys: [String]
    /// The user's settings.
    public let settings: Settings
    /// Which build this is, passed in because this module has no bundle of its own.
    public let version: AppVersion
    /// The clock the sidebar is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but the selection, the keycaps and the clock has a default.
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

/// Which build is running: the short version people say, and the build the updater compares.
public struct AppVersion: Sendable, Equatable {
    /// "0.2.0".
    public let short: String
    /// "3".
    public let build: String

    /// What a build with no version in its bundle says; the sidebar draws nothing rather than a lie.
    public static let unknown = AppVersion(short: "", build: "")

    /// Builds a version from its two numbers.
    public init(short: String, build: String) {
        self.short = short
        self.build = build
    }

    /// Whether there is a version to show.
    public var isKnown: Bool { !short.isEmpty }

    /// "0.2.0 (3)", or nothing at all where there is no version to show.
    public var full: String {
        guard isKnown else { return "" }
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

/// What the sidebar shows.
public struct SidebarPresentation: Sendable, Equatable {
    /// The name over the rows.
    public let productName: String
    /// The rows, in the design's order.
    public let items: [SidebarItem]
    /// Drawn at the foot: the one fact a bug reporter needs and cannot be expected to remember.
    public let version: AppVersion

    /// Builds the sidebar; unknown version unless given one.
    public init(productName: String, items: [SidebarItem], version: AppVersion = .unknown) {
        self.productName = productName
        self.items = items
        self.version = version
    }
}

/// Builds the one piece of the window that is on every screen.
public enum SidebarPresenter {
    /// The name over the rows.
    public static let productName = "Uttrflow"

    /// Every row in the design's order; written out since Settings sits among the pages but is not one.
    public static let order: [SidebarDestination] = [
        .page(.home), .page(.dictation), .page(.history), .page(.dictionary), .page(.corrections),
        .page(.insights), .page(.snippets), .page(.style), .page(.diagnostics),
        .settings(.general), .page(.account),
    ]

    /// Draws the sidebar from a snapshot.
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

    /// One row.
    static func item(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> SidebarItem {
        SidebarItem(
            destination: destination,
            title: title(for: destination),
            symbolName: symbolName(for: destination),
            badge: badge(for: destination, in: snapshot),
            isSelected: isSelected(destination, given: snapshot.selection))
    }

    /// Lights the page the main window is showing; Settings never lights, since it is its own window.
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

    /// The heading above the pane is the same word as the sidebar row, so a page has one name.
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

    /// The page's name.
    public static func title(for page: MainTab) -> String { title(for: .page(page)) }

    /// The SF Symbol beside the row.
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

    /// The corrections count, on that row only and only when it is non-zero.
    static func badge(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> String? {
        guard destination == .page(.corrections), snapshot.correctionsToday > 0 else { return nil }
        return "\(snapshot.correctionsToday)"
    }
}

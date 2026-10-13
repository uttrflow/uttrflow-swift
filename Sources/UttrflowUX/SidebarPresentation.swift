// The sidebar: where each row leads, what it shows, and the version at its foot.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// Where a sidebar row leads; two cases because Settings has tabs of its own.
public enum SidebarDestination: Sendable, Equatable, Hashable {
    /// A page of the main window.
    case page(MainTab)
    /// A tab of the Settings page.
    case settings(SettingsTab)
}

/// Which group a sidebar row sits in, top to bottom.
public enum SidebarSection: String, Sendable, Equatable, CaseIterable {
    /// The pages about what was said.
    case main
    /// The pages about the user's own words.
    case yourWords
    /// Settings, pinned to the foot above the account card.
    case footer

    /// The heading over the group; absent for groups drawn without one.
    public var title: String? {
        self == .yourWords ? "Your words" : nil
    }
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
    /// The group the row sits in.
    public let section: SidebarSection

    /// The destination, which is unique.
    public var id: SidebarDestination { destination }

    /// Builds a row; no badge unless given one.
    public init(
        destination: SidebarDestination,
        title: String,
        symbolName: String,
        badge: String? = nil,
        isSelected: Bool,
        section: SidebarSection = .main
    ) {
        self.destination = destination
        self.title = title
        self.symbolName = symbolName
        self.badge = badge
        self.isSelected = isSelected
        self.section = section
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

    /// "v26.0926.0", the version as a release tag names it, or nothing where there is no version.
    public var tag: String {
        isKnown ? "v\(short)" : ""
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
    /// Whether the window is showing the Account page, which the account card lights for.
    public let isAccountSelected: Bool

    /// Builds the sidebar; unknown version and an unlit account card unless given otherwise.
    public init(
        productName: String, items: [SidebarItem], version: AppVersion = .unknown,
        isAccountSelected: Bool = false
    ) {
        self.productName = productName
        self.items = items
        self.version = version
        self.isAccountSelected = isAccountSelected
    }

    /// The rows in one group, in order.
    public func items(in section: SidebarSection) -> [SidebarItem] {
        items.filter { $0.section == section }
    }
}

/// Builds the one piece of the window that is on every screen.
public enum SidebarPresenter {
    /// The name over the rows.
    public static let productName = "Uttrflow"

    /// Every row in the design's order; the account card, not a row, leads to the Account page.
    public static let order: [SidebarDestination] = [
        .page(.home), .page(.history), .page(.insights), .page(.dictionary), .page(.snippets),
        .settings(.general),
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
            version: snapshot.version,
            isAccountSelected: snapshot.selection == .page(.account))
    }

    // MARK: - Rows

    /// One row.
    static func item(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> SidebarItem {
        SidebarItem(
            destination: destination,
            title: title(for: destination),
            symbolName: symbolName(for: destination),
            badge: badge(for: destination, in: snapshot),
            isSelected: isSelected(destination, given: snapshot.selection),
            section: section(for: destination))
    }

    /// The group a row sits in.
    static func section(for destination: SidebarDestination) -> SidebarSection {
        switch destination {
        case .settings: .footer
        case .page(.dictionary), .page(.snippets): .yourWords
        case .page: .main
        }
    }

    /// Lights the page the main window is showing; the Settings row lights on any of its tabs.
    public static func isSelected(
        _ destination: SidebarDestination, given selection: SidebarDestination
    )
        -> Bool
    {
        switch (destination, selection) {
        case (.settings, .settings): true
        case (.settings, .page): false
        case (.page, _): destination == selection
        }
    }

    /// The heading above the pane is the same word as the sidebar row, so a page has one name.
    public static func title(for destination: SidebarDestination) -> String {
        switch destination {
        case .settings: "Settings"
        case .page(let page):
            switch page {
            case .home: "Home"
            case .history: "History"
            case .dictionary: "Dictionary"
            case .corrections: "Corrections"
            case .insights: "Insights"
            case .snippets: "Snippets"
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
            case .home: "house.fill"
            case .history: "clock"
            case .dictionary: "square.split.1x2"
            case .corrections: "arrow.left.arrow.right"
            case .insights: "chart.bar.xaxis"
            case .snippets: "chevron.left.chevron.right"
            case .account: "person.crop.circle"
            }
        }
    }

    /// Today's corrections, on the Dictionary row only and only when there are any.
    static func badge(for destination: SidebarDestination, in snapshot: SidebarSnapshot) -> String? {
        guard destination == .page(.dictionary), snapshot.correctionsToday > 0 else { return nil }
        return "\(snapshot.correctionsToday)"
    }
}

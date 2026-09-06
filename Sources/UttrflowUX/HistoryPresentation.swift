// The History page: kept dictations grouped by day, searched, and cut to the retention promise.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// One kept dictation: the persisted record itself, so there is one retention rule and one answer.
public typealias HistoryEntry = DictationRecord

/// The app a dictation went into, as a row can draw it.
public struct HistoryApplication: Sendable, Equatable {
    /// The app's name.
    public let name: String
    /// The single letter in the coloured tile, for when the app's own icon cannot be found.
    public let initial: String
    /// The bundle identifier when recorded; an identity, where a name is only a label two apps can share.
    public let identifier: String?

    /// Builds the app; the identifier is optional.
    public init(name: String, initial: String, identifier: String? = nil) {
        self.name = name
        self.initial = initial
        self.identifier = identifier
    }
}

/// One dictation, ready to draw.
public struct HistoryRow: Sendable, Equatable, Identifiable {
    /// The dictation's identity.
    public let id: UUID
    /// Absent when nothing was known about where the text went, rather than labelled "Unknown".
    public let application: HistoryApplication?
    /// How long ago, in words: "2 minutes ago".
    public let when: String
    /// What was said.
    public let text: String

    /// Builds a row from its parts.
    public init(id: UUID, application: HistoryApplication?, when: String, text: String) {
        self.id = id
        self.application = application
        self.when = when
        self.text = text
    }
}

/// A day's worth of dictations.
public struct HistoryDay: Sendable, Equatable, Identifiable {
    /// "Today", "Yesterday", or the date.
    public let title: String
    /// The day's dictations, in the store's order.
    public let rows: [HistoryRow]

    /// The title, which is unique on the page.
    public var id: String { title }

    /// Builds a day.
    public init(title: String, rows: [HistoryRow]) {
        self.title = title
        self.rows = rows
    }
}

/// The promise the user was shown, restated under the list even when the list is empty.
public struct HistoryRetentionNotice: Sendable, Equatable {
    /// The promise, cut to fit under the list.
    public let sentence: String
    /// The way to the privacy settings.
    public let link: MainAction

    /// Builds the notice.
    public init(sentence: String, link: MainAction) {
        self.sentence = sentence
        self.link = link
    }
}

/// Everything the history page is drawn from.
public struct HistorySnapshot: Sendable, Equatable {
    /// Newest first, in the order the store keeps them.
    public let entries: [HistoryEntry]
    /// What the user typed into the search field.
    public let query: String
    /// Retention and nothing else is read from here, so the page cannot drift from the privacy screen.
    public let settings: Settings
    /// Whether captured audio is written to disk, read from the app so the notice cannot claim otherwise.
    public let keepsRecordings: Bool
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but entries and the clock has a default.
    public init(
        entries: [HistoryEntry],
        query: String = "",
        settings: Settings = .default,
        keepsRecordings: Bool = false,
        now: Date
    ) {
        self.entries = entries
        self.query = query
        self.settings = settings
        self.keepsRecordings = keepsRecordings
        self.now = now
    }
}

/// What the history page shows.
public struct HistoryPresentation: Sendable, Equatable {
    /// The dictations, grouped by day.
    public let days: [HistoryDay]
    /// Set when — and only when — ``days`` is empty, saying which of three reasons nothing survived.
    public let emptyState: MainEmptyState?
    /// The promise under the list.
    public let retentionNotice: HistoryRetentionNotice
    /// Whether the search field is worth showing. Hidden when there is nothing to search.
    public let showsSearch: Bool

    /// Builds the page from its parts.
    public init(
        days: [HistoryDay],
        emptyState: MainEmptyState?,
        retentionNotice: HistoryRetentionNotice,
        showsSearch: Bool
    ) {
        self.days = days
        self.emptyState = emptyState
        self.retentionNotice = retentionNotice
        self.showsSearch = showsSearch
    }
}

/// Turns the stored dictations into the history page, applying retention rather than trusting the list.
public enum HistoryPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search"
    /// The sentence under the page's name: everything is here, and none of it left the Mac.
    public static let caption = "Every dictation, kept on this Mac."

    /// Draws the History page from a snapshot.
    public static func page(
        for snapshot: HistorySnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> HistoryPresentation {
        let kept = retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let matching = matches(kept, query: snapshot.query, locale: locale)
        let days = group(matching, snapshot: snapshot, calendar: calendar, locale: locale)

        return HistoryPresentation(
            days: days,
            emptyState: days.isEmpty
                ? emptyState(for: snapshot) : nil,
            retentionNotice: notice(for: snapshot),
            showsSearch: !kept.isEmpty
        )
    }

    // MARK: - Retention

    /// Drops what is promised deleted, via ``DictationRecord/survives(days:now:)`` so page and store agree.
    static func retained(_ entries: [HistoryEntry], days: Int, now: Date) -> [HistoryEntry] {
        entries.filter { $0.survives(days: days, now: now) }
    }

    /// The privacy screen's promise, cut to what fits under a list.
    static func notice(for snapshot: HistorySnapshot) -> HistoryRetentionNotice {
        let text = snapshot.settings.transcriptRetentionDays
        let kept = "Kept on this Mac for \(MainFormatting.count(text, "day", "days")), then deleted."
        let sentence =
            snapshot.keepsRecordings
            ? "\(kept) A recording stays only until its words land." : "\(kept) Recordings are never saved."

        return HistoryRetentionNotice(
            sentence: sentence,
            link: MainAction(title: "Change in Privacy settings", intent: .go(.settings(.privacy)))
        )
    }

    // MARK: - Searching

    /// Matches the text and the app name, ignoring case and accents, since users type accented words plain.
    static func matches(_ entries: [HistoryEntry], query: String, locale: Locale) -> [HistoryEntry] {
        SearchQuery.matches(entries, query: query, locale: locale) { [$0.text, $0.applicationName] }
    }

    /// The kept dictations cut into today's and everything before it, as the figures compare them.
    static func todayAndEarlier(
        in entries: [HistoryEntry], now: Date, calendar: Calendar
    ) -> (today: [HistoryEntry], earlier: [HistoryEntry]) {
        let today = entries.filter { calendar.isDate($0.when, inSameDayAs: now) }
        let earlier = entries.filter { !calendar.isDate($0.when, inSameDayAs: now) }
        return (today, earlier)
    }

    // MARK: - Grouping

    /// Groups by day in the store's order, merging days as met, so a moved clock cannot make two "Today"s.
    static func group(
        _ entries: [HistoryEntry], snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> [HistoryDay] {
        var grouped: [(day: Date, rows: [HistoryRow])] = []

        for entry in entries {
            let day = calendar.startOfDay(for: entry.when)
            let row = row(for: entry, relativeTo: snapshot.now, locale: locale)
            if let index = grouped.firstIndex(where: { $0.day == day }) {
                grouped[index].rows.append(row)
            } else {
                grouped.append((day, [row]))
            }
        }

        return grouped.map { day, rows in
            HistoryDay(
                title: title(for: day, snapshot: snapshot, calendar: calendar, locale: locale),
                rows: rows)
        }
    }

    /// "Today", "Yesterday", or the date, for a day's heading.
    static func title(
        for day: Date, snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> String {
        MainFormatting.todayOrYesterday(day, now: snapshot.now, calendar: calendar)
            ?? day.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    /// One dictation as a row.
    static func row(for entry: HistoryEntry, relativeTo now: Date, locale: Locale) -> HistoryRow {
        HistoryRow(
            id: entry.id,
            application: application(for: entry),
            when: when(entry.when, relativeTo: now, locale: locale),
            text: entry.text)
    }

    /// "2 minutes ago" against the snapshot's clock, not the real one, so the row agrees with retention.
    static func when(_ date: Date, relativeTo now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// A blank app name is no name at all, and a tile with a space in it is worse than no tile.
    static func application(
        named name: String, identifier: String? = nil
    )
        -> HistoryApplication?
    {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        let identity = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HistoryApplication(
            name: trimmed, initial: String(first).uppercased(),
            identifier: (identity?.isEmpty ?? true) ? nil : identity)
    }

    /// The application a dictation went to, identifier and all, in one place for every page.
    static func application(for entry: HistoryEntry) -> HistoryApplication? {
        entry.applicationName.flatMap {
            application(named: $0, identifier: entry.applicationIdentifier)
        }
    }

    // MARK: - Nothing to show

    /// Three different nothings, told apart, because the answer to each is different.
    static func emptyState(for snapshot: HistorySnapshot) -> MainEmptyState {
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("Nothing kept on this Mac mentions “\(query)”.")
        }
        if snapshot.entries.isEmpty {
            return MainEmptyState(
                symbolName: "clock",
                title: "Nothing yet",
                message: "What you dictate shows up here, and never leaves this Mac.")
        }
        // Everything handed over fell outside retention: the promise was kept, not "never dictated".
        return MainEmptyState(
            symbolName: "clock.badge.checkmark",
            title: "Nothing left to show",
            message: """
                Everything older than \
                \(MainFormatting.count(snapshot.settings.transcriptRetentionDays, "day", "days")) \
                has been deleted, as promised.
                """)
    }
}

extension Sequence where Element == HistoryEntry {
    /// Every word across these dictations, counted the way a row counts its own.
    var totalWords: Int {
        reduce(0) { $0 + MainFormatting.words(in: $1.text) }
    }
}

public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// One kept dictation, as the pages talk about it.
///
/// The persisted record itself rather than a copy of its fields. There were two spellings
/// of the same thing — and, more to the point, two answers to "has this been deleted yet",
/// which disagreed at the boundary: a record exactly seven days old was gone from the
/// store and still drawn on the page. One type, one retention rule, one answer.
public typealias HistoryEntry = DictationRecord

/// The app a dictation went into, as a row can draw it.
public struct HistoryApplication: Sendable, Equatable {
    public let name: String
    /// The single letter in the coloured tile, for when the app's own icon cannot be
    /// found.
    public let initial: String
    /// The bundle identifier, when the dictation recorded one.
    ///
    /// What the interface looks the app up by. A name is a label — two apps can share
    /// one and an app can change its own between versions — where an identifier is an
    /// identity, and the difference is Claude's icon rather than whichever bundle
    /// happens to be called Claude.
    public let identifier: String?

    public init(name: String, initial: String, identifier: String? = nil) {
        self.name = name
        self.initial = initial
        self.identifier = identifier
    }
}

/// One dictation, ready to draw.
public struct HistoryRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Absent when nothing was known about where the text went, which is the honest
    /// alternative to labelling it "Unknown".
    public let application: HistoryApplication?
    /// How long ago, in words: "2 minutes ago".
    public let when: String
    public let text: String

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
    public let rows: [HistoryRow]

    public var id: String { title }

    public init(title: String, rows: [HistoryRow]) {
        self.title = title
        self.rows = rows
    }
}

/// The promise the user was shown, restated where the history is.
///
/// Present on the page even when there is nothing in the list: a user checking what the
/// app keeps about them should not have to dictate something first to find out.
public struct HistoryRetentionNotice: Sendable, Equatable {
    public let sentence: String
    public let link: MainAction

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
    /// Retention and nothing else is read from here, so the page cannot drift from the
    /// promise the privacy screen makes.
    public let settings: Settings
    /// Whether captured audio is being written to disk at all. Nothing in Uttrflow
    /// writes any, so this is false in every build there is — but the notice makes a
    /// promise about it, and a promise asserted rather than checked is one a later
    /// build can silently turn into a lie. Read from the app, so it cannot.
    public let keepsRecordings: Bool
    public let now: Date

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
    public let days: [HistoryDay]
    /// Set when — and only when — ``days`` is empty. Which of the three reasons it is
    /// depends on why nothing survived, and the user is told which.
    public let emptyState: MainEmptyState?
    public let retentionNotice: HistoryRetentionNotice
    /// Whether the search field is worth showing. Hidden when there is nothing to search.
    public let showsSearch: Bool

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

/// Turns the stored dictations into the history page.
///
/// Retention is applied here rather than trusted to whatever wrote the list: the
/// promise is that a dictation older than the window is gone, and a page that would
/// happily draw one is a page that can break the promise on the store's behalf.
public enum HistoryPresenter {
    public static let searchPlaceholder = "Search"
    /// The sentence under the page's name. Says the two things somebody arriving
    /// here wants settled: everything is here, and none of it left the Mac.
    public static let caption = "Every dictation, kept on this Mac."

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

    /// Drops anything the app has promised to have deleted by now.
    ///
    /// Shared with the home page, which shows the newest entry and must not show one the
    /// user has been told is gone.
    ///
    /// A rolling window of whole days rather than a calendar span: "kept for seven days"
    /// is a promise about elapsed time, and reckoning it against a calendar would make
    /// the moment of deletion depend on which side of a daylight-saving change the
    /// dictation fell — and would give the promise a way to fail to be computed at all.
    /// Applies the promise the user was shown.
    ///
    /// Delegates to ``DictationRecord/survives(days:now:)`` rather than repeating the
    /// arithmetic: the store prunes by that rule, so any second implementation here is a
    /// chance to draw something the store has already deleted — which is exactly what
    /// the earlier inclusive comparison did at the boundary.
    static func retained(_ entries: [HistoryEntry], days: Int, now: Date) -> [HistoryEntry] {
        entries.filter { $0.survives(days: days, now: now) }
    }

    /// The privacy screen's promise, cut to what fits under a list.
    ///
    /// The audio half is dropped rather than reworded if a build ever does keep a
    /// recording: what is left is still true, where a shortened lie would not be.
    static func notice(for snapshot: HistorySnapshot) -> HistoryRetentionNotice {
        let text = snapshot.settings.transcriptRetentionDays
        let kept = "Kept on this Mac for \(MainFormatting.count(text, "day", "days")), then deleted."
        let sentence = snapshot.keepsRecordings ? kept : "\(kept) Recordings are never saved."

        return HistoryRetentionNotice(
            sentence: sentence,
            link: MainAction(title: "Change in Privacy settings", intent: .go(.settings(.privacy)))
        )
    }

    // MARK: - Searching

    /// Matches the text and the app name, ignoring case and accents.
    ///
    /// Dictation produces accented words the user will type unaccented when looking for
    /// them again, and a search that answers "no matches" to a word plainly on screen
    /// is worse than no search at all.
    static func matches(_ entries: [HistoryEntry], query: String, locale: Locale) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            contains(entry.text, needle, locale: locale)
                || contains(entry.applicationName, needle, locale: locale)
        }
    }

    private static func contains(_ haystack: String?, _ needle: String, locale: Locale) -> Bool {
        haystack?.range(
            of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
            locale: locale
        ) != nil
    }

    // MARK: - Grouping

    /// Groups by day, keeping the order the store handed them over in.
    ///
    /// Encounter order rather than a sort by timestamp, for the reason the store itself
    /// gives: the clock belongs to the caller, and a machine whose clock moved must not
    /// be able to shuffle the list. Days are merged as they are met, so a clock that did
    /// move cannot produce two sections both called "Today".
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

    static func title(
        for day: Date, snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> String {
        if calendar.isDate(day, inSameDayAs: snapshot.now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: snapshot.now),
            calendar.isDate(day, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return day.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    static func row(for entry: HistoryEntry, relativeTo now: Date, locale: Locale) -> HistoryRow {
        HistoryRow(
            id: entry.id,
            application: application(for: entry),
            when: when(entry.when, relativeTo: now, locale: locale),
            text: entry.text)
    }

    /// "2 minutes ago", measured against the clock the snapshot carries.
    ///
    /// `Date.formatted(.relative(…))` measures against the real one instead, which would
    /// let the row disagree with the retention the rest of the page is reasoned from —
    /// and would make a test of this depend on the minute it ran in.
    static func when(_ date: Date, relativeTo now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// A blank or whitespace-only app name is no name at all, and a tile with a space in
    /// it is worse than no tile.
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

    /// The application a dictation went to, identifier and all.
    ///
    /// One place rather than five: every page that lists dictations was calling
    /// `application(named:)` with the name alone, and each would have had to remember
    /// to pass the identifier as well.
    static func application(for entry: HistoryEntry) -> HistoryApplication? {
        entry.applicationName.flatMap {
            application(named: $0, identifier: entry.applicationIdentifier)
        }
    }

    // MARK: - Nothing to show

    /// Three different nothings, told apart, because the answer to each is different.
    static func emptyState(for snapshot: HistorySnapshot) -> MainEmptyState {
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return MainEmptyState(
                symbolName: "magnifyingglass",
                title: "No matches",
                message: "Nothing kept on this Mac mentions “\(query)”.")
        }
        if snapshot.entries.isEmpty {
            return MainEmptyState(
                symbolName: "clock",
                title: "Nothing yet",
                message: "What you dictate shows up here, and never leaves this Mac.")
        }
        // Something was handed over and none of it survived retention, which means the
        // promise was kept rather than that the user has never dictated.
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

// The Corrections page: every change Uttrflow made today, why, and the way to put it back.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// One change Uttrflow made: the stored change itself, named here so no page imports the store.
public typealias Correction = UttrflowHistory.Correction

/// The correction engine's own reasons, kept on the record; ``CorrectionReason/title`` is the row's pill.
public typealias CorrectionReason = UttrflowHistory.CorrectionReason

/// Which changes the page is listing; shared with the store, because both narrow the same list.
public typealias CorrectionsScope = UttrflowHistory.CorrectionsScope

/// One change, ready to draw.
public struct CorrectionRow: Sendable, Equatable, Identifiable {
    /// The change's identity.
    public let id: UUID
    /// What the recogniser heard.
    public let heard: String
    /// What Uttrflow wrote instead.
    public let wrote: String
    /// Struck through, because the word on screen is the one that was heard.
    public let isUndone: Bool
    /// Why, as a pill.
    public let reason: MainPill
    /// "4:12 PM".
    public let when: String
    /// Where the dictation went, when known.
    public let application: HistoryApplication?
    /// Absent on a change that has already been put back — there is nothing left to undo.
    public let undo: MainAction?

    /// Builds a row from its parts.
    public init(
        id: UUID,
        heard: String,
        wrote: String,
        isUndone: Bool,
        reason: MainPill,
        when: String,
        application: HistoryApplication?,
        undo: MainAction?
    ) {
        self.id = id
        self.heard = heard
        self.wrote = wrote
        self.isUndone = isUndone
        self.reason = reason
        self.when = when
        self.application = application
        self.undo = undo
    }
}

/// Everything the corrections page is drawn from.
public struct CorrectionsSnapshot: Sendable, Equatable {
    /// Newest first.
    public let corrections: [Correction]
    /// Today's dictations, so the caption can say how many sentences the changes are spread across.
    public let dictations: [HistoryEntry]
    /// What has been typed into the search field.
    public let query: String
    /// Which changes are listed.
    public let scope: CorrectionsScope
    /// The user's settings.
    public let settings: Settings
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but the clock defaults to empty.
    public init(
        corrections: [Correction] = [],
        dictations: [HistoryEntry] = [],
        query: String = "",
        scope: CorrectionsScope = .all,
        settings: Settings = .default,
        now: Date
    ) {
        self.corrections = corrections
        self.dictations = dictations
        self.query = query
        self.scope = scope
        self.settings = settings
        self.now = now
    }
}

/// What the corrections page shows.
public struct CorrectionsPresentation: Sendable, Equatable {
    /// The title, caption, scope and search field across the top.
    public let chrome: MainPageChrome
    /// Why this page exists at all, stated on the page rather than in a release note.
    public let callout: MainCallout
    /// "Today · 7 changes across 34 dictations".
    public let caption: String
    /// The changes that match the scope and query.
    public let rows: [CorrectionRow]
    /// Set when — and only when — ``rows`` is empty.
    public let emptyState: MainEmptyState?
    /// The line under the rows, absent when there are none.
    public let footnote: String?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        callout: MainCallout,
        caption: String,
        rows: [CorrectionRow],
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.callout = callout
        self.caption = caption
        self.rows = rows
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns what Uttrflow changed into the page that admits it; nothing is summarised, sampled or rounded.
public enum CorrectionsPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search"

    /// Draws the Corrections page from a snapshot.
    public static func page(
        for snapshot: CorrectionsSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> CorrectionsPresentation {
        let today = madeToday(snapshot, calendar: calendar)
        let listed = matches(
            snapshot.scope.matching(today), query: snapshot.query, locale: locale)
        let rows = listed.map { row(for: $0, locale: locale) }

        return CorrectionsPresentation(
            chrome: chrome(for: snapshot, anyToday: !today.isEmpty),
            callout: MainCallout(
                symbolName: "arrow.left.arrow.right",
                message: """
                    Every word Uttrflow changed today, and why. A product that quietly rewrites \
                    what you said owes you this page — nothing here happened without a reason, \
                    and nothing here is permanent.
                    """),
            caption: caption(for: snapshot, changes: today.count, calendar: calendar),
            rows: rows,
            emptyState: rows.isEmpty
                ? emptyState(for: snapshot, madeToday: today.count, calendar: calendar) : nil,
            // Dropped when the pane is empty: the empty state carries its own closing line.
            footnote: rows.isEmpty
                ? nil
                : """
                Undo teaches Uttrflow. Undo a word more often than you keep it and it stops \
                being applied — the word retires itself in your Dictionary.
                """)
    }

    // MARK: - Chrome

    /// The scope pop-up appears only once there is something to narrow.
    static func chrome(for snapshot: CorrectionsSnapshot, anyToday: Bool) -> MainPageChrome {
        MainPageChrome(
            title: "Corrections",
            caption: "What Uttrflow changed after it heard you.",
            scope: anyToday
                ? MainScope(
                    title: snapshot.scope.title,
                    options: CorrectionsScope.allCases.map {
                        MainScopeOption(
                            id: $0.rawValue, title: $0.title, isSelected: $0 == snapshot.scope)
                    })
                : nil,
            search: anyToday
                ? MainSearchField(placeholder: searchPlaceholder, query: snapshot.query) : nil)
    }

    /// "Today · 7 changes across 34 dictations"; both halves counted, since changes alone are unreadable.
    static func caption(
        for snapshot: CorrectionsSnapshot, changes: Int, calendar: Calendar
    ) -> String {
        let said = saidToday(in: snapshot, calendar: calendar)
        return """
            Today · \(MainFormatting.count(changes, "change", "changes")) across \
            \(MainFormatting.count(said, "dictation", "dictations"))
            """
    }

    /// How many dictations were made today, in one place so the caption and the chip cannot disagree.
    static func saidToday(in snapshot: CorrectionsSnapshot, calendar: Calendar) -> Int {
        snapshot.dictations.filter { calendar.isDate($0.when, inSameDayAs: snapshot.now) }.count
    }

    // MARK: - Choosing rows

    /// Today only; everything older belongs to the dictation it happened in, which is on History.
    static func madeToday(_ snapshot: CorrectionsSnapshot, calendar: Calendar) -> [Correction] {
        snapshot.corrections.filter { calendar.isDate($0.when, inSameDayAs: snapshot.now) }
    }

    /// Matches what was heard, what was written and the reason, since the pill is where the reason lives.
    static func matches(
        _ corrections: [Correction], query: String, locale: Locale
    ) -> [Correction] {
        SearchQuery.matches(corrections, query: query, locale: locale) {
            [$0.heard, $0.wrote, $0.reason.title]
        }
    }

    // MARK: - Drawing one

    /// One change as a row, with Undo unless it is already undone.
    static func row(for correction: Correction, locale: Locale) -> CorrectionRow {
        CorrectionRow(
            id: correction.id,
            heard: correction.heard,
            wrote: correction.wrote,
            isUndone: correction.isUndone,
            reason: MainPill(text: correction.reason.title),
            when: MainFormatting.time(correction.when, locale: locale),
            application: correction.applicationName.flatMap {
                HistoryPresenter.application(named: $0)
            },
            undo: correction.isUndone
                ? nil
                : MainAction(
                    title: "Undo", symbolName: "arrow.uturn.backward",
                    intent: .undoCorrection(correction.id)))
    }

    // MARK: - Nothing to show

    /// Four different nothings, since "it changed nothing" and "your filter hid everything" differ.
    static func emptyState(
        for snapshot: CorrectionsSnapshot, madeToday: Int, calendar: Calendar
    ) -> MainEmptyState {
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("Nothing Uttrflow changed today mentions “\(query)”.")
        }
        if madeToday > 0 {
            return MainEmptyState(
                symbolName: "line.3.horizontal.decrease",
                title: "Nothing in this view",
                message: """
                    \(MainFormatting.count(madeToday, "change", "changes")) today, and none of \
                    them is \(snapshot.scope.title.lowercased()).
                    """)
        }
        let said = saidToday(in: snapshot, calendar: calendar)
        return MainEmptyState(
            symbolName: "arrow.left.arrow.right",
            title: "Uttrflow changed nothing you said today",
            message: """
                It only changes a word when it has a reason it can name: a word in your \
                dictionary, a term it could see on your screen, a filler word, or punctuation. \
                When it does, the change is listed here with what it heard, what it wrote, and \
                an undo.
                """,
            chips: [
                MainStatistic(value: "\(said)", caption: said == 1 ? "dictation today" : "dictations today"),
                MainStatistic(value: "0", caption: "words changed"),
            ],
            footnote: "An empty page here is the good outcome, not a missing feature.")
    }
}

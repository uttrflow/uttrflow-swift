// The Corrections page: dictionary-backed substitutions, why, and the way to put them back.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings
import UttrflowCore

/// One dictionary-backed substitution: the stored change itself, named here so no page imports the store.
public typealias Correction = UttrflowHistory.Correction

/// The correction engine's own reasons, kept on the record; ``CorrectionReason/title`` is the row's pill.
public typealias CorrectionReason = UttrflowHistory.CorrectionReason

/// Which corrections the page is listing; shared with the store, because both narrow the same list.
public typealias CorrectionsScope = UttrflowHistory.CorrectionsScope

/// One dictionary-backed substitution, ready to draw.
public struct CorrectionRow: Sendable, Equatable, Identifiable {
    /// The correction's identity.
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
    /// Every dictation kept by the store, so the caption can say how many sentences the corrections are spread across.
    public let dictations: [HistoryEntry]
    /// What has been typed into the search field.
    public let query: String
    /// Which corrections are listed.
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
    /// "7 corrections across 34 dictations".
    public let caption: String
    /// The corrections that match the scope and query.
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

/// Turns dictionary-backed substitutions into the page that admits them; nothing is summarised, sampled or rounded.
public enum CorrectionsPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search"

    /// Draws the Corrections page from a snapshot.
    public static func page(
        for snapshot: CorrectionsSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> CorrectionsPresentation {
        let inWindow = retained(snapshot)
        let listed = matches(
            snapshot.scope.matching(inWindow), query: snapshot.query, locale: locale)
        let rows = listed.map { row(for: $0, locale: locale) }

        return CorrectionsPresentation(
            chrome: chrome(for: snapshot, anyKept: !inWindow.isEmpty),
            callout: MainCallout(
                symbolName: "arrow.left.arrow.right",
                message: """
                    Dictionary-backed word substitutions Uttrflow made, and why. Each row \
                    names what it heard, what it wrote from your Dictionary, and the undo that \
                    teaches that word when to retire.
                    """),
            caption: caption(for: snapshot, corrections: inWindow.count),
            rows: rows,
            emptyState: rows.isEmpty
                ? emptyState(for: snapshot, kept: inWindow.count) : nil,
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
    static func chrome(for snapshot: CorrectionsSnapshot, anyKept: Bool) -> MainPageChrome {
        MainPageChrome(
            title: "Corrections",
            caption: "Dictionary-backed substitutions Uttrflow made after it heard you.",
            scope: anyKept
                ? MainScope(
                    title: snapshot.scope.title,
                    options: CorrectionsScope.allCases.map {
                        MainScopeOption(
                            id: $0.rawValue, title: $0.title, isSelected: $0 == snapshot.scope)
                    })
                : nil,
            search: anyKept
                ? MainSearchField(placeholder: searchPlaceholder, query: snapshot.query) : nil)
    }

    /// "7 corrections across 34 dictations"; both halves counted, since corrections alone are unreadable.
    static func caption(for snapshot: CorrectionsSnapshot, corrections: Int) -> String {
        let said = dictationsInWindow(in: snapshot)
        return """
            \(MainFormatting.count(corrections, "correction", "corrections")) across \
            \(MainFormatting.count(said, "dictation", "dictations"))
            """
    }

    /// How many dictations are within the retention window, in one place so the caption and the chip cannot disagree.
    static func dictationsInWindow(in snapshot: CorrectionsSnapshot) -> Int {
        let window = RetentionWindow(
            days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        return snapshot.dictations.filter { window.keeps($0.when) }.count
    }

    // MARK: - Choosing rows

    /// Corrections within the retention window; the same window that keeps their dictations, so an undo can reach any of them.
    static func retained(_ snapshot: CorrectionsSnapshot) -> [Correction] {
        let window = RetentionWindow(
            days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        return snapshot.corrections.filter { window.keeps($0.when) }
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

    /// One correction as a row, with Undo unless it is already undone.
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

    /// Four different nothings, since "no corrections" and "your filter hid everything" differ.
    static func emptyState(for snapshot: CorrectionsSnapshot, kept: Int) -> MainEmptyState {
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("No dictionary correction mentions “\(query)”.")
        }
        if kept > 0 {
            return MainEmptyState(
                symbolName: "line.3.horizontal.decrease",
                title: "Nothing in this view",
                message: """
                    \(MainFormatting.count(kept, "correction", "corrections")), and \
                    none of them is \(snapshot.scope.title.lowercased()).
                    """)
        }
        let said = dictationsInWindow(in: snapshot)
        return MainEmptyState(
            symbolName: "arrow.left.arrow.right",
            title: "No dictionary corrections",
            message: """
                This page lists word substitutions backed by your Dictionary: a term visible on \
                screen, a spelling heard clearly elsewhere, stray letters, or several spoken words \
                joined into one entry. Cleanup such as filler removal, punctuation, layout, and \
                grammar does not appear here.
                """,
            chips: [
                MainStatistic(value: "\(said)", caption: said == 1 ? "dictation" : "dictations"),
                MainStatistic(value: "0", caption: "dictionary corrections"),
            ],
            footnote: "An empty page here is the good outcome, not a missing feature.")
    }
}

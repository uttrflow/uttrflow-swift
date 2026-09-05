// The Dictation page: today's rows, the figures in the rail, and the empty states.
public import Foundation
public import UttrflowCore
public import UttrflowHistory
public import UttrflowSettings

/// One of today's dictations, ready to draw.
public struct DictationRow: Sendable, Equatable, Identifiable {
    /// The history entry this row shows.
    public let id: UUID
    /// "4:12 PM".
    public let when: String
    /// What was said.
    public let text: String
    /// The app it went into, when known.
    public let application: HistoryApplication?
    /// "11s · 21 words", or just the words when nothing timed it; a duration is never invented.
    public let detail: String
    /// "2 changes", leading to the page that lists them; absent when Uttrflow left the sentence alone.
    public let changes: MainAction?
    /// Copy, insert again and flag — always all three, in that order, so pointing at a row never reflows it.
    public let actions: [MainAction]
    /// What the overflow menu offers.
    public let more: [MainAction]
    /// Set on a kept recording, which has no words yet: what stands in for them.
    public let status: DictationRowStatus?
    /// The one button drawn in full whether or not the row is pointed at.
    public let prominent: MainAction?

    /// Builds a row; the badge and the prominent button belong to kept recordings only.
    public init(
        id: UUID,
        when: String,
        text: String,
        application: HistoryApplication?,
        detail: String,
        changes: MainAction?,
        actions: [MainAction],
        more: [MainAction],
        status: DictationRowStatus? = nil,
        prominent: MainAction? = nil
    ) {
        self.id = id
        self.when = when
        self.text = text
        self.application = application
        self.detail = detail
        self.changes = changes
        self.actions = actions
        self.more = more
        self.status = status
        self.prominent = prominent
    }
}

/// Where a kept recording has got to, as the badge on its row says it.
public enum DictationRowStatus: String, Sendable, Equatable, CaseIterable {
    /// The recording has no words yet and nothing is trying.
    case waiting = "Not transcribed"
    /// The recording is going through transcription again.
    case retrying = "Retrying…"
}

/// Everything the dictation page is drawn from.
public struct DictationSnapshot: Sendable, Equatable {
    /// What macOS has granted; an absent permission has not been checked yet and is not reported.
    public let permissions: [PermissionKind: PermissionStatus]
    /// Newest first, before retention is applied; every day, since the figures compare today with earlier.
    public let entries: [HistoryEntry]
    /// Every change the dictionary made, so a row can count its own.
    public let corrections: [Correction]
    /// What has been typed into the search field.
    public let query: String
    /// The shortcut as it reads on a keycap, "⌥Space", formatted by the app.
    public let shortcut: String
    /// The user's settings.
    public let settings: Settings
    /// Recordings whose words were lost, newest first, each waiting for a retry.
    public let recordings: [KeptRecording]
    /// The recording going through transcription again right now, if one is.
    public let retrying: UUID?
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but the shortcut and the clock defaults to empty.
    public init(
        permissions: [PermissionKind: PermissionStatus] = [:],
        entries: [HistoryEntry] = [],
        corrections: [Correction] = [],
        query: String = "",
        shortcut: String,
        settings: Settings = .default,
        recordings: [KeptRecording] = [],
        retrying: UUID? = nil,
        now: Date
    ) {
        self.permissions = permissions
        self.entries = entries
        self.corrections = corrections
        self.query = query
        self.shortcut = shortcut
        self.settings = settings
        self.recordings = recordings
        self.retrying = retrying
        self.now = now
    }
}

/// What the dictation page shows.
public struct DictationPresentation: Sendable, Equatable {
    /// The title, caption and search field across the top.
    public let chrome: MainPageChrome
    /// Set when the app cannot work at all, and then it is the whole page.
    public let blocked: MainEmptyState?
    /// "Today · Sunday 23 August".
    public let caption: String
    /// Kept recordings first, then today's dictations that match the query.
    public let rows: [DictationRow]
    /// The right-hand rail; only figures with something real behind them, so it may be two tiles long.
    public let figures: [MainStatistic]
    /// Set when — and only when — ``rows`` is empty and nothing is ``blocked``.
    public let emptyState: MainEmptyState?
    /// The line under the rows, absent when there are none.
    public let footnote: String?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        blocked: MainEmptyState?,
        caption: String,
        rows: [DictationRow],
        figures: [MainStatistic],
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.blocked = blocked
        self.caption = caption
        self.rows = rows
        self.figures = figures
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns today into the landing page; everything older belongs to History.
public enum DictationPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search today"

    /// How many earlier days the pace and accuracy comparisons need before "your usual" is said.
    static let comparisonFloor = 1

    /// What the accuracy figure measures, shared with Insights; the denominator is the words said.
    static let accuracyCaption = "Words that came out exactly as you said them."

    /// Draws the Dictation page from a snapshot.
    public static func page(
        for snapshot: DictationSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> DictationPresentation {
        let kept = HistoryPresenter.retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let (today, earlier) = HistoryPresenter.todayAndEarlier(
            in: kept, now: snapshot.now, calendar: calendar)
        let listed = HistoryPresenter.matches(today, query: snapshot.query, locale: locale)
        let blocked = MainPresenter.obstruction(in: snapshot.permissions)
        // Recordings first: each is a dictation still owed its words, and the newest thing here.
        let recordings =
            blocked == nil && snapshot.query.isEmpty
            ? snapshot.recordings.map { row(for: $0, in: snapshot, locale: locale) } : []
        let rows =
            recordings + (blocked == nil ? listed.map { row(for: $0, in: snapshot, locale: locale) } : [])

        return DictationPresentation(
            chrome: MainPageChrome(
                title: "Dictation",
                caption: "Everything you said today, and what Uttrflow did with it.",
                search: today.isEmpty || blocked != nil
                    ? nil
                    : MainSearchField(placeholder: searchPlaceholder, query: snapshot.query)),
            blocked: blocked,
            caption: caption(for: snapshot, locale: locale),
            rows: rows,
            figures: blocked == nil
                ? figures(
                    today: today, earlier: earlier, calendar: calendar, locale: locale) : [],
            emptyState: blocked == nil && rows.isEmpty
                ? emptyState(
                    for: snapshot, today: today, earlier: earlier, calendar: calendar,
                    locale: locale)
                : nil,
            footnote: rows.isEmpty
                ? nil
                : """
                Point at a row for copy, insert again, flag and more. Today stays here; \
                everything older moves to History.
                """)
    }

    /// "Today · Sunday 23 August", with the date spelt out because the whole page depends on it.
    static func caption(for snapshot: DictationSnapshot, locale: Locale) -> String {
        let date = snapshot.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return "Today · \(date)"
    }

    // MARK: - One dictation

    /// One dictation as a row with copy, insert again and flag.
    static func row(
        for entry: HistoryEntry, in snapshot: DictationSnapshot, locale: Locale
    ) -> DictationRow {
        // Read from the record, so a dictation that recorded nothing shows no badge.
        let applied =
            entry.changes == nil
            ? 0
            : snapshot.corrections.filter { $0.dictation == entry.id && !$0.isUndone }.count
        return DictationRow(
            id: entry.id,
            when: MainFormatting.time(entry.when, locale: locale),
            text: entry.text,
            application: HistoryPresenter.application(for: entry),
            detail: detail(for: entry),
            changes: applied > 0
                ? MainAction(
                    title: MainFormatting.count(applied, "change", "changes"),
                    intent: .show(.corrections))
                : nil,
            actions: [
                MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(entry.text)),
                MainAction(
                    title: "Insert Again", symbolName: "arrow.clockwise",
                    intent: .insert(entry.text)),
                // The label says what pressing it does, so a recorded flag can be told from one that was not.
                MainAction(
                    title: entry.isFlagged ? "Unflag" : "Flag",
                    symbolName: entry.isFlagged ? "flag.fill" : "flag",
                    intent: .flagDictation(entry.id)),
            ],
            more: [.delete(.forgetDictation(entry.id))])
    }

    /// A kept recording as a row: what stands in for its words, and the one button that gets them.
    static func row(
        for recording: KeptRecording, in snapshot: DictationSnapshot, locale: Locale
    ) -> DictationRow {
        let retrying = snapshot.retrying == recording.id
        return DictationRow(
            id: recording.id,
            when: MainFormatting.time(recording.when, locale: locale),
            text: retrying ? "Transcribing…" : "Couldn’t turn this into text",
            application: nil,
            detail: MainFormatting.spoken(recording.duration),
            changes: nil,
            actions: [],
            more: retrying ? [] : [.delete(.forgetRecording(recording.id))],
            status: retrying ? .retrying : .waiting,
            prominent: retrying
                ? nil
                : MainAction(
                    title: "Retry", symbolName: "arrow.clockwise",
                    intent: .retryRecording(recording.id)))
    }

    /// "11s · 21 words"; the words come second so they can stand alone when nothing timed it.
    static func detail(for entry: HistoryEntry) -> String {
        let words = MainFormatting.count(MainFormatting.words(in: entry.text), "word", "words")
        guard let spoken = entry.spokenFor else { return words }
        return "\(MainFormatting.spoken(spoken)) · \(words)"
    }

    // MARK: - The rail

    /// Only figures with something real behind them; no "time saved" tile, since nothing measures typing.
    static func figures(
        today: [HistoryEntry], earlier: [HistoryEntry], calendar: Calendar, locale: Locale
    ) -> [MainStatistic] {
        var figures: [MainStatistic] = []
        let kept = today + earlier

        // Words within the retention window, never a lifetime total: older words are gone.
        let all = kept.totalWords
        let todayWords = today.totalWords
        if all > 0 {
            figures.append(
                MainStatistic(
                    value: MainFormatting.compact(all, locale: locale),
                    caption: "Words dictated",
                    comment: todayWords > 0
                        ? "\(todayWords.formatted(.number.locale(locale))) of them today"
                        : "none yet today"))
        }

        if let run = streak(in: kept, calendar: calendar) {
            figures.append(
                MainStatistic(
                    value: "\(run.days)",
                    caption: run.days == 1 ? "Day dictating" : "Day streak",
                    // A streak reaching the oldest thing kept is a floor, so it says "at least".
                    comment: run.reachesTheEdge
                        ? "at least — anything older has been deleted"
                        : "days in a row"))
        }

        if let pace = pace(of: today) {
            let usual = earlier.count >= comparisonFloor ? self.pace(of: earlier) : nil
            figures.append(
                MainStatistic(
                    value: "\(pace)",
                    caption: "Words per minute",
                    comment: usual.map { "your usual pace is \($0)" }))
        }

        if let accuracy = accuracy(of: today) {
            let baseline =
                earlier.count >= comparisonFloor ? self.accuracy(of: earlier) : nil
            figures.append(
                MainStatistic(
                    value: MainFormatting.percentage(accuracy, locale: locale),
                    caption: "Accuracy",
                    comment: baseline.map {
                        """
                        \(Self.accuracyCaption) Your baseline is \
                        \(MainFormatting.percentage($0, locale: locale)).
                        """
                    } ?? Self.accuracyCaption,
                    meters: meters(now: accuracy, baseline: baseline)))
        }

        return figures
    }

    /// Words per minute pooled across every timed dictation; `nil` when nothing was timed.
    static func pace(of entries: [HistoryEntry]) -> Int? {
        // Reduced to words and seconds as found, so untimed entries never reach the sum.
        let timed = entries.compactMap { entry -> (words: Int, seconds: Double)? in
            guard let spoken = entry.spokenFor else { return nil }
            return (MainFormatting.words(in: entry.text), spoken.inSeconds)
        }
        let seconds = timed.reduce(0.0) { $0 + $1.seconds }
        guard seconds > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.words }
        return Int((Double(words) / seconds * 60).rounded())
    }

    /// The share of spoken words that came out as said, measured dictations only. See Docs/ux-figures.md.
    static func accuracy(of entries: [HistoryEntry]) -> Double? {
        var spoken = 0
        var changed = 0
        for changes in entries.compactMap(\.changes) {
            guard let said = changes.spokenWords else { continue }
            spoken += said
            changed += changes.correctedWords
        }
        guard spoken > 0 else { return nil }
        return Double(spoken - changed) / Double(spoken)
    }

    /// Days in a row back from the most recent day, not today; `nil` when nothing is kept.
    static func streak(
        in entries: [HistoryEntry], calendar: Calendar
    ) -> (days: Int, reachesTheEdge: Bool)? {
        let days = Set(entries.map { calendar.startOfDay(for: $0.when) }).sorted(by: >)
        guard let newest = days.first else { return nil }

        var run = 1
        var expected = newest
        for day in days.dropFirst() {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: expected),
                calendar.isDate(day, inSameDayAs: previous)
            else { break }
            run += 1
            expected = day
        }
        // Every day kept is in the run, so the run is bounded by what is kept, not by when the user started.
        return (run, run == days.count && days.count > 1)
    }

    /// Today's accuracy as a meter, with the baseline beside it when there is one.
    static func meters(now: Double, baseline: Double?) -> [MainMeter] {
        var meters = [MainMeter(label: "Today", fraction: now)]
        if let baseline {
            meters.append(MainMeter(label: "Baseline", fraction: baseline, isBaseline: true))
        }
        return meters
    }

    // MARK: - Nothing to show

    /// Three nothings: no matches, nothing today, nothing ever — each needs its own sentence.
    static func emptyState(
        for snapshot: DictationSnapshot, today: [HistoryEntry], earlier: [HistoryEntry],
        calendar: Calendar, locale: Locale
    ) -> MainEmptyState {
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("Nothing you dictated today mentions “\(query)”.")
        }

        // The verb follows how the shortcut is set up: "hold" a key that toggles does not work.
        let verb = snapshot.settings.hotkeyActivation == .holdToTalk ? "Hold" : "Press"
        let chips = chips(
            for: earlier, snapshot: snapshot, calendar: calendar, locale: locale)
        return MainEmptyState(
            symbolName: "mic",
            title: "Nothing dictated today",
            message: """
                \(verb) \(snapshot.shortcut) anywhere and talk. You don’t need this window \
                open — whatever you say lands in the app you were already typing into.
                """,
            chips: chips,
            // Tied to the chips: the sentence explains the figures, so with no figures it explains nothing.
            footnote: chips.isEmpty
                ? nil
                : """
                Yesterday’s figures, so the pane is never blank. Today’s start counting from \
                your first dictation.
                """)
    }

    /// Yesterday's figures under an empty pane, only yesterday's so nothing reads as today's.
    static func chips(
        for earlier: [HistoryEntry], snapshot: DictationSnapshot, calendar: Calendar,
        locale: Locale
    ) -> [MainStatistic] {
        // Counted as a difference of whole days, so no date arithmetic can fail.
        let today = calendar.startOfDay(for: snapshot.now)
        let said = earlier.filter {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.when), to: today)
                .day == 1
        }
        guard !said.isEmpty else { return [] }

        var chips = [
            MainStatistic(
                value: said.totalWords.formatted(.number.locale(locale)),
                caption: "words yesterday")
        ]
        if let pace = pace(of: said) {
            chips.append(MainStatistic(value: "\(pace)", caption: "wpm yesterday"))
        }
        if let accuracy = accuracy(of: said) {
            chips.append(
                MainStatistic(
                    value: MainFormatting.percentage(accuracy, locale: locale),
                    caption: "accuracy yesterday"))
        }
        return chips
    }
}

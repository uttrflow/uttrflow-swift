public import Foundation
public import UttrflowCore
public import UttrflowHistory
public import UttrflowSettings

/// One of today's dictations, ready to draw.
public struct DictationRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// "4:12 PM".
    public let when: String
    public let text: String
    public let application: HistoryApplication?
    /// "11s · 21 words", or just the words when nothing timed it. A duration invented
    /// for a dictation nobody measured would make the words-per-minute figure a fiction.
    public let detail: String
    /// "2 changes", leading to the page that lists them. Absent when Uttrflow left the
    /// sentence alone, which is most of them.
    public let changes: MainAction?
    /// Copy, insert again and flag — always all three, in that order, so pointing at a
    /// row never reflows it.
    public let actions: [MainAction]
    /// What the overflow menu offers.
    public let more: [MainAction]

    public init(
        id: UUID,
        when: String,
        text: String,
        application: HistoryApplication?,
        detail: String,
        changes: MainAction?,
        actions: [MainAction],
        more: [MainAction]
    ) {
        self.id = id
        self.when = when
        self.text = text
        self.application = application
        self.detail = detail
        self.changes = changes
        self.actions = actions
        self.more = more
    }
}

/// Everything the dictation page is drawn from.
public struct DictationSnapshot: Sendable, Equatable {
    /// What macOS has granted. A permission that is absent has not been checked yet, and
    /// the page stays quiet about it rather than accusing the user of withholding it.
    public let permissions: [PermissionKind: PermissionStatus]
    /// Newest first, before retention is applied. Everything, not only today: the
    /// figures compare today against the days before it.
    public let entries: [HistoryEntry]
    public let corrections: [Correction]
    public let query: String
    /// The shortcut as it reads on a keycap, for example "⌥Space". Formatted by the app,
    /// which owns the mapping from key codes to the glyphs on a physical keyboard.
    public let shortcut: String
    public let settings: Settings
    public let now: Date

    public init(
        permissions: [PermissionKind: PermissionStatus] = [:],
        entries: [HistoryEntry] = [],
        corrections: [Correction] = [],
        query: String = "",
        shortcut: String,
        settings: Settings = .default,
        now: Date
    ) {
        self.permissions = permissions
        self.entries = entries
        self.corrections = corrections
        self.query = query
        self.shortcut = shortcut
        self.settings = settings
        self.now = now
    }
}

/// What the dictation page shows.
public struct DictationPresentation: Sendable, Equatable {
    public let chrome: MainPageChrome
    /// Set when the app cannot work at all, and then it is the whole page: listing
    /// today's dictations under a broken microphone answers the wrong question.
    public let blocked: MainEmptyState?
    /// "Today · Sunday 23 August".
    public let caption: String
    public let rows: [DictationRow]
    /// The right-hand rail. Only figures with something real behind them, so the rail
    /// can be two tiles long on a Mac that has not measured the third.
    public let figures: [MainStatistic]
    /// Set when — and only when — ``rows`` is empty and nothing is ``blocked``.
    public let emptyState: MainEmptyState?
    public let footnote: String?

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

/// Turns today into the landing page.
///
/// Today and only today. Everything older moves to History, which is the one rule that
/// keeps this page a page about what just happened rather than a second history with a
/// different sort order.
public enum DictationPresenter {
    public static let searchPlaceholder = "Search today"

    /// Insights waits for a week of evidence; this page compares today against whatever
    /// there is, so it needs a floor of its own. One earlier day is enough for "your
    /// usual pace is 126" to be a fact rather than a coincidence of one morning.
    static let comparisonFloor = 1

    /// What the accuracy figure is a figure of, in the user's terms.
    ///
    /// Spelt out here and shared with Insights because it is a claim about the
    /// arithmetic, and a caption that says one thing on two pages while the number means
    /// another is how the old figure went unnoticed. It says *said* rather than
    /// *written*: the denominator is the utterance, so a dictation the dictionary
    /// improved is not penalised for coming out shorter than it was spoken.
    static let accuracyCaption = "Words that came out exactly as you said them."

    public static func page(
        for snapshot: DictationSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> DictationPresentation {
        let kept = HistoryPresenter.retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let today = kept.filter { calendar.isDate($0.when, inSameDayAs: snapshot.now) }
        let earlier = kept.filter { !calendar.isDate($0.when, inSameDayAs: snapshot.now) }
        let listed = HistoryPresenter.matches(today, query: snapshot.query, locale: locale)
        let blocked = MainPresenter.obstruction(in: snapshot.permissions)
        let rows =
            blocked == nil
            ? listed.map { row(for: $0, in: snapshot, locale: locale) } : []

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

    /// "Today · Sunday 23 August". The date is spelt out because this is the one page
    /// whose whole contents depend on which day it is.
    static func caption(for snapshot: DictationSnapshot, locale: Locale) -> String {
        let date = snapshot.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return "Today · \(date)"
    }

    // MARK: - One dictation

    static func row(
        for entry: HistoryEntry, in snapshot: DictationSnapshot, locale: Locale
    ) -> DictationRow {
        // Read from the record rather than from a flag about the history as a whole: a
        // dictation that recorded nothing shows no badge, and one beside it that recorded
        // three shows three. An app-level claim could only ever be right about both by
        // being wrong about one.
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
                // Says what pressing it will do, and shows what it has already done.
                // A button whose label never changes gives the user no way to tell a
                // flag that was recorded from one that was not.
                MainAction(
                    title: entry.isFlagged ? "Unflag" : "Flag",
                    symbolName: entry.isFlagged ? "flag.fill" : "flag",
                    intent: .flagDictation(entry.id)),
            ],
            more: [
                MainAction(
                    title: "Delete", symbolName: "trash", intent: .forgetDictation(entry.id),
                    isDestructive: true)
            ])
    }

    /// "11s · 21 words". The duration is dropped rather than guessed when nothing timed
    /// the dictation, which is why the words come second and can stand alone.
    static func detail(for entry: HistoryEntry) -> String {
        let words = MainFormatting.count(MainFormatting.words(in: entry.text), "word", "words")
        guard let spoken = entry.spokenFor else { return words }
        return "\(MainFormatting.spoken(spoken)) · \(words)"
    }

    // MARK: - The rail

    /// Only figures with something real behind them.
    ///
    /// There is no "time saved" tile. It would need a guess at how fast the user types,
    /// and Uttrflow has never watched them type — one invented number would make the true
    /// ones unreadable. The same rule retires each of these when its source is missing:
    /// no timings, no pace; no record of changes, no accuracy.
    static func figures(
        today: [HistoryEntry], earlier: [HistoryEntry], calendar: Calendar, locale: Locale
    ) -> [MainStatistic] {
        var figures: [MainStatistic] = []
        let kept = today + earlier

        // How much has been dictated altogether, which is the figure somebody opening the
        // app wants first — and the one place the wording has to be careful. It is not a
        // lifetime total and must never be called one: the history keeps a retention
        // window and no more, so words older than that are gone and cannot be counted.
        // "Words dictated" over "in the N days Uttrflow keeps" is the whole truth.
        let all = kept.reduce(0) { $0 + MainFormatting.words(in: $1.text) }
        let todayWords = today.reduce(0) { $0 + MainFormatting.words(in: $1.text) }
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
                    // A streak that reaches the oldest thing kept is a floor, not a
                    // measurement: the day before it may well have had a dictation that
                    // has since been deleted. Saying "at least" is the difference between
                    // a number and a guess.
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

    /// Words per minute across every dictation that was actually timed.
    ///
    /// Pooled rather than averaged per dictation, so a two-word aside does not weigh as
    /// much as a two-minute paragraph. `nil` when nothing was timed, which is the honest
    /// answer and draws no tile.
    static func pace(of entries: [HistoryEntry]) -> Int? {
        // Reduced to the two numbers that matter as they are found, so the untimed
        // entries are gone by the time anything is added up and there is no second
        // place to decide what an untimed one counts as.
        let timed = entries.compactMap { entry -> (words: Int, seconds: Double)? in
            guard let spoken = entry.spokenFor else { return nil }
            return (MainFormatting.words(in: entry.text), spoken.inSeconds)
        }
        let seconds = timed.reduce(0.0) { $0 + $1.seconds }
        guard seconds > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.words }
        return Int((Double(words) / seconds * 60).rounded())
    }

    /// The share of the words the user actually said that came out as they said them.
    ///
    /// **Both halves count spoken words, and both are read out of the same value.** That
    /// is the whole of the arithmetic, and it is a correction to a figure that was wrong
    /// in exactly that place: the denominator used to be the words of the *finished
    /// text* while the subtrahend was the words that were *heard*. Two of the engine's
    /// four reasons — ``CorrectionReason/heardAsStrayLetters`` and
    /// ``CorrectionReason/heardAsSeveralWords`` — exist precisely to write one word over
    /// several, so the subtrahend routinely exceeded the denominator. Dictating "the s q
    /// l query" with SQL in the dictionary reported **0%**, under a caption telling the
    /// user how much of their own wording had survived. Two of those five words had.
    ///
    /// There is no `max(_:0)` under it any more, and its absence is load-bearing. The
    /// clamp was not guarding an impossible case; it was converting a units mismatch
    /// into a plausible-looking zero, which is how the mismatch survived. What replaces
    /// it is ``RecordedChanges/correctedWords`` counting distinct positions *within* the
    /// utterance, so the subtrahend cannot exceed the utterance whatever is on disk.
    ///
    /// Measured dictations only, and that is the rest of the honesty. A dictation whose
    /// insertion failed reports no changes — not "no changes were made", but "nobody was
    /// keeping a record" — and counting its words in the denominator while its
    /// corrections cannot appear in the numerator would report an accuracy higher than
    /// the truth. Leaving it out narrows the sample and keeps the figure true: a smaller
    /// honest number beats a larger invented one. It also means the figure appears as
    /// soon as one dictation has been measured, rather than staying hidden for the whole
    /// retention window after any single failed insertion.
    ///
    /// A dictation from a build that kept changes but never counted the utterance is
    /// left out on the same grounds. Its ``RecordedChanges/spokenWords`` is `nil`, and
    /// there is no way back to the number from what was kept — so the sample simply
    /// starts where the counting started.
    ///
    /// `nil` when nothing has been measured, or when nothing was said — in both cases the
    /// arithmetic would produce a number with no meaning behind it.
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

    /// How many days in a row, counting back from the most recent one.
    ///
    /// From the most recent day rather than from today, so a streak is not reported as
    /// broken at breakfast: somebody who dictated every day for a fortnight and has not
    /// yet opened their laptop this morning still has a fortnight's streak. It breaks when
    /// a whole day passes with nothing in it, which is when it has actually broken.
    ///
    /// `nil` for nothing kept — there is no streak to report, and zero would read as one
    /// that had just ended.
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
        // Every day kept is in the run, so the run is bounded by what is kept rather than
        // by when the user actually started.
        return (run, run == days.count && days.count > 1)
    }

    static func meters(now: Double, baseline: Double?) -> [MainMeter] {
        var meters = [MainMeter(label: "Today", fraction: now)]
        if let baseline {
            meters.append(MainMeter(label: "Baseline", fraction: baseline, isBaseline: true))
        }
        return meters
    }

    // MARK: - Nothing to show

    /// Three nothings. A user who searched and found none of their own words needs a
    /// different sentence from one who has not spoken yet today.
    static func emptyState(
        for snapshot: DictationSnapshot, today: [HistoryEntry], earlier: [HistoryEntry],
        calendar: Calendar, locale: Locale
    ) -> MainEmptyState {
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return MainEmptyState(
                symbolName: "magnifyingglass",
                title: "No matches",
                message: "Nothing you dictated today mentions “\(query)”.")
        }

        // The verb follows how the shortcut is set up: telling somebody to hold a key
        // that toggles is an instruction that does not work.
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
            // Tied to the chips rather than to whether anything older exists: the
            // sentence explains the figures, so with no figures it explains nothing.
            footnote: chips.isEmpty
                ? nil
                : """
                Yesterday’s figures, so the pane is never blank. Today’s start counting from \
                your first dictation.
                """)
    }

    /// Yesterday's figures under an empty pane, so it says something true rather than
    /// nothing at all. Only yesterday's: a week's total under today's heading would be
    /// the sort of number a user reads as today's and is never corrected about.
    static func chips(
        for earlier: [HistoryEntry], snapshot: DictationSnapshot, calendar: Calendar,
        locale: Locale
    ) -> [MainStatistic] {
        // Counted as a difference of whole days rather than by subtracting a date, so
        // there is no arithmetic that can fail and no branch for what to do if it did.
        let today = calendar.startOfDay(for: snapshot.now)
        let said = earlier.filter {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.when), to: today)
                .day == 1
        }
        guard !said.isEmpty else { return [] }

        var chips = [
            MainStatistic(
                value: said.reduce(0) { $0 + MainFormatting.words(in: $1.text) }
                    .formatted(.number.locale(locale)),
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

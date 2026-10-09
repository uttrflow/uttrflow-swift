// The History page: kept dictations grouped by day, searched, and cut to the retention promise.
public import Foundation
public import UttrflowCore
public import UttrflowHistory
public import UttrflowSettings
private import Synchronization

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

/// A recording whose words were lost, as its row draws it: the pill to hear it and the way to retry.
public struct HistoryRecording: Sendable, Equatable {
    /// How long it runs, on a clock: "0:06".
    public let duration: String
    /// "Couldn’t turn this into text", or "Transcribing…" while a retry runs.
    public let message: String
    /// Plays the recording, or stops it while it is playing.
    public let play: MainAction
    /// Whether it is playing now, so the button shows stop.
    public let isPlaying: Bool
    /// Runs it through transcription again; absent while that is already happening.
    public let retry: MainAction?

    /// Builds the recording's parts.
    public init(
        duration: String, message: String, play: MainAction, isPlaying: Bool, retry: MainAction?
    ) {
        self.duration = duration
        self.message = message
        self.play = play
        self.isPlaying = isPlaying
        self.retry = retry
    }
}

/// One dictation, or one recording still owed its words, ready to draw.
public struct HistoryRow: Sendable, Equatable, Identifiable {
    /// The dictation's identity, or the recording's.
    public let id: UUID
    /// Absent when nothing was known about where the text went, rather than labelled "Unknown".
    public let application: HistoryApplication?
    /// How long ago, in words: "2 minutes ago".
    public let when: String
    /// What was said; empty for a recording, which has no words yet.
    public let text: String
    /// The time on the rail, on the 24-hour clock: "10:41".
    public let time: String
    /// "0:09 · 23 words", or just the words when nothing timed it.
    public let length: String
    /// "2 changes" when the clean-up changed anything; absent otherwise.
    public let tag: String?
    /// Whether the user flagged it as wrong.
    public let isFlagged: Bool
    /// "Not inserted" or "Unconfirmed" when the words may not have reached the field; absent otherwise.
    public let arrival: String?
    /// The buttons shown while the row is pointed at: copy, copy to paste elsewhere, flag.
    public let actions: [MainAction]
    /// What the row's context menu offers.
    public let more: [MainAction]
    /// Set on a recording whose words were lost, which draws in place of the text.
    public let recording: HistoryRecording?
    /// One "Fix" per distinct word in the text, each opening the word editor on that spelling.
    public let fixes: [MainAction]
    /// Why each word changed: one read-only phrase per dictionary correction, then per ledgered clean-up change.
    public let whatChanged: [String]

    /// Builds a row from its parts; everything after the text defaults to a bare dictation.
    public init(
        id: UUID, application: HistoryApplication?, when: String, text: String,
        time: String = "", length: String = "", tag: String? = nil, isFlagged: Bool = false,
        arrival: String? = nil, actions: [MainAction] = [], more: [MainAction] = [],
        recording: HistoryRecording? = nil, fixes: [MainAction] = [], whatChanged: [String] = []
    ) {
        self.id = id
        self.application = application
        self.when = when
        self.text = text
        self.time = time
        self.length = length
        self.tag = tag
        self.isFlagged = isFlagged
        self.arrival = arrival
        self.actions = actions
        self.more = more
        self.recording = recording
        self.fixes = fixes
        self.whatChanged = whatChanged
    }
}

/// A day's worth of dictations.
public struct HistoryDay: Sendable, Equatable, Identifiable {
    /// "Today", "Yesterday", or the date.
    public let title: String
    /// The day's dictations, in the store's order.
    public let rows: [HistoryRow]
    /// "4 dictations · 1,284 words", beside the title.
    public let summary: String

    /// The title, which is unique on the page.
    public var id: String { title }

    /// Builds a day; the summary defaults to none.
    public init(title: String, rows: [HistoryRow], summary: String = "") {
        self.title = title
        self.rows = rows
        self.summary = summary
    }
}

/// The promise the user was shown, restated under the list even when the list is empty.
public struct HistoryRetentionNotice: Sendable, Equatable {
    /// The promise, cut to fit under the list.
    public let sentence: String
    /// The way to the privacy settings.
    public let link: MainAction
    /// The promise cut to a phrase for the caption: "kept for 30 days".
    public let phrase: String

    /// Builds the notice; the phrase defaults to none.
    public init(sentence: String, link: MainAction, phrase: String = "") {
        self.sentence = sentence
        self.link = link
        self.phrase = phrase
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
    /// Whether the Clipboard switch permits a History row to be kept as a clip.
    public let canKeepAsClip: Bool
    /// Recordings whose words were lost, newest first, each waiting for a retry.
    public let recordings: [KeptRecording]
    /// The recording going through transcription again right now, if one is.
    public let retrying: UUID?
    /// The recording playing right now, if one is.
    public let playing: UUID?
    /// The clock the page is drawn against.
    public let now: Date
    /// Whether ``entries`` has been read from the store yet; false only before the first reading.
    public let hasReadHistory: Bool

    /// Builds a snapshot; everything but entries and the clock has a default.
    public init(
        entries: [HistoryEntry],
        query: String = "",
        settings: Settings = .default,
        keepsRecordings: Bool = false,
        canKeepAsClip: Bool = false,
        recordings: [KeptRecording] = [],
        retrying: UUID? = nil,
        playing: UUID? = nil,
        now: Date,
        hasReadHistory: Bool = true
    ) {
        self.entries = entries
        self.query = query
        self.settings = settings
        self.keepsRecordings = keepsRecordings
        self.canKeepAsClip = canKeepAsClip
        self.recordings = recordings
        self.retrying = retrying
        self.playing = playing
        self.now = now
        self.hasReadHistory = hasReadHistory
    }
}

/// What the history page shows.
public struct HistoryPresentation: Sendable, Equatable {
    /// The dictations, grouped by day.
    public let days: [HistoryDay]
    /// Set when ``days`` is empty once the history is read, saying which of three reasons nothing survived.
    public let emptyState: MainEmptyState?
    /// The promise under the list.
    public let retentionNotice: HistoryRetentionNotice
    /// Whether the search field is worth showing. Hidden when there is nothing to search.
    public let showsSearch: Bool
    /// The four stat tiles across the top, the same figures home shows; empty when nothing is kept.
    public let tiles: [HomeStatTile]
    /// Set until the history has first been read, when the page shows only its header.
    public let isReading: Bool

    /// Builds the page from its parts; no tiles unless given.
    public init(
        days: [HistoryDay],
        emptyState: MainEmptyState?,
        retentionNotice: HistoryRetentionNotice,
        showsSearch: Bool,
        tiles: [HomeStatTile] = [],
        isReading: Bool = false
    ) {
        self.days = days
        self.emptyState = emptyState
        self.retentionNotice = retentionNotice
        self.showsSearch = showsSearch
        self.tiles = tiles
        self.isReading = isReading
    }
}

/// Turns the stored dictations into the history page, applying retention rather than trusting the list.
public enum HistoryPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search everything you said"
    /// The sentence under the page's name: everything is here, and none of it left the Mac.
    public static let caption = "Every dictation, kept on this Mac"

    /// Draws the History page from a snapshot.
    public static func page(
        for snapshot: HistorySnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> HistoryPresentation {
        // Nothing is said about an empty history before the store has answered.
        guard snapshot.hasReadHistory else {
            return HistoryPresentation(
                days: [], emptyState: nil, retentionNotice: notice(for: snapshot), showsSearch: false,
                isReading: true)
        }
        let kept = retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let matching = matches(kept, query: snapshot.query, locale: locale)
        // Recordings have no words to match, so a search leaves them out.
        let waiting = snapshot.query.isEmpty ? snapshot.recordings : []
        let days = group(
            matching, recordings: waiting, snapshot: snapshot, calendar: calendar, locale: locale)
        let today = todayAndEarlier(in: kept, now: snapshot.now, calendar: calendar).today

        return HistoryPresentation(
            days: days,
            emptyState: days.isEmpty
                ? emptyState(for: snapshot) : nil,
            retentionNotice: notice(for: snapshot),
            showsSearch: !kept.isEmpty,
            tiles: kept.isEmpty
                ? []
                : HomeDashboard.tiles(
                    kept: kept, today: today, now: snapshot.now, calendar: calendar, locale: locale)
        )
    }

    // MARK: - Retention

    /// Drops what is promised deleted, via ``DictationRecord/survives(days:now:)`` so page and store agree.
    static func retained(_ entries: [HistoryEntry], days: Int, now: Date) -> [HistoryEntry] {
        entries.filter { $0.survives(days: days, now: now) }
    }

    /// What retention promises deleted but the snapshot still carries; the only evidence of a deletion.
    static func dropped(_ entries: [HistoryEntry], days: Int, now: Date) -> [HistoryEntry] {
        entries.filter { !$0.survives(days: days, now: now) }
    }

    /// The privacy screen's promise, cut to what fits under a list.
    static func notice(for snapshot: HistorySnapshot) -> HistoryRetentionNotice {
        let text = snapshot.settings.transcriptRetentionDays
        let kept =
            SettingsRetention.isAlways(days: text)
            ? "Kept on this Mac until you delete it."
            : "Kept on this Mac for \(MainFormatting.count(text, "day", "days")), then deleted."
        let sentence =
            snapshot.keepsRecordings
            ? "\(kept) A recording stays only until its words land." : "\(kept) Recordings are never saved."

        return HistoryRetentionNotice(
            sentence: sentence,
            link: MainAction(title: "change in Settings › Privacy", intent: .go(.settings(.privacy))),
            phrase: SettingsRetention.isAlways(days: text)
                ? "kept until you delete it" : "kept for \(MainFormatting.count(text, "day", "days"))"
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
        _ entries: [HistoryEntry], recordings: [KeptRecording] = [], snapshot: HistorySnapshot,
        calendar: Calendar, locale: Locale
    ) -> [HistoryDay] {
        var grouped: [(day: Date, rows: [HistoryRow], words: Int, dictations: Int)] = []

        for item in interleaved(entries, recordings) {
            let day = calendar.startOfDay(for: item.when)
            let words = item.entry.map { MainFormatting.words(in: $0.text) } ?? 0
            let row = row(for: item, words: words, snapshot: snapshot, calendar: calendar, locale: locale)
            if let index = grouped.firstIndex(where: { $0.day == day }) {
                grouped[index].rows.append(row)
                grouped[index].words += words
                grouped[index].dictations += 1
            } else {
                grouped.append((day, [row], words, 1))
            }
        }

        return grouped.map { day, rows, words, dictations in
            HistoryDay(
                title: title(for: day, snapshot: snapshot, calendar: calendar, locale: locale),
                rows: rows,
                summary: """
                    \(MainFormatting.count(dictations, "dictation", "dictations")) · \
                    \(words == 1 ? "1 word" : "\(words.formatted(.number.locale(locale))) words")
                    """)
        }
    }

    /// A dictation or a recording, whichever a row is drawn from.
    enum Item {
        case entry(HistoryEntry)
        case recording(KeptRecording)

        /// When it happened.
        var when: Date {
            switch self {
            case .entry(let entry): entry.when
            case .recording(let recording): recording.when
            }
        }

        /// The dictation, when this is one.
        var entry: HistoryEntry? {
            if case .entry(let entry) = self { entry } else { nil }
        }
    }

    /// The store's order kept, each recording placed before the first dictation older than it.
    static func interleaved(_ entries: [HistoryEntry], _ recordings: [KeptRecording]) -> [Item] {
        var items = entries.map(Item.entry)
        for recording in recordings {
            let index = items.firstIndex { $0.entry != nil && $0.when < recording.when } ?? items.count
            items.insert(.recording(recording), at: index)
        }
        return items
    }

    /// One dictation or recording as a row.
    static func row(
        for item: Item, words: Int, snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> HistoryRow {
        switch item {
        case .entry(let entry):
            row(
                for: entry, words: words, relativeTo: snapshot.now, calendar: calendar,
                locale: locale, canKeepAsClip: snapshot.canKeepAsClip)
        case .recording(let recording):
            row(for: recording, snapshot: snapshot, calendar: calendar, locale: locale)
        }
    }

    /// "Today", "Yesterday", or the date, for a day's heading.
    static func title(
        for day: Date, snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> String {
        if let near = MainFormatting.todayOrYesterday(day, now: snapshot.now, calendar: calendar) {
            return near
        }
        let dateStyle = Date.FormatStyle.dateTime.day().month(.wide).locale(locale)
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: snapshot.now)
        return day.formatted(sameYear ? dateStyle : dateStyle.year())
    }

    /// Only an arrival that may have missed the field is labelled; a delivered row stays quiet.
    static func arrivalLabel(for arrival: RecordedArrival?) -> String? {
        switch arrival {
        case .notInserted: "Not inserted"
        case .unconfirmed: "Unconfirmed"
        case .confirmed, .notReported, nil: nil
        }
    }

    /// One dictation as a row, with the buttons it offers when pointed at.
    static func row(
        for entry: HistoryEntry, words: Int? = nil, relativeTo now: Date,
        calendar: Calendar = .autoupdatingCurrent, locale: Locale, canKeepAsClip: Bool = false
    ) -> HistoryRow {
        let (tag, tone) = HomeDashboard.outcome(of: entry.changes)
        return HistoryRow(
            id: entry.id,
            application: application(for: entry),
            when: when(entry.when, relativeTo: now, locale: locale),
            text: DictationTextPresentation(entry.text).displayText,
            time: HomeDashboard.time(entry.when, calendar: calendar, locale: locale),
            length: length(of: entry, words: words),
            // Only a change is worth a tag; "as dictated" is what every quiet row already says.
            tag: tone == .changed ? tag : nil,
            isFlagged: entry.isFlagged,
            arrival: arrivalLabel(for: entry.arrival),
            actions: [
                MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(entry.text)),
                // From the main window Uttrflow is in front, so the button says what it actually does. See `Docs/insertion.md`.
                MainAction(
                    title: "Copy to Paste Elsewhere", symbolName: "arrow.turn.down.left",
                    intent: .copy(entry.text)),
                MainAction(
                    title: entry.isFlagged ? "Unflag" : "Flag",
                    symbolName: entry.isFlagged ? "flag.fill" : "flag",
                    intent: .flagDictation(entry.id)),
            ],
            more: flagReasons(for: entry.id)
                + [
                    MainAction(
                        title: "Report This Dictation", symbolName: "doc.text.magnifyingglass",
                        intent: .reportDictation(entry.id))
                ]
                + (canKeepAsClip
                    ? [
                        MainAction(
                            title: "Keep as clip", symbolName: "doc.on.clipboard",
                            intent: .keepDictationAsClip(entry.id))
                    ]
                    : []) + [.delete(.forgetDictation(entry.id))],
            fixes: fixes(for: entry.text),
            whatChanged: (entry.changes?.corrections ?? []).map(phrase(for:))
                + (entry.whatChanged ?? []).map(phrase(for:)))
    }

    /// One dictionary correction as one phrase naming the signal that decided it, in the order the stages ran.
    static func phrase(for correction: RecordedCorrection) -> String {
        "Dictionary: rewrote “\(correction.heard)” as “\(correction.wrote)” (\(correction.reason.title))"
            + (correction.isUndone ? ", undone" : "")
    }

    /// One ledgered change as one phrase, in the step names and verbs Diagnostics already uses.
    static func phrase(for line: WhatChangedLine) -> String {
        let step = CleaningSteps.name(of: line.pass)
        let did =
            switch (line.kind, line.location) {
            case (.removed, .word(let word)?): "removed before “\(word)”"
            case (.removed, .end?): "removed at the end"
            case (.replaced, .word(let word)?): "rewrote as “\(word)”"
            case (.inserted, .word(let word)?): "added “\(word)”"
            // Unlocated, or a rewrite or addition pointing past the text: the step and verb, never a guessed word.
            case (.removed, _): "removed"
            case (.replaced, _): "rewrote"
            case (.inserted, _): "added"
            }
        return "\(step): \(did)"
    }

    /// One flag per error class of `Docs/accuracy-targets.md`, so a flag can say what was wrong.
    static func flagReasons(for id: UUID) -> [MainAction] {
        FlagReason.allCases.map { reason in
            let title =
                switch reason {
                case .meaningChanging: "Flag: Wrong Words"
                case .formatting: "Flag: Formatting"
                case .cosmetic: "Flag: Spacing"
                }
            return MainAction(title: title, symbolName: "flag", intent: .flagDictationAs(id, reason))
        }
    }

    /// One action per distinct word in the text, in text order, for teaching the dictionary its right spelling.
    static func fixes(for text: String) -> [MainAction] {
        var seen: Set<String> = []
        return text.split(whereSeparator: \.isWhitespace).compactMap { token in
            let word = String(token).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            guard word.contains(where: \.isLetter), seen.insert(word).inserted else { return nil }
            return MainAction(
                title: "Fix “\(word)”", symbolName: "character.cursor.ibeam", intent: .fixWord(word))
        }
    }

    /// A recording whose words were lost, as a row with the way to hear it and to retry it.
    static func row(
        for recording: KeptRecording, snapshot: HistorySnapshot, calendar: Calendar, locale: Locale
    ) -> HistoryRow {
        let retrying = snapshot.retrying == recording.id
        let playing = snapshot.playing == recording.id
        return HistoryRow(
            id: recording.id,
            application: nil,
            when: when(recording.when, relativeTo: snapshot.now, locale: locale),
            text: "",
            time: HomeDashboard.time(recording.when, calendar: calendar, locale: locale),
            length: clock(recording.duration),
            more: retrying ? [] : [.delete(.forgetRecording(recording.id))],
            recording: HistoryRecording(
                duration: clock(recording.duration),
                message: retrying ? "Transcribing…" : "Couldn’t turn this into text",
                play: MainAction(
                    title: playing ? "Stop" : "Play Recording",
                    symbolName: playing ? "stop.fill" : "play.fill",
                    intent: .playRecording(recording.id)),
                isPlaying: playing,
                retry: retrying
                    ? nil
                    : MainAction(
                        title: "Retry", symbolName: "arrow.clockwise",
                        intent: .retryRecording(recording.id))))
    }

    /// "0:09 · 23 words"; the words stand alone when nothing timed the dictation.
    static func length(of entry: HistoryEntry, words counted: Int? = nil) -> String {
        let words = MainFormatting.count(
            counted ?? MainFormatting.words(in: entry.text), "word", "words")
        guard let spoken = entry.spokenFor else { return words }
        let duration = clock(spoken)
        return duration == "—" ? words : "\(duration) · \(words)"
    }

    /// A duration on a clock, minutes and two-digit seconds: "0:06", "12:40".
    static func clock(_ duration: Duration) -> String {
        guard let measured = MainFormatting.roundedInteger(duration.inSeconds) else { return "—" }
        let seconds = max(0, measured)
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }

    /// "2 minutes ago" against the snapshot's clock, not the real one, so the row agrees with retention.
    static func when(_ date: Date, relativeTo now: Date, locale: Locale) -> String {
        relativeFormatters.withLock { formatters in
            let formatter = formatters[locale.identifier] ?? RelativeDateTimeFormatter()
            if formatters[locale.identifier] == nil {
                formatter.locale = locale
                formatter.unitsStyle = .full
                formatters[locale.identifier] = formatter
            }
            return formatter.localizedString(for: date, relativeTo: now)
        }
    }

    /// One formatter per locale, used under the lock because a formatter is not safe across threads.
    private static let relativeFormatters = Mutex<[String: RelativeDateTimeFormatter]>([:])

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
                title: "Nothing dictated yet",
                message: "Every dictation lands here, kept on this Mac.",
                action: .tryIt)
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

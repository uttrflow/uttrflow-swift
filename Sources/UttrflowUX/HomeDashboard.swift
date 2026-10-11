// The home page's hero, stat tiles and recent-activity rail, and the rules that fill them.
public import Foundation
internal import UttrflowCore
internal import UttrflowHistory

/// The part of the day, which picks the greeting and the picture beside the hero.
public enum HomeMood: String, Sendable, Equatable, CaseIterable {
    case earlyMorning
    case morning
    case afternoon
    case evening
    case night
    case lateNight

    /// The mood for an hour of the day from 0 to 23; anything outside 5 to 22 is late at night.
    public static func at(hour: Int) -> HomeMood {
        switch hour {
        case 5..<8: .earlyMorning
        case 8..<12: .morning
        case 12..<17: .afternoon
        case 17..<20: .evening
        case 20..<23: .night
        default: .lateNight
        }
    }

    /// The hours at which home changes: midnight for the date line, then each hour the mood turns.
    public static let boundaryHours: [Int] = [0] + (1..<24).filter { at(hour: $0) != at(hour: $0 - 1) }

    /// The first moment after `date` at which the mood or the date changes, skipping hours a clock change removes.
    public static func nextBoundary(after date: Date, calendar: Calendar) -> Date {
        let candidates = boundaryHours.compactMap {
            calendar.nextDate(
                after: date, matching: DateComponents(hour: $0, minute: 0, second: 0),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        // An hour later is the safe answer if a calendar ever finds none of them.
        return candidates.min() ?? date.addingTimeInterval(3600)
    }

    /// The greeting's opening words.
    public var salutation: String {
        switch self {
        case .earlyMorning, .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening, .night: "Good evening"
        case .lateNight: "Working late"
        }
    }

    /// The picture's file name among the app's resources, without its extension.
    public var imageName: String {
        switch self {
        case .earlyMorning: "panda-early-morning"
        case .morning: "panda-morning"
        case .afternoon: "panda-afternoon"
        case .evening: "panda-evening"
        case .night: "panda-night"
        case .lateNight: "panda-late-night"
        }
    }
}

/// One of the three things Uttrflow does, named under the hero's headline in its own accent.
public enum HomeFeature: String, Sendable, Equatable, CaseIterable, Identifiable {
    case dictation
    case suggestions
    case clipboard

    /// The case, which is unique.
    public var id: String { rawValue }

    /// The feature's name.
    public var title: String {
        switch self {
        case .dictation: "Dictation"
        case .suggestions: "AI suggestions"
        case .clipboard: "Clipboard"
        }
    }

    /// Whether the feature name carries a beta badge.
    public var isBeta: Bool { self != .dictation }
}

/// The card across the top of home: the headline, the three features and the way to start talking.
public struct HomeHero: Sendable, Equatable {
    /// The plain start of the headline.
    public let lead: String
    /// The end of the headline, drawn in the accent gradient.
    public let emphasis: String
    /// The features named under the headline, in order.
    public let features: [HomeFeature]
    /// Starts a dictation, or stops the one running.
    public let start: MainAction
    /// Whether a dictation can start now; false while a permission or the speech model is missing.
    public let canStart: Bool
    /// The speech model's state in place of the waveform; absent once it can transcribe.
    public let modelStatus: HomeModelStatus?

    /// Builds the hero from its parts; the waveform shows unless a model status is given.
    public init(
        lead: String, emphasis: String, features: [HomeFeature], start: MainAction, canStart: Bool,
        modelStatus: HomeModelStatus? = nil
    ) {
        self.lead = lead
        self.emphasis = emphasis
        self.features = features
        self.start = start
        self.canStart = canStart
        self.modelStatus = modelStatus
    }
}

/// Which figure a stat tile shows; the view picks its icon and accent from this.
public enum HomeStatKind: String, Sendable, Equatable, CaseIterable {
    case wordsToday
    case streak
    case pace
    case leftAsDictated
}

/// One stat tile: a figure, what it counts, and how far its ring is filled.
public struct HomeStatTile: Sendable, Equatable, Identifiable {
    /// Which figure this is.
    public let kind: HomeStatKind
    /// The figure, already formatted, or a dash when nothing has been measured.
    public let value: String
    /// What it counts.
    public let label: String
    /// How full the ring is, from 0 to 1.
    public let progress: Double
    /// What VoiceOver reads for the tile.
    public let accessibilityLabel: String

    /// The kind, which is unique on the page.
    public var id: HomeStatKind { kind }

    /// Builds a tile; the progress is clamped to between 0 and 1.
    public init(
        kind: HomeStatKind, value: String, label: String, progress: Double, accessibilityLabel: String
    ) {
        self.kind = kind
        self.value = value
        self.label = label
        self.progress = min(max(progress, 0), 1)
        self.accessibilityLabel = accessibilityLabel
    }
}

/// What the clean-up did to a dictation, which colours its dot and its tag.
public enum HomeActivityTone: String, Sendable, Equatable, CaseIterable {
    /// Measured, and every word kept as said.
    case asDictated
    /// Measured, and at least one word changed or one snippet expanded.
    case changed
    /// Never measured, so nothing is claimed about it.
    case unmeasured
}

/// One dictation on the recent-activity rail.
public struct HomeActivityRow: Sendable, Equatable, Identifiable {
    /// The history entry this row shows.
    public let id: UUID
    /// The time it happened, as the page writes it.
    public let time: String
    /// What was said.
    public let text: String
    /// The app it went into, when known.
    public let application: HistoryApplication?
    /// "23 words".
    public let words: String
    /// "As dictated" or "2 changes"; absent when the dictation was never measured.
    public let tag: String?
    /// What the clean-up did, for the dot and the tag's colour.
    public let tone: HomeActivityTone
    /// The View button.
    public let view: MainAction
    /// The ⋯ menu, in order.
    public let more: [MainAction]

    /// Builds a row from its parts.
    public init(
        id: UUID, time: String, text: String, application: HistoryApplication?, words: String,
        tag: String?, tone: HomeActivityTone, view: MainAction, more: [MainAction]
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.application = application
        self.words = words
        self.tag = tag
        self.tone = tone
        self.view = view
        self.more = more
    }

    /// The line under the text: the app, the word count and the tag, whichever are known.
    public var details: [String] {
        [application?.name, words, tag].compactMap(\.self)
    }
}

/// The rules behind the hero, the tiles and the rail, kept apart from the rest of home.
public enum HomeDashboard {
    /// How many dictations the rail shows before sending the reader to History.
    public static let activityShown = 3
    /// The words in a day at which the words ring is full.
    public static let dailyWordGoal = 1_000
    /// The days in a row at which the streak ring is full.
    public static let streakGoal = 7
    /// The speaking pace at which the pace ring is full, an ordinary conversational rate.
    public static let paceGoal = 150

    /// The search field in the top bar.
    static let search = MainAction(
        title: "Search your words…", symbolName: "magnifyingglass", intent: .search)

    /// Home before the first dictation: the shortcut, how to use it, and a dictation to start now.
    static func emptyState(activation: HotkeyActivation, shortcuts: ShortcutSet = .default) -> MainEmptyState
    {
        MainEmptyState(
            symbolName: "mic", title: "Nothing dictated yet",
            message: !shortcuts.isBound(.dictate)
                ? ""
                : activation == .holdToTalk
                    ? "Hold the shortcut anywhere and talk." : "Press the shortcut anywhere and talk.",
            action: .tryIt)
    }

    /// The hero; `canStart` is false while anything stops a dictation starting.
    static func hero(canStart: Bool, modelStatus: HomeModelStatus? = nil) -> HomeHero {
        HomeHero(
            lead: "Your voice,", emphasis: "finished for you.", features: HomeFeature.allCases,
            start: MainAction(title: "Start speaking", symbolName: "mic", intent: .dictate),
            canStart: canStart, modelStatus: modelStatus)
    }

    /// "Sunday 15 June", in the reader's region and the calendar's time zone.
    static func dateLine(_ now: Date, calendar: Calendar, locale: Locale) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide)
        return now.formatted(style)
    }

    // MARK: - Tiles

    /// The four tiles: today's words, the streak, the pace and the share left as dictated.
    static func tiles(
        kept: [HistoryEntry], today: [HistoryEntry], now: Date, calendar: Calendar, locale: Locale
    ) -> [HomeStatTile] {
        let words = today.totalWords
        let days =
            DictationPresenter.currentStreak(
                in: kept, dropped: [], now: now, calendar: calendar)?.days ?? 0
        let pace = DictationPresenter.pace(of: kept)
        let share = DictationPresenter.accuracy(of: kept)
        return [
            tile(
                .wordsToday, value: words.formatted(.number.locale(locale)), label: "words today",
                progress: Double(words) / Double(dailyWordGoal)),
            tile(
                .streak, value: MainFormatting.count(days, "day", "days"), label: "streak",
                progress: Double(days) / Double(streakGoal)),
            tile(
                .pace, value: pace.map { "\($0)" }, label: "words / min",
                progress: Double(pace ?? 0) / Double(paceGoal)),
            tile(
                .leftAsDictated, value: share.map { percentage($0, locale: locale) },
                label: "left as dictated", progress: share ?? 0),
        ]
    }

    /// One tile, with a dash and a spoken "not measured yet" when there is no figure.
    static func tile(
        _ kind: HomeStatKind, value: String?, label: String, progress: Double
    )
        -> HomeStatTile
    {
        HomeStatTile(
            kind: kind, value: value ?? "—", label: label, progress: progress,
            accessibilityLabel: value.map { "\($0) \(label)" } ?? "\(label), not measured yet")
    }

    /// A share as a whole percentage, rounded down so nothing short of every word reads 100%.
    static func percentage(_ fraction: Double, locale: Locale) -> String {
        let whole = (fraction * 100).rounded(.down) / 100
        return whole.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Current days in a row with a dictation, ending today or yesterday.
    static func streak(in entries: [HistoryEntry], now: Date, calendar: Calendar) -> Int {
        DictationPresenter.currentStreak(
            in: entries, dropped: [], now: now, calendar: calendar)?.days ?? 0
    }

    // MARK: - The rail

    /// The rail's time on the 24-hour clock, "09:05", so every stamp fits the gutter the same way.
    static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let style = Date.VerbatimFormatStyle(
            format:
                "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: locale, timeZone: calendar.timeZone, calendar: calendar)
        return date.formatted(style)
    }

    /// One dictation as a row on the rail.
    static func activity(
        for entry: HistoryEntry, calendar: Calendar, locale: Locale, secretPhrases: [String] = []
    )
        -> HomeActivityRow
    {
        let (tag, tone) = outcome(of: entry.changes)
        return HomeActivityRow(
            id: entry.id,
            time: time(entry.when, calendar: calendar, locale: locale),
            text: DictationTextPresentation(entry.text, secretPhrases: secretPhrases).displayText,
            application: HistoryPresenter.application(for: entry),
            words: MainFormatting.count(MainFormatting.words(in: entry.text), "word", "words"),
            tag: tag, tone: tone,
            view: MainAction(title: "View", intent: .show(.history)),
            more: [
                MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(entry.text)),
                MainAction(
                    title: entry.isFlagged ? "Unflag" : "Flag",
                    symbolName: entry.isFlagged ? "flag.fill" : "flag",
                    intent: .flagDictation(entry.id)),
                .delete(.forgetDictation(entry.id)),
            ])
    }

    /// The tag and tone for what the clean-up did; nothing is claimed about an unmeasured dictation.
    static func outcome(of changes: RecordedChanges?) -> (tag: String?, tone: HomeActivityTone) {
        guard let changes else { return (nil, .unmeasured) }
        let count = changes.corrections.count(where: { !$0.isUndone }) + changes.snippets.count
        guard count > 0 else { return ("As dictated", .asDictated) }
        return (MainFormatting.count(count, "change", "changes"), .changed)
    }
}

extension MainAction {
    /// Starts a dictation from an empty page, the same toggle as the hero's Start speaking.
    static let tryIt = MainAction(title: "Try it now", symbolName: "plus", intent: .dictate)
}

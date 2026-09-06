// The Insights page: the daily chart, the average line, pace and accuracy, and where the words went.
public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// One day's bar in the words-dictated chart.
public struct InsightsDay: Sendable, Equatable, Identifiable {
    /// The number on the axis: "23".
    public let label: String
    /// Words dictated that day.
    public let words: Int
    /// Of the tallest day in the window, so the view scales nothing itself.
    public let fraction: Double
    /// A day with no dictation, drawn flat and grey rather than omitted, since a missing bar is a mystery.
    public let isSilent: Bool
    /// Whether this bar is today's.
    public let isToday: Bool

    /// The label, which is unique within the window.
    public var id: String { label }

    /// Builds a bar; the fraction is clamped to 0…1.
    public init(label: String, words: Int, fraction: Double, isSilent: Bool, isToday: Bool) {
        self.label = label
        self.words = words
        self.fraction = min(max(fraction, 0), 1)
        self.isSilent = isSilent
        self.isToday = isToday
    }
}

/// One app, and the share of dictations that went into it.
public struct InsightsPlace: Sendable, Equatable, Identifiable {
    /// The app.
    public let application: HistoryApplication
    /// Its share of dictations, 0…1.
    public let share: Double
    /// "41%".
    public let percentage: String
    /// "1,249 words": how much of the dictating there was, where the share says how it divides.
    public let words: String

    /// The app's name, which is unique in the list.
    public var id: String { application.name }

    /// Builds a place; the share is clamped to 0…1.
    public init(
        application: HistoryApplication, share: Double, percentage: String, words: String
    ) {
        self.application = application
        self.share = min(max(share, 0), 1)
        self.percentage = percentage
        self.words = words
    }
}

/// The line across the chart that turns each bar into a statement, at the cost of one dashed line.
public struct InsightsAverage: Sendable, Equatable {
    /// The mean, rounded.
    public let words: Int
    /// Where the line sits, on the same scale as ``InsightsDay/fraction``, so the view scales nothing.
    public let fraction: Double
    /// "388 a day".
    public let label: String

    /// Builds the line; the fraction is clamped to 0…1.
    public init(words: Int, fraction: Double, label: String) {
        self.words = words
        self.fraction = min(max(fraction, 0), 1)
        self.label = label
    }
}

/// Everything the insights page is drawn from.
public struct InsightsSnapshot: Sendable, Equatable {
    /// Newest first, before retention is applied. The only thing this page now reads.
    public let entries: [HistoryEntry]
    /// The user's settings, for the retention window.
    public let settings: Settings
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; entries and settings default to empty.
    public init(
        entries: [HistoryEntry] = [],
        settings: Settings = .default,
        now: Date
    ) {
        self.entries = entries
        self.settings = settings
        self.now = now
    }
}

/// What the insights page shows.
public struct InsightsPresentation: Sendable, Equatable {
    /// The title, caption and window label across the top.
    public let chrome: MainPageChrome
    /// The chart along the top. Empty exactly when ``emptyState`` is set.
    public let days: [InsightsDay]
    /// The mean across the charted days. Absent when there is nothing to average.
    public let average: InsightsAverage?
    /// "12,410 words · 10–23 August".
    public let chartCaption: String
    /// The heading over the chart.
    public let chartTitle: String
    /// Words per minute, and accuracy where it can be measured; two tiles or one, never a placeholder.
    public let figures: [MainStatistic]
    /// The pace, day by day, for the sparkline. Empty when nothing was timed.
    public let paceTrend: [Int]
    /// The apps dictated into, busiest first.
    public let places: [InsightsPlace]
    /// Shown until there is a week to chart.
    public let emptyState: MainEmptyState?
    /// The line under the page while there is a chart.
    public let footnote: String?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        days: [InsightsDay],
        average: InsightsAverage?,
        chartCaption: String,
        chartTitle: String,
        figures: [MainStatistic],
        paceTrend: [Int],
        places: [InsightsPlace],
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.days = days
        self.average = average
        self.chartCaption = chartCaption
        self.chartTitle = chartTitle
        self.figures = figures
        self.paceTrend = paceTrend
        self.places = places
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns a fortnight of dictations into what can honestly be said; no "time saved" or language card.
public enum InsightsPresenter {
    /// A week, because a baseline drawn from three days is noise wearing a number's clothes.
    public static let daysBeforeCharting = 7

    /// Draws the Insights page from a snapshot.
    public static func page(
        for snapshot: InsightsSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> InsightsPresentation {
        let kept = HistoryPresenter.retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let window = snapshot.settings.transcriptRetentionDays
        let spoken = daysSpokenOn(kept, calendar: calendar)
        let ready = spoken.count >= daysBeforeCharting
        let days = ready ? bars(for: kept, snapshot: snapshot, calendar: calendar, locale: locale) : []

        return InsightsPresentation(
            chrome: MainPageChrome(
                title: "Insights",
                caption: "Where the words went, and how fast they arrived.",
                // A label, not a choice: the window is the retention setting, not this page's to widen.
                scope: MainScope(
                    title: "Last \(MainFormatting.count(window, "day", "days"))")),
            days: days,
            average: ready ? average(across: days, locale: locale) : nil,
            chartCaption: ready
                ? caption(
                    for: kept, days: days, snapshot: snapshot, calendar: calendar, locale: locale)
                : "",
            chartTitle: "Words dictated",
            figures: ready ? figures(for: kept, locale: locale) : [],
            paceTrend: ready ? paceTrend(for: kept, calendar: calendar) : [],
            places: ready ? places(for: kept, locale: locale) : [],
            emptyState: ready
                ? nil
                : emptyState(
                    for: kept, daysSpokenOn: spoken.count, now: snapshot.now, calendar: calendar,
                    locale: locale),
            footnote: ready
                ? """
                Measured on this Mac over the last \(MainFormatting.count(window, "day", "days")). \
                Never sent anywhere. There is no “time saved” figure: it would need a guess at \
                how fast you type, and Uttrflow has never watched you type.
                """
                : nil)
    }

    // MARK: - What there is to chart

    /// The distinct days the user said something on; fifty dictations in one afternoon is one afternoon.
    static func daysSpokenOn(_ entries: [HistoryEntry], calendar: Calendar) -> Set<Date> {
        Set(entries.map { calendar.startOfDay(for: $0.when) })
    }

    /// One bar per day of the window, oldest first, silent days included.
    static func bars(
        for entries: [HistoryEntry], snapshot: InsightsSnapshot, calendar: Calendar, locale: Locale
    ) -> [InsightsDay] {
        let today = calendar.startOfDay(for: snapshot.now)
        var totals: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.when)
            totals[day, default: 0] += MainFormatting.words(in: entry.text)
        }

        let span = (0..<snapshot.settings.transcriptRetentionDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        // A floor of one keeps the division safe without a branch for a window this path never asks for.
        let peak = totals.values.reduce(1, max)

        return span.map { day in
            let words = totals[day] ?? 0
            return InsightsDay(
                label: day.formatted(.dateTime.day().locale(locale)),
                words: words,
                fraction: Double(words) / Double(peak),
                isSilent: words == 0,
                isToday: day == today)
        }
    }

    /// "12,410 words · 10–23 August".
    static func caption(
        for entries: [HistoryEntry], days: [InsightsDay], snapshot: InsightsSnapshot,
        calendar: Calendar, locale: Locale
    ) -> String {
        let total = MainFormatting.count(entries.totalWords, "word", "words")
        // A window with no first day is a window of nothing, so the caption is then the total on its own.
        let range = calendar.date(byAdding: .day, value: -(days.count - 1), to: snapshot.now)
            .map { first in
                let from = first.formatted(.dateTime.day().locale(locale))
                let to = snapshot.now.formatted(.dateTime.day().month(.wide).locale(locale))
                return "\(from)–\(to)"
            }
        return [total, range].compactMap(\.self).joined(separator: " · ")
    }

    // MARK: - Figures

    /// Pace and accuracy across the window, each only where measured.
    static func figures(for entries: [HistoryEntry], locale: Locale) -> [MainStatistic] {
        var figures: [MainStatistic] = []

        if let pace = DictationPresenter.pace(of: entries) {
            figures.append(
                MainStatistic(
                    value: "\(pace)",
                    caption: "Words per minute",
                    comment: "Days you did not dictate are skipped."))
        }

        if let accuracy = DictationPresenter.accuracy(of: entries) {
            figures.append(
                MainStatistic(
                    value: MainFormatting.percentage(accuracy, locale: locale),
                    caption: "Accuracy",
                    // The Dictation page's wording, so the two cannot drift apart.
                    comment: DictationPresenter.accuracyCaption,
                    meters: [MainMeter(label: "Now", fraction: accuracy)]))
        }

        return figures
    }

    /// The pace on each day that had one, oldest first; untimed days are left out, not plotted as zero.
    static func paceTrend(for entries: [HistoryEntry], calendar: Calendar) -> [Int] {
        var byDay: [Date: [HistoryEntry]] = [:]
        for entry in entries {
            byDay[calendar.startOfDay(for: entry.when), default: []].append(entry)
        }
        return byDay.sorted { $0.key < $1.key }.compactMap {
            DictationPresenter.pace(of: $0.value)
        }
    }

    // MARK: - Where the words went

    /// The mean words a day across the charted window, silent days included.
    static func average(across days: [InsightsDay], locale: Locale) -> InsightsAverage? {
        // The tallest day is `fraction == 1`, so the line's height is the mean measured against that day.
        guard let tallest = days.map(\.words).max(), tallest > 0 else { return nil }
        let mean = Double(days.reduce(0) { $0 + $1.words }) / Double(days.count)
        let rounded = Int(mean.rounded())
        return InsightsAverage(
            words: rounded,
            fraction: mean / Double(tallest),
            label: "\(rounded.formatted(.number.locale(locale))) a day")
    }

    /// The apps the user dictates into, busiest first; unknown destinations leave the total too.
    static func places(for entries: [HistoryEntry], locale: Locale) -> [InsightsPlace] {
        // The application is kept with its tally so it is resolved once and cannot fail on the way out.
        var counts: [String: (application: HistoryApplication, dictations: Int, words: Int)] = [:]
        for entry in entries {
            guard
                let application = HistoryPresenter.application(for: entry)
            else { continue }
            counts[application.name, default: (application, 0, 0)].dictations += 1
            counts[application.name]?.words += MainFormatting.words(in: entry.text)
        }
        let total = counts.values.reduce(0) { $0 + $1.dictations }
        guard total > 0 else { return [] }

        return counts.values.sorted {
            ($0.dictations, $1.application.name)
                > ($1.dictations, $0.application.name)
        }.map { application, dictations, words in
            let share = Double(dictations) / Double(total)
            return InsightsPlace(
                application: application,
                share: share,
                percentage: share.formatted(.percent.precision(.fractionLength(0)).locale(locale)),
                words: "\(MainFormatting.count(words, "word", "words"))")
        }
    }

    // MARK: - Not yet

    /// Waiting is not empty: says how long is left and gives the two figures already true.
    static func emptyState(
        for entries: [HistoryEntry], daysSpokenOn spoken: Int, now: Date, calendar: Calendar,
        locale: Locale
    ) -> MainEmptyState {
        MainEmptyState(
            symbolName: "chart.bar",
            title: "Not enough to chart yet",
            message: """
                Insights compare this week against your own baseline, so they wait until there \
                are \(daysBeforeCharting) days to compare. Uttrflow has \(spoken).
                """,
            chips: entries.isEmpty
                ? []
                : [
                    MainStatistic(
                        value: entries.count.formatted(.number.locale(locale)),
                        caption: "dictations so far"),
                    MainStatistic(
                        value: entries.totalWords.formatted(.number.locale(locale)),
                        caption: "words so far"),
                ],
            progress: MainProgress(
                fraction: Double(spoken) / Double(daysBeforeCharting),
                leading: "\(spoken) of \(daysBeforeCharting) days",
                trailing: remaining(spoken: spoken, now: now, calendar: calendar, locale: locale)),
            footnote: """
                The figures Uttrflow can honestly give this early are given. The rest waits \
                rather than guessing.
                """)
    }

    /// "Charts appear on Tuesday", assuming the remaining days are spoken on, counted in flat days.
    static func remaining(spoken: Int, now: Date, calendar: Calendar, locale: Locale) -> String {
        let left = max(daysBeforeCharting - spoken, 1)
        let day = now.addingTimeInterval(Double(left) * 86_400)
        return "Charts appear on \(day.formatted(.dateTime.weekday(.wide).locale(locale)))"
    }
}

public import Foundation
public import UttrflowCore

/// What clicking something in the main window means.
///
/// Named rather than carried as a closure: a page has to be comparable in a test, and a
/// closure is not. It also keeps the single place that knows *how* to open System
/// Settings or reach the pasteboard in the app, where the platform already lives.
///
/// The identifiers are deliberately not interchangeable. `forgetWord` and
/// `forgetSnippet` could have been one case taking an identifier, and then the one
/// mis-wired call site would delete the wrong thing without failing to compile.
public enum MainIntent: Sendable, Equatable {
    /// Something only macOS can grant. The app already knows how to ask — this is the
    /// same vocabulary a failure uses, so a permission is repaired one way, not two.
    case recover(RecoveryAction)
    /// Somewhere else in the app.
    case go(Destination)
    /// Another page of this window.
    ///
    /// Separate from ``go(_:)`` only because ``MainTab`` cannot yet name every page.
    /// See ``MainTab``: when it can, this case folds into `go(.main(_:))`.
    case show(MainTab)
    case copy(String)
    /// Put this text back into whatever the user is typing in.
    case insert(String)

    /// This dictation came out wrong. The honest input to teaching, and the only thing
    /// a user can say about a dictation that the app cannot work out for itself.
    case flagDictation(UUID)
    case forgetDictation(UUID)

    /// Run a kept recording through transcription again.
    case retryRecording(UUID)
    /// Delete a kept recording without ever hearing it.
    case forgetRecording(UUID)

    /// Put a changed word back to what was heard.
    case undoCorrection(UUID)

    /// Open the inline word editor. Carries nothing, because there is nothing to carry
    /// yet — the word itself arrives on ``saveWord(word:pronunciation:)``.
    case addWord
    /// Commit the inline word editor.
    ///
    /// No `replacing`, unlike ``saveSnippet(trigger:text:replacing:)``: a dictionary row
    /// offers Restore and Delete and never Edit, so this only ever adds.
    case saveWord(word: String, pronunciation: String)
    case cancelWordEdit
    case forgetWord(UUID)
    /// Trust a word that retired itself, and let it start earning its place again.
    case restoreWord(UUID)

    case addSnippet
    case editSnippet(UUID)
    case forgetSnippet(UUID)
    /// Commit the inline editor. `replacing` is the snippet being edited, or `nil` for
    /// a new one — carried here so the app never has to remember which it was.
    case saveSnippet(trigger: String, text: String, replacing: UUID?)
    case cancelSnippetEdit

    /// A setting the user changed from the main window rather than the settings window.
    ///
    /// The same ``SettingsChange`` the settings window reports, so ``SettingsEditor``
    /// stays the only thing that decides whether a change may happen — two screens
    /// offering one choice must not be two chances to apply it differently.
    case change(SettingsChange)

    case signIn
    case signOut
}

/// Something a page offers the user to click.
public struct MainAction: Sendable, Equatable, Identifiable {
    public let title: String
    /// The symbol on an icon-only button. Absent where the title is the button.
    public let symbolName: String?
    public let intent: MainIntent
    /// Whether this destroys something. Drawn in red, and never the default button.
    public let isDestructive: Bool

    public var id: String { title }

    public init(
        title: String, symbolName: String? = nil, intent: MainIntent, isDestructive: Bool = false
    ) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
        self.isDestructive = isDestructive
    }
}

/// A pane with nothing in it, or with something in the way.
///
/// First class rather than an afterthought: between them the pages can be empty for a
/// dozen different reasons, and a blank pane tells the user none of them.
public struct MainEmptyState: Sendable, Equatable {
    public let symbolName: String
    public let title: String
    /// A complete sentence saying why, and — where there is one — what to do next.
    public let message: String
    /// At most one, matching the rest of the product: a screen that offers three ways
    /// forward has not decided which one is right.
    public let action: MainAction?
    /// The few figures that are true even with nothing to list, so an empty pane is
    /// informative rather than merely blank.
    public let chips: [MainStatistic]
    /// How far off the page is from having something to show, when the answer is
    /// "wait" rather than "do something".
    public let progress: MainProgress?
    /// The small print under the whole pane.
    public let footnote: String?

    public init(
        symbolName: String,
        title: String,
        message: String,
        action: MainAction? = nil,
        chips: [MainStatistic] = [],
        progress: MainProgress? = nil,
        footnote: String? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.action = action
        self.chips = chips
        self.progress = progress
        self.footnote = footnote
    }
}

/// One figure and what it counts.
public struct MainStatistic: Sendable, Equatable, Identifiable {
    public let value: String
    public let caption: String
    /// The sentence under the figure, saying what it is measured against. Absent when
    /// the figure needs no context — and absent, rather than invented, when there is no
    /// second figure to compare it with.
    public let comment: String?
    /// The bars drawn beneath it. Empty for a plain figure.
    public let meters: [MainMeter]

    public var id: String { caption }

    public init(
        value: String, caption: String, comment: String? = nil, meters: [MainMeter] = []
    ) {
        self.value = value
        self.caption = caption
        self.comment = comment
        self.meters = meters
    }
}

extension MainAction {
    /// The trash-can button every list draws: destructive, and never the default.
    static func delete(_ intent: MainIntent) -> MainAction {
        MainAction(title: "Delete", symbolName: "trash", intent: intent, isDestructive: true)
    }
}

extension MainEmptyState {
    /// The nothing every searchable page shares: a query that matched no row.
    static func noMatches(_ message: String) -> MainEmptyState {
        MainEmptyState(symbolName: "magnifyingglass", title: "No matches", message: message)
    }
}

/// The chrome every page sits in.
public enum MainPresenter {
    public static let windowTitle = "Uttrflow"

    /// One verb per recovery, matching the sentence the failure already offered.
    ///
    /// Here rather than in each page so that the button beside a missing microphone on
    /// Dictation reads exactly as the one beside it on Diagnostics.
    public static func title(for action: RecoveryAction) -> String {
        switch action {
        case .openSystemSettings: "Open Settings"
        case .retry: "Try Again"
        case .downloadSpeechModel: "Download"
        case .pasteManually: "Paste"
        case .showRecentDictations: "Show Recent"
        case .retryFromRecording: "Retry"
        }
    }

    /// The first permission that stops the app working, in the order the journey needs
    /// them: nothing can be heard without a microphone, and nothing can be typed without
    /// Accessibility. Reporting only the first keeps the page to one thing to fix.
    ///
    /// Shared rather than owned by the Dictation page, because every page in this window
    /// is describing an app that cannot currently run and only one of them should say so.
    public static func obstruction(
        in permissions: [PermissionKind: PermissionStatus]
    ) -> MainEmptyState? {
        for kind in [PermissionKind.microphone, .accessibility] {
            guard let status = permissions[kind] else { continue }
            switch status {
            case .granted:
                continue
            case .notDetermined:
                return MainEmptyState(
                    symbolName: "hand.raised",
                    title: "\(DiagnosticsPresenter.name(for: kind)) has not been set up",
                    message: """
                        Uttrflow needs \(DiagnosticsPresenter.name(for: kind).lowercased()) access \
                        before it can work. Setting up takes a moment.
                        """,
                    action: MainAction(title: "Set Up", intent: .go(.onboarding)))
            case .denied, .restricted:
                let failure = permissionError(for: kind, status: status)
                return MainEmptyState(
                    symbolName: "exclamationmark.triangle",
                    title: "\(DiagnosticsPresenter.name(for: kind)) access is off",
                    // The sentence the failure already writes for itself, rather than a
                    // second wording of the same problem that could drift from it.
                    message: failure.userMessage,
                    action: failure.recovery.map {
                        MainAction(title: title(for: $0), intent: .recover($0))
                    })
            }
        }
        return nil
    }

    /// Restricted means a device policy, which is a different sentence and offers no
    /// action; ``PermissionError`` spells only the microphone case out, because that is
    /// the only permission macOS reports as restricted.
    static func permissionError(
        for kind: PermissionKind, status: PermissionStatus
    ) -> PermissionError {
        switch (kind, status) {
        case (.microphone, .restricted): .microphoneRestricted
        case (.microphone, _): .microphoneDenied
        case (.accessibility, _): .accessibilityNotTrusted
        }
    }
}

/// Numbers as every page writes them.
///
/// Shared so that two pages cannot disagree about what two and a half seconds looks
/// like. Locale is a parameter rather than read from the environment because a test
/// that depends on the machine's region settings is a test that fails in another country.
public enum MainFormatting {
    /// A duration in seconds, to the hundredth.
    ///
    /// Anything faster than that is reported as being faster rather than as `0.00s`,
    /// which reads as "not measured" when it means "too quick to matter".
    public static func seconds(_ duration: Duration) -> String {
        let value = duration.inSeconds
        guard value >= 0.01 else { return "under 0.01s" }
        return String(format: "%.2fs", value)
    }

    /// How long somebody talked, as a row lists it: "11s".
    ///
    /// Whole seconds, unlike ``seconds(_:)``, which measures the machine. Hundredths
    /// matter when the app is being timed and are noise when a person is.
    public static func spoken(_ duration: Duration) -> String {
        "\(max(0, Int(duration.inSeconds.rounded())))s"
    }

    public static func bytes(_ count: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        count.formatted(.byteCount(style: .file).locale(locale))
    }

    /// A fraction of one, as a percentage to one decimal place.
    public static func percentage(_ fraction: Double, locale: Locale) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    /// A count and the thing it counts, singular or plural.
    ///
    /// Written out rather than reached for from a formatter because the strings this
    /// pluralises are English-only for now, and "1 days" is the kind of detail that
    /// makes an otherwise careful product look unfinished.
    public static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    /// How many words are in a piece of dictated text.
    ///
    /// Whitespace-separated runs, which is what a person counting them would say and
    /// what every figure on Dictation and Insights is built from. One definition, so a
    /// row and a total cannot disagree about the length of the same sentence.
    /// A large count, short enough to read at a glance: 964, 12.4K, 1.2M.
    ///
    /// Rounded down rather than to nearest, so the figure never claims a word that has
    /// not been said. `12.4K` from 12,499 is a floor the user can trust; `12.5K` would be
    /// a number they never reached.
    public static func compact(_ number: Int, locale: Locale) -> String {
        switch number {
        case ..<1_000: number.formatted(.number.locale(locale))
        case ..<1_000_000: "\(tenths(number, per: 1_000, locale: locale))K"
        default: "\(tenths(number, per: 1_000_000, locale: locale))M"
        }
    }

    /// One decimal place, truncated, with the decimal separator the locale uses — and no
    /// trailing `.0`, because "12K" reads better than "12.0K".
    private static func tenths(_ number: Int, per unit: Int, locale: Locale) -> String {
        let whole = number / unit
        let tenth = (number % unit) * 10 / unit
        guard tenth > 0 else { return whole.formatted(.number.locale(locale)) }
        return (Double(whole) + Double(tenth) / 10).formatted(
            .number.locale(locale).precision(.fractionLength(1)))
    }

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The time of day a row is stamped with: "4:12 PM".
    public static func time(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// A day named the way somebody would say it out loud.
    ///
    /// "Today", "Yesterday", the weekday within the past week, and the date beyond it.
    /// ``HistoryPresenter`` deliberately keeps its own, narrower version: its headings
    /// group a list that can run for weeks, where a bare weekday is ambiguous, and this
    /// one names a single recent moment where it is the clearest thing to say.
    public static func day(
        _ date: Date, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        if let near = todayOrYesterday(date, now: now, calendar: calendar) { return near }
        if let week = calendar.date(byAdding: .day, value: -6, to: now), date > week {
            return date.formatted(.dateTime.weekday(.wide).locale(locale))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "Today" or "Yesterday" for a date that near to `now`, and `nil` for anything older.
    static func todayOrYesterday(_ date: Date, now: Date, calendar: Calendar) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return nil
    }
}

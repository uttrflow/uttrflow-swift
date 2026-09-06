// The main window's shared vocabulary: intents, actions, empty states, figures, and formatting.
public import Foundation
public import UttrflowCore

/// What clicking something in the main window means, named so a page compares in a test.
public enum MainIntent: Sendable, Equatable {
    /// Something only macOS can grant, in the same vocabulary a failure uses.
    case recover(RecoveryAction)
    /// Somewhere else in the app.
    case go(Destination)
    /// Another page of this window; separate from ``go(_:)`` only because ``MainTab`` cannot name every page.
    case show(MainTab)
    /// Put this text on the clipboard.
    case copy(String)
    /// Put this text back into whatever the user is typing in.
    case insert(String)

    /// This dictation came out wrong: the honest input to teaching.
    case flagDictation(UUID)
    /// Delete a dictation from history.
    case forgetDictation(UUID)

    /// Run a kept recording through transcription again.
    case retryRecording(UUID)
    /// Delete a kept recording without ever hearing it.
    case forgetRecording(UUID)

    /// Put a changed word back to what was heard.
    case undoCorrection(UUID)

    /// Open the inline word editor; the word arrives on ``saveWord(word:pronunciation:)``.
    case addWord
    /// Commit the inline word editor; it only ever adds, since a dictionary row never offers Edit.
    case saveWord(word: String, pronunciation: String)
    /// Close the inline word editor unchanged.
    case cancelWordEdit
    /// Delete a word from the dictionary.
    case forgetWord(UUID)
    /// Trust a word that retired itself, and let it start earning its place again.
    case restoreWord(UUID)

    /// Open the inline snippet editor empty.
    case addSnippet
    /// Open the inline snippet editor on this snippet.
    case editSnippet(UUID)
    /// Delete a snippet.
    case forgetSnippet(UUID)
    /// Commit the inline editor; `replacing` is the snippet being edited, or `nil` for a new one.
    case saveSnippet(trigger: String, text: String, replacing: UUID?)
    /// Close the inline snippet editor unchanged.
    case cancelSnippetEdit

    /// A setting changed from the main window, as the same ``SettingsChange`` the settings window reports.
    case change(SettingsChange)

    /// Open onboarding at the sign-in page.
    case signIn
    /// End the session on this Mac.
    case signOut
}

/// Something a page offers the user to click.
public struct MainAction: Sendable, Equatable, Identifiable {
    /// The words on the button.
    public let title: String
    /// The symbol on an icon-only button. Absent where the title is the button.
    public let symbolName: String?
    /// What pressing it means.
    public let intent: MainIntent
    /// Whether this destroys something. Drawn in red, and never the default button.
    public let isDestructive: Bool

    /// The title, which is unique within a page.
    public var id: String { title }

    /// Builds an action; icon-less and harmless unless said otherwise.
    public init(
        title: String, symbolName: String? = nil, intent: MainIntent, isDestructive: Bool = false
    ) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
        self.isDestructive = isDestructive
    }
}

/// A pane with nothing in it, or with something in the way, saying which of a dozen reasons applies.
public struct MainEmptyState: Sendable, Equatable {
    /// The SF Symbol above the title.
    public let symbolName: String
    /// The heading.
    public let title: String
    /// A complete sentence saying why, and — where there is one — what to do next.
    public let message: String
    /// At most one, since a screen that offers three ways forward has not decided which is right.
    public let action: MainAction?
    /// The few figures true even with nothing to list, so an empty pane is informative.
    public let chips: [MainStatistic]
    /// How far off the page is from having something to show, when the answer is "wait".
    public let progress: MainProgress?
    /// The small print under the whole pane.
    public let footnote: String?

    /// Builds an empty state; everything after the message is optional.
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
    /// The figure, already formatted.
    public let value: String
    /// What it counts.
    public let caption: String
    /// The sentence under the figure saying what it is measured against; absent rather than invented.
    public let comment: String?
    /// The bars drawn beneath it. Empty for a plain figure.
    public let meters: [MainMeter]

    /// The caption, which is unique within a page.
    public var id: String { caption }

    /// Builds a figure; plain unless given a comment or meters.
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
    /// The window's title.
    public static let windowTitle = "Uttrflow"

    /// One verb per recovery, shared so the same button reads the same on every page.
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

    /// The first permission that stops the app working, microphone before Accessibility; shared by all pages.
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
                    // The sentence the failure already writes for itself, so a second wording cannot drift.
                    message: failure.userMessage,
                    action: failure.recovery.map {
                        MainAction(title: title(for: $0), intent: .recover($0))
                    })
            }
        }
        return nil
    }

    /// Restricted means a device policy; only the microphone is ever reported restricted by macOS.
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

/// Numbers as every page writes them; the locale is a parameter so tests do not depend on the region.
public enum MainFormatting {
    /// A duration in seconds to the hundredth; anything faster is "under 0.01s" rather than `0.00s`.
    public static func seconds(_ duration: Duration) -> String {
        let value = duration.inSeconds
        guard value >= 0.01 else { return "under 0.01s" }
        return String(format: "%.2fs", value)
    }

    /// How long somebody talked, in whole seconds: "11s".
    public static func spoken(_ duration: Duration) -> String {
        "\(max(0, Int(duration.inSeconds.rounded())))s"
    }

    /// A byte count as Finder writes it.
    public static func bytes(_ count: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        count.formatted(.byteCount(style: .file).locale(locale))
    }

    /// A fraction of one, as a percentage to one decimal place.
    public static func percentage(_ fraction: Double, locale: Locale) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    /// A count and the thing it counts, singular or plural; English-only.
    public static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    /// A large count short enough to read at a glance — 964, 12.4K, 1.2M — rounded down, never up.
    public static func compact(_ number: Int, locale: Locale) -> String {
        switch number {
        case ..<1_000: number.formatted(.number.locale(locale))
        case ..<1_000_000: "\(tenths(number, per: 1_000, locale: locale))K"
        default: "\(tenths(number, per: 1_000_000, locale: locale))M"
        }
    }

    /// One decimal place, truncated, in the locale's separator, with no trailing `.0`.
    private static func tenths(_ number: Int, per unit: Int, locale: Locale) -> String {
        let whole = number / unit
        let tenth = (number % unit) * 10 / unit
        guard tenth > 0 else { return whole.formatted(.number.locale(locale)) }
        return (Double(whole) + Double(tenth) / 10).formatted(
            .number.locale(locale).precision(.fractionLength(1)))
    }

    /// How many words are in dictated text: whitespace-separated runs, the one definition every figure uses.
    public static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The time of day a row is stamped with: "4:12 PM".
    public static func time(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// A day as somebody says it: "Today", "Yesterday", a weekday within the week, else the date.
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

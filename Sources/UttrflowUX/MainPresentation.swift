// The main window's shared vocabulary: intents, actions, empty states, figures, and formatting.
public import Foundation
public import UttrflowCore
public import UttrflowHistory

/// What clicking something in the main window means, named so a page compares in a test.
public enum MainIntent: Sendable, Equatable {
    /// Something only macOS can grant, in the same vocabulary a failure uses.
    case recover(RecoveryAction)
    /// Somewhere else in the app.
    case go(AppLocation)
    /// Another page of this window; separate from ``go(_:)`` only because ``MainTab`` cannot name every page.
    case show(MainTab)
    /// Read the current page's list in the order this identifier names.
    case sort(String)
    /// Put this text on the clipboard.
    case copy(String)
    /// Put this text back into whatever the user is typing in.
    case insert(String)
    /// Start a dictation, or stop the one running; the same toggle the menu bar and the Dock use.
    case dictate
    /// Open History with the caret in its search field.
    case search
    /// Remove the locally downloaded suggestion model.
    case removeSuggestionModel

    /// This dictation came out wrong: the honest input to teaching.
    case flagDictation(UUID)
    /// This dictation came out wrong in this way: a flag that names its error class.
    case flagDictationAs(UUID, FlagReason)
    /// Open a masked, editable report of this dictation to copy or save; nothing is sent.
    case reportDictation(UUID)
    /// Open the word editor with this spelling as "Say it like", so the right spelling is typed once.
    case fixWord(String)
    /// Keep this dictation in clipboard history by choice.
    case keepDictationAsClip(UUID)
    /// Delete a dictation from history.
    case forgetDictation(UUID)

    /// Run a kept recording through transcription again.
    case retryRecording(UUID)
    /// Delete a kept recording without ever hearing it.
    case forgetRecording(UUID)
    /// Play a kept recording, or stop it if it is playing.
    case playRecording(UUID)

    /// Put a changed word back to what was heard.
    case undoCorrection(UUID)
    /// Let a vetoed heard-to-meant pairing be made again.
    case allowPairing(heard: String, meant: String)

    /// Open the inline word editor; the word arrives on ``saveWord(word:pronunciation:applications:)``.
    case addWord
    /// Commit the inline word editor as a new word; an edited word arrives as ``replaceWord(_:word:pronunciation:applications:)``.
    case saveWord(word: String, pronunciation: String, applications: [String])
    /// Open the inline word editor on this word, keeping its identity and counters on save.
    case editWord(UUID)
    /// Close the inline word editor unchanged.
    case cancelWordEdit
    /// Delete the named words from the dictionary in one write, refusing each one.
    case forgetWords(Set<UUID>)
    /// Trust the named retired words again, and let them start earning their place.
    case restoreWords(Set<UUID>)
    /// Respell an existing word as typed in the editor, keeping its counters.
    case replaceWord(UUID, word: String, pronunciation: String, applications: [String])
    /// Fold the second spelling of one word into the first, summing their counters.
    case mergeWords(keeping: UUID, absorbing: UUID)
    /// Let a deleted spelling be learned again.
    case allowWord(String)
    /// Say the word typed in the editor once, to see whether it is recognised; nothing is saved.
    case tryDraft(word: String, pronunciation: String)
    /// Say a saved word once, to see whether it is recognised; nothing is saved.
    case tryWord(UUID)
    /// Say the word typed in the editor once, filling its "Say it like" with what the recogniser writes alone.
    case sayDraft(word: String)
    /// Add what a try heard as a "Say it like": to the open editor, or to this word opened in it.
    case useSayItLike(UUID?, heard: String)

    /// Open the inline snippet editor empty.
    case addSnippet
    /// Open the inline snippet editor on this snippet.
    case editSnippet(UUID)
    /// Delete a snippet.
    case forgetSnippet(UUID)
    /// Restore the snippet held by the latest deletion notice.
    case restoreSnippet(UUID)
    /// Restore valid clipboard privacy settings from their set-aside file.
    case restoreClipboardPreferences
    /// Commit the inline editor; `replacing` is the snippet being edited, or `nil` for a new one.
    case saveSnippet(trigger: String, text: String, applications: [String], replacing: UUID?)
    /// Close the inline snippet editor unchanged.
    case cancelSnippetEdit

    /// A setting changed from the main window, as the same ``SettingsChange`` the settings window reports.
    case change(SettingsChange)

    /// Open onboarding at the sign-in page.
    case signIn
    /// End the session on this Mac.
    case signOut
    /// Delete the account on the server, then end the session on this Mac.
    case deleteAccount
    /// Put away the notice in the window's corner.
    case dismissNotice
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

    /// What pressing it asks first, decided by its intent so every button for one act asks the same.
    public var confirmation: MainConfirmation? { MainConfirmation.before(intent) }
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
    /// The small picture above the title, and the colour that glows behind it.
    public let scene: MainEmptyScene

    /// Builds an empty state; everything after the message is optional, and the scene follows the symbol.
    public init(
        symbolName: String,
        title: String,
        message: String,
        action: MainAction? = nil,
        chips: [MainStatistic] = [],
        progress: MainProgress? = nil,
        footnote: String? = nil,
        scene: MainEmptyScene? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.action = action
        self.chips = chips
        self.progress = progress
        self.footnote = footnote
        self.scene = scene ?? MainEmptyScene(symbolName: symbolName)
    }
}

/// The colour a page is known by: dictation, suggestions, the clipboard, or information.
public enum MainAccent: Sendable, Equatable, CaseIterable {
    case dictation
    case suggestion
    case clipboard
    case info
}

/// The small picture an empty page draws above its title, so each page is recognisable before it has content.
public enum MainEmptyScene: Sendable, Equatable {
    /// The shortcut's keys beside a waveform, for a page that fills as the user dictates.
    case dictation
    /// One of the user's own words on a chip, for the dictionary.
    case word(String)
    /// A phrase that expands on a chip, for snippets.
    case phrase(String)
    /// A few day bars, filled for the days already spoken on, for a page that waits to chart.
    case chart
    /// The state's own symbol on a tile, for everything else.
    case symbol

    /// The dictionary's example word, which is the one the app always spells right.
    public static let exampleWord = "Uttrflow"
    /// The snippets page's example phrase.
    public static let examplePhrase = "my address"

    /// The scene each page's symbol stands for; a symbol with no page of its own gets the plain tile.
    public init(symbolName: String) {
        switch symbolName {
        case "mic", "clock", "waveform": self = .dictation
        case "character.book.closed", "book": self = .word(Self.exampleWord)
        case "doc.on.doc": self = .phrase(Self.examplePhrase)
        case "chart.bar": self = .chart
        default: self = .symbol
        }
    }

    /// The page's colour, which the scene is drawn in and glows behind it.
    public var accent: MainAccent {
        switch self {
        case .dictation, .symbol: .dictation
        case .word: .clipboard
        case .phrase: .suggestion
        case .chart: .info
        }
    }
}

/// The question asked before a button does something that cannot be taken back.
public struct MainConfirmation: Sendable, Equatable {
    /// The question, ending in a question mark.
    public let title: String
    /// What happens and what stays.
    public let message: String
    /// The button that goes ahead.
    public let confirmTitle: String
    /// The button that changes nothing, which Return presses.
    public let cancelTitle: String
    /// The SF Symbol on the sheet's tile.
    public let symbolName: String
    /// The tile's colour.
    public let tone: MainTone
    /// Whether going ahead destroys something, which draws the confirm button in red.
    public let isDestructive: Bool

    /// Builds a question from its parts.
    public init(
        title: String, message: String, confirmTitle: String, cancelTitle: String = "Cancel",
        symbolName: String, tone: MainTone, isDestructive: Bool
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.symbolName = symbolName
        self.tone = tone
        self.isDestructive = isDestructive
    }

    /// Settings' question in the same sheet, since whatever Settings asks first removes something.
    public init(_ settings: SettingsConfirmation) {
        self.init(
            title: settings.title, message: settings.message, confirmTitle: settings.confirmTitle,
            cancelTitle: settings.cancelTitle, symbolName: "trash", tone: .critical,
            isDestructive: true)
    }

    /// Asked before signing out, because Uttrflow stops until the user signs in again.
    public static let signOut = MainConfirmation(
        title: "Sign out of Uttrflow?",
        message: "Your dictations stay on this Mac. You’ll need to sign in again to keep using Uttrflow.",
        confirmTitle: "Sign out", symbolName: "rectangle.portrait.and.arrow.forward", tone: .warning,
        isDestructive: true)

    /// Asked before deleting the account, because the server keeps nothing to restore it from.
    public static let deleteAccount = MainConfirmation(
        title: "Delete your Uttrflow account?",
        message: """
            The server deletes your name, email address, sign-in and the list of your Macs, and this Mac \
            signs out. Your dictations stay on this Mac. This cannot be undone.
            """,
        confirmTitle: "Delete account", symbolName: "person.crop.circle.badge.xmark", tone: .critical,
        isDestructive: true)

    /// What pressing a button for this intent asks first, or `nil` when it acts at once.
    public static func before(_ intent: MainIntent) -> MainConfirmation? {
        switch intent {
        case .signOut: signOut
        case .deleteAccount: deleteAccount
        default: nil
        }
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
        RecoveryActionTitle.title(for: action)
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

    /// The speech model's load as a page's empty state, with the download it needs when there is one.
    public static func obstruction(for load: SpeechModelLoad) -> MainEmptyState {
        MainEmptyState(
            symbolName: load.isLoading ? "hourglass" : "arrow.down.circle",
            title: load.title,
            message: load.message,
            action: load.recovery.map { MainAction(title: title(for: $0), intent: .recover($0)) })
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
    public static func seconds(
        _ duration: Duration, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let value = duration.inSeconds
        guard value >= 0.01 else { return "under \(secondsValue(.milliseconds(10), locale: locale))" }
        return secondsValue(duration, locale: locale)
    }

    /// A duration in seconds to the hundredth, including values below the display floor.
    static func secondsValue(
        _ duration: Duration, locale: Locale = .autoupdatingCurrent
    ) -> String {
        duration.inSeconds.formatted(
            .number.locale(locale).grouping(.never).precision(.fractionLength(2))) + "s"
    }

    /// How long somebody talked, in whole seconds: "11s".
    public static func spoken(_ duration: Duration) -> String {
        guard let seconds = roundedInteger(duration.inSeconds) else { return "—" }
        return "\(max(0, seconds))s"
    }

    /// A rounded finite value that fits in the platform integer type.
    static func roundedInteger(_ value: Double) -> Int? {
        let rounded = value.rounded()
        guard rounded.isFinite, rounded >= Double(Int.min), rounded < Double(Int.max) else {
            return nil
        }
        return Int(rounded)
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
        // Counted in one pass without building the substrings, since every redraw counts every dictation.
        var count = 0
        var inWord = false
        for character in text {
            if character.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
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
        return Self.date(date, now: now, calendar: calendar, locale: locale)
    }

    /// "12 Aug", with the year once the date is not in the current one, so last year never reads as this.
    public static func date(
        _ date: Date, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(style) }
        return date.formatted(style.year())
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

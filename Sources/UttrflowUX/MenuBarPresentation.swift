public import UttrflowCore

// MARK: - What the menu needs to know

/// Where a dictation has got to, in as much detail as a menu needs.
///
/// Deliberately not the pipeline's own state: this module cannot see it, and a menu
/// does not care about the difference between transcribing and tidying — both are a
/// wait, and naming them apart would describe the machinery rather than the moment.
public enum DictationActivity: Sendable, Equatable, CaseIterable {
    case idle
    case listening
    case working
    /// Text has just gone into another app. Resting, but with something to say.
    case finished
}

/// How far the speech model has got. Nothing can be dictated until it is ready.
public enum SpeechModelReadiness: Sendable, Equatable {
    case ready
    /// Being fetched, with how far along it is when that is known.
    case downloading(fractionCompleted: Double?)
    case notInstalled
}

/// A recent dictation, as much of it as a menu can show.
public struct MenuBarRecent: Sendable, Equatable {
    /// Already shortened to one line by whoever keeps the list, because how long a line
    /// a menu can take is not something two places should have an opinion about.
    public let title: String
    /// The whole of it, for the tooltip. Showing only the shortened form would be a lie
    /// about what clicking the row is going to insert.
    public let fullText: String

    public init(title: String, fullText: String) {
        self.title = title
        self.fullText = fullText
    }
}

/// How far along an update is, when one is happening at all.
///
/// Updating was entirely silent before this existed: an update downloaded, waited for a
/// quiet minute, and then the app replaced itself and came back — with nothing anywhere
/// having said so. An app that vanishes and reappears without explanation reads as a
/// crash, and the one moment a user most wants to be told is the moment they are least
/// able to ask.
public enum UpdateProgress: Sendable, Equatable {
    /// Nothing is happening, which is almost always true.
    case idle
    /// The feed has been asked and has not answered yet.
    case checking
    /// An update exists and is coming down. The fraction is absent until enough has
    /// arrived to estimate one.
    case downloading(fraction: Double?)
    /// Downloaded and verified, waiting for the app to be quiet for a minute.
    ///
    /// Its own case rather than folding into ``installing`` because the wait is the part
    /// that needs explaining: an update that says "ready" and then sits there looks
    /// stuck, and the honest line says what it is waiting for.
    case readyToInstall
    /// About to replace the app and relaunch. The last thing shown before it happens.
    case installing
}

/// What the product is doing, in the only terms the menu bar needs it.
public struct MenuBarState: Sendable, Equatable {
    public var activity: DictationActivity
    /// The last thing that went wrong and has not yet been dealt with.
    public var failure: FailurePresentation?
    public var speechModel: SpeechModelReadiness
    /// Newest first.
    public var recents: [MenuBarRecent]
    /// Whether this build has an update feed to ask. False in every build made before
    /// one was configured, and in every development build — where an enabled item that
    /// does nothing would read as a broken app.
    public var canCheckForUpdates: Bool
    /// How far along an update is, if one is under way.
    public var updateProgress: UpdateProgress

    public init(
        activity: DictationActivity = .idle,
        failure: FailurePresentation? = nil,
        speechModel: SpeechModelReadiness = .ready,
        recents: [MenuBarRecent] = [],
        canCheckForUpdates: Bool = false,
        updateProgress: UpdateProgress = .idle
    ) {
        self.activity = activity
        self.failure = failure
        self.speechModel = speechModel
        self.recents = recents
        self.canCheckForUpdates = canCheckForUpdates
        self.updateProgress = updateProgress
    }
}

// MARK: - What the menu is

/// What choosing a menu item means.
///
/// The menu names what it wants rather than reaching for it: window intents carry a
/// ``Destination`` so that the app owns every window and the menu owns none of them.
public enum MenuBarIntent: Sendable, Equatable {
    case startDictation
    /// Ends a dictation the menu itself began.
    ///
    /// Its own intent rather than a second meaning for `startDictation`, so the app
    /// cannot mistake one for the other while the menu is being rebuilt.
    case stopDictation
    /// Carry out the one fix the current failure offered.
    case recover(RecoveryAction)
    /// Positions into ``MenuBarState/recents``, so the menu never carries the text of a
    /// dictation back to the app that already has it.
    case insertRecent(index: Int)
    case copyRecent(index: Int)
    case open(Destination)
    /// Opens the clipboard panel, the same one ⇧⌘V opens.
    ///
    /// Here because it was nowhere. The panel had exactly one way in, a shortcut nothing
    /// on screen mentioned, so a user who had not been told it existed could not find it —
    /// and a comment elsewhere in this app justified the shortcut being optional on the
    /// grounds that the menu bar could still reach it, which was untrue.
    case openClipboard
    /// Ask the update feed now, rather than waiting for the next scheduled check.
    ///
    /// The one path allowed to put an update window in front of somebody: they asked
    /// for it. Everything else about updating happens without a window at all.
    case checkForUpdates
    case quit
}

/// One modifier a menu shortcut can use.
///
/// An enumeration as well as an option set, because the app target has to translate
/// these into AppKit's flags and a translation written as a list of `if`s is a list
/// somebody has to remember to extend. `shift` was added here for the clipboard's
/// ⇧⌘V and the translation was not, so the menu printed ⌘V beside it — and bound
/// ⌘V, which is paste. Iterating `allCases` and switching over them makes the next
/// addition a compile error instead of a wrong shortcut on screen.
public enum MenuBarModifier: CaseIterable, Sendable, Equatable {
    case command
    case option
    case shift
}

/// The modifiers a menu shortcut can use.
public struct MenuBarModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = MenuBarModifiers(rawValue: 1 << 0)
    public static let option = MenuBarModifiers(rawValue: 1 << 1)
    /// Added for the clipboard's ⇧⌘V. The set had only the two the dictation
    /// shortcut needed, which is why nothing here could describe the other half of the app.
    public static let shift = MenuBarModifiers(rawValue: 1 << 2)

    /// The one-modifier value for each case, so the two spellings cannot drift apart.
    public static func one(_ modifier: MenuBarModifier) -> MenuBarModifiers {
        switch modifier {
        case .command: .command
        case .option: .option
        case .shift: .shift
        }
    }

    public func contains(_ modifier: MenuBarModifier) -> Bool {
        contains(Self.one(modifier))
    }
}

/// A key combination printed beside a menu item.
public struct MenuBarShortcut: Sendable, Equatable {
    /// The character as it is typed, for example "," or " ".
    public let key: String
    public let modifiers: MenuBarModifiers

    public init(key: String, modifiers: MenuBarModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The shortcut the product ships with for dictating.
    ///
    /// Held as a constant rather than read from the user's binding because a menu needs
    /// the character that is typed and a binding stores a positional key code — only
    /// the platform layer can turn one into the other, and it is not on this side of
    /// the boundary.
    public static let dictation = MenuBarShortcut(key: " ", modifiers: .option)
}

/// One thing the user can choose, and whether they may.
public struct MenuBarCommand: Sendable, Equatable {
    public let title: String
    public let intent: MenuBarIntent
    public let shortcut: MenuBarShortcut?
    /// A disabled item reads as "not yet"; an enabled one that does nothing reads as a
    /// broken app. Which of the two an item is, is decided here and nowhere else.
    public let isEnabled: Bool
    /// Shown in place of the row above it while Option is held.
    public let isAlternate: Bool
    /// The whole of a title that had to be shortened.
    public let tooltip: String?

    public init(
        title: String, intent: MenuBarIntent, shortcut: MenuBarShortcut? = nil,
        isEnabled: Bool = true, isAlternate: Bool = false, tooltip: String? = nil
    ) {
        self.title = title
        self.intent = intent
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.isAlternate = isAlternate
        self.tooltip = tooltip
    }
}

/// How the status line, and the dot beside it, are coloured.
public enum MenuBarEmphasis: Sendable, Equatable, CaseIterable {
    case normal
    /// The microphone is live.
    case live
    /// Something is waiting on the user.
    case attention
}

/// A row of the menu, in the order the menu shows them.
public enum MenuBarItem: Sendable, Equatable {
    /// The line at the top saying what is happening. Never clickable.
    case status(text: String, emphasis: MenuBarEmphasis)
    case sectionHeader(String)
    case separator
    case command(MenuBarCommand)
}

/// What is drawn in the menu bar slot.
///
/// Two kinds, because the slot answers two different questions. At rest it says whose
/// app this is, and the mark does that better than any system symbol can. The moment
/// something is happening it has to say *what*, and there the shared vocabulary of SF
/// Symbols is worth more than a logo.
public enum MenuBarIcon: Sendable, Hashable {
    /// The Uttrflow mark, shipped as a template image so the system tints it for a
    /// light or dark bar.
    case mark
    /// An SF Symbol, by name.
    case symbol(String)
}

/// What the menu bar item shows: its icon, and the menu behind it.
public struct MenuBarPresentation: Sendable, Equatable {
    /// What the slot draws — the mark at rest, a symbol for everything else.
    public let icon: MenuBarIcon
    public let statusLine: String
    public let emphasis: MenuBarEmphasis
    /// Read aloud by VoiceOver. An icon is not a sentence, and for many users the
    /// icon is the only part of Uttrflow that is ever on screen.
    public let accessibilityLabel: String
    public let items: [MenuBarItem]

    public init(
        icon: MenuBarIcon, statusLine: String, emphasis: MenuBarEmphasis,
        accessibilityLabel: String, items: [MenuBarItem]
    ) {
        self.icon = icon
        self.statusLine = statusLine
        self.emphasis = emphasis
        self.accessibilityLabel = accessibilityLabel
        self.items = items
    }

    /// Whether the icon should be tinted rather than drawn as a plain template.
    /// Derived, so the icon and the status line cannot disagree about the same moment.
    public var isAttentionNeeded: Bool { emphasis == .attention }

    /// Every command in the menu, in order. Lets a caller — most usefully a test — ask
    /// what is on offer without walking past the separators and headers.
    public var commands: [MenuBarCommand] {
        items.compactMap { if case .command(let command) = $0 { command } else { nil } }
    }
}

// MARK: - Deciding it

/// Works out the whole menu from the state of the product.
///
/// Pure, and the only place that decides what the menu bar offers. The controller that
/// draws it makes no judgement of its own, so the icon, the status line, VoiceOver and
/// whether an item is greyed out can never tell the user three different stories about
/// the same moment.
public enum MenuBarPresenter {
    public static func present(_ state: MenuBarState) -> MenuBarPresentation {
        // Only a failure that has been placed in the menu bar may light the icon up. A
        // degraded one already said its piece next to the work; shouting about it here
        // as well would leave an orange menu bar over an app that is working fine.
        let needsAttention = state.failure?.placement == .menuBar
        let emphasis: MenuBarEmphasis =
            if needsAttention {
                .attention
            } else if state.activity == .listening {
                .live
            } else {
                .normal
            }

        let statusLine = statusLine(for: state)
        return MenuBarPresentation(
            icon: icon(for: state.activity, needsAttention: needsAttention),
            statusLine: statusLine,
            emphasis: emphasis,
            accessibilityLabel: spokenForm(of: statusLine),
            items: items(for: state, statusLine: statusLine, emphasis: emphasis)
        )
    }

    // MARK: The icon

    /// Idle, recording, working, done — and, above all of them, something wrong.
    ///
    /// Resting is the mark; the rest are symbols. All four still differ from one
    /// another, which is the point: someone who never opens the menu can still tell
    /// from the bar alone whether the microphone is live.
    static func icon(for activity: DictationActivity, needsAttention: Bool) -> MenuBarIcon {
        guard !needsAttention else { return .symbol("exclamationmark.triangle.fill") }
        return switch activity {
        case .idle: .mark
        case .listening: .symbol("mic.fill")
        case .working: .symbol("sparkles")
        case .finished: .symbol("checkmark")
        }
    }

    // MARK: The status line

    /// What is happening, in one short line.
    ///
    /// A failure takes precedence over everything: it is the reason the user opened the
    /// menu. Otherwise setting up outranks resting, because a "Ready" that cannot
    /// dictate is worse than saying nothing at all.
    static func statusLine(for state: MenuBarState) -> String {
        if let failure = state.failure { return failure.headline }

        // Above the model and the dictation activity, and below a failure. An update
        // that is installing is about to take the app away, which outranks anything the
        // app is otherwise doing — but it is not a problem, so it does not outrank one.
        if let updating = updateLine(for: state.updateProgress) { return updating }

        switch state.speechModel {
        case .downloading(let fraction):
            guard let fraction else { return "Setting up…" }
            return "Setting up… \(percentage(of: fraction))%"
        case .notInstalled:
            return "Setup hasn't finished"
        case .ready:
            return switch state.activity {
            case .idle: "Ready"
            case .listening: "Listening…"
            case .working: "Tidying up…"
            case .finished: "Inserted"
            }
        }
    }

    /// What an update in progress says, or `nil` when none is.
    ///
    /// "Checking" is deliberately absent: a check happens every six hours on a timer
    /// nobody asked about, and a status line that flickers between "Ready" and
    /// "Checking for updates…" four times a day is noise about something that needs no
    /// attention. It is shown only when the user pressed the button — which is the one
    /// case where somebody is waiting for the answer.
    static func updateLine(for progress: UpdateProgress) -> String? {
        switch progress {
        case .idle: nil
        case .checking: "Checking for updates…"
        case .downloading(let fraction):
            if let fraction {
                "Downloading update… \(percentage(of: fraction))%"
            } else {
                "Downloading update…"
            }
        case .readyToInstall: "Update ready — installing when you pause"
        case .installing: "Updating…"
        }
    }

    /// Clamped because a download reporting 103% is a bug in the downloader, and the
    /// menu bar is the wrong place to find out about it.
    static func percentage(of fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// The status line as VoiceOver should read it.
    ///
    /// Built from the same string rather than written out a second time: two lists of
    /// wordings drift, and the one that drifts is always the one nobody can see.
    static func spokenForm(of statusLine: String) -> String {
        // An ellipsis means "still going" to the eye and nothing at all to the ear.
        let spoken = String(statusLine.filter { $0 != "…" })
        let stop = spoken.hasSuffix(".") ? "" : "."
        return "Uttrflow. \(spoken)\(stop)"
    }

    // MARK: The menu

    static func items(
        for state: MenuBarState, statusLine: String, emphasis: MenuBarEmphasis
    ) -> [MenuBarItem] {
        var items: [MenuBarItem] = [.status(text: statusLine, emphasis: emphasis)]

        // The problem and its one fix sit together at the top. Anything between them
        // would make the user hunt for the way out of the thing they came here about.
        if let action = state.failure?.action {
            items.append(
                .command(MenuBarCommand(title: menuTitle(for: action), intent: .recover(action.recovery))))
        }
        items.append(.separator)

        // A toggle, not a one-way door. It used to say "Start Dictation" always, with no
        // stop anywhere in the menu: a dictation begun from here left the microphone open
        // with the item still reading "Start Dictation" and still enabled, and the only
        // way out was the shortcut — a short tap of which hits the slip rule and silently
        // discards everything recorded, while a long hold dumps the whole accumulated
        // buffer into whatever happens to be focused by then.
        items.append(
            .command(
                MenuBarCommand(
                    title: isDictating(in: state) ? "Stop Dictation" : "Start Dictation",
                    intent: isDictating(in: state) ? .stopDictation : .startDictation,
                    shortcut: .dictation,
                    isEnabled: isDictating(in: state) || canStartDictation(in: state))))

        // Directly under dictation, because these are the app's two halves and the menu is
        // where somebody looks when they have forgotten the shortcut for either.
        items.append(
            .command(
                MenuBarCommand(
                    title: "Clipboard", intent: .openClipboard,
                    shortcut: MenuBarShortcut(key: "v", modifiers: [.command, .shift]))))

        items.append(contentsOf: recentItems(for: state))

        items.append(.separator)
        // Both windows exist as of this phase, so both are offered. The menu names the
        // place and the app opens it; nothing here knows a window from a hole in the wall.
        items.append(
            .command(
                MenuBarCommand(
                    title: "Open Uttrflow", intent: .open(.main(.dictation)),
                    shortcut: MenuBarShortcut(key: "0", modifiers: .command))))
        items.append(
            .command(
                MenuBarCommand(
                    title: "Settings…", intent: .open(.settings(.general)),
                    shortcut: MenuBarShortcut(key: ",", modifiers: .command))))
        // Only in a build that can actually update. An enabled item that does nothing
        // reads as a broken app, and a disabled one in every development build reads as
        // a feature somebody forgot to finish.
        if state.canCheckForUpdates {
            items.append(
                .command(
                    MenuBarCommand(title: "Check for Updates…", intent: .checkForUpdates)))
        }

        items.append(.separator)
        items.append(
            .command(
                MenuBarCommand(
                    title: "Quit Uttrflow", intent: .quit,
                    shortcut: MenuBarShortcut(key: "q", modifiers: .command))))
        return items
    }

    /// Three separate reasons dictation cannot begin, and the item is greyed for all of
    /// them: pressing something and having nothing happen reads as a broken app, and a
    /// user who has just been refused the microphone would believe it.
    /// Whether the microphone is open right now, and so whether the item must offer a
    /// way to close it.
    ///
    /// `.working` is deliberately not included: transcription cannot be stopped, and an
    /// enabled Stop that did nothing would be worse than a greyed one.
    static func isDictating(in state: MenuBarState) -> Bool {
        state.activity == .listening
    }

    static func canStartDictation(in state: MenuBarState) -> Bool {
        guard state.failure?.severity != .blocking else { return false }
        guard state.speechModel == .ready else { return false }
        return switch state.activity {
        case .idle, .finished: true
        case .listening, .working: false
        }
    }

    /// The Recent section, or nothing at all.
    ///
    /// Absent rather than present-and-empty: a permanently greyed "No recent dictations"
    /// row is a line of the menu spent telling the user something they can already see.
    static func recentItems(for state: MenuBarState) -> [MenuBarItem] {
        guard !state.recents.isEmpty else { return [] }

        // Reaching into the pipeline's output while the pipeline is running it would
        // race the insertion that is already on its way.
        let isEnabled = !isBusy(state.activity)
        var items: [MenuBarItem] = [.sectionHeader("Recent")]
        for (index, recent) in state.recents.enumerated() {
            items.append(
                .command(
                    MenuBarCommand(
                        title: recent.title, intent: .insertRecent(index: index),
                        isEnabled: isEnabled, tooltip: recent.fullText)))
            // Copying is the rarer wish, so it hides behind Option on the same row
            // rather than doubling the length of the section.
            items.append(
                .command(
                    MenuBarCommand(
                        title: "Copy “\(recent.title)”", intent: .copyRecent(index: index),
                        shortcut: MenuBarShortcut(key: "", modifiers: .option),
                        isEnabled: isEnabled, isAlternate: true, tooltip: recent.fullText)))
        }
        return items
    }

    static func isBusy(_ activity: DictationActivity) -> Bool {
        switch activity {
        case .listening, .working: true
        case .idle, .finished: false
        }
    }

    /// The same words as the banner button, plus the ellipsis that macOS menus put on
    /// anything which opens something else before it does what it says.
    static func menuTitle(for action: FailureAction) -> String {
        switch action.recovery {
        case .openSystemSettings: "\(action.title)…"
        case .retry, .downloadSpeechModel, .pasteManually, .showRecentDictations: action.title
        }
    }
}

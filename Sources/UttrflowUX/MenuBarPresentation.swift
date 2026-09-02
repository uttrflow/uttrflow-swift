public import UttrflowCore

// MARK: - What the menu needs to know

/// Where a dictation has got to, in as much detail as a menu needs and no more.
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
    /// On disk, but not yet loaded into memory, which is cold-start slow.
    case loading
    case notInstalled
}

/// A recent dictation, as much of it as a menu can show.
public struct MenuBarRecent: Sendable, Equatable {
    /// Already shortened by whoever keeps the list, so only one place decides a menu's width.
    public let title: String
    /// The whole of it, for the tooltip, since the row says less than it will insert.
    public let fullText: String

    public init(title: String, fullText: String) {
        self.title = title
        self.fullText = fullText
    }
}

/// How far along an update is, so an app that replaces itself does not read as a crash.
public enum UpdateProgress: Sendable, Equatable {
    /// Nothing is happening, which is almost always true.
    case idle
    /// The feed has been asked and has not answered yet.
    case checking
    /// Coming down, with no fraction until enough has arrived to estimate one.
    case downloading(fraction: Double?)
    /// Downloaded and waiting for a quiet minute, which is the part that needs explaining.
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
    /// How a long recording is going, so the status line can count it down.
    public var recordingAdvice: DictationAdvice
    /// Newest first.
    public var recents: [MenuBarRecent]
    /// Whether this build has a feed to ask, so no item is enabled that could do nothing.
    public var canCheckForUpdates: Bool
    /// How far along an update is, if one is under way.
    public var updateProgress: UpdateProgress

    public init(
        activity: DictationActivity = .idle,
        failure: FailurePresentation? = nil,
        speechModel: SpeechModelReadiness = .ready,
        recordingAdvice: DictationAdvice = .keepGoing,
        recents: [MenuBarRecent] = [],
        canCheckForUpdates: Bool = false,
        updateProgress: UpdateProgress = .idle
    ) {
        self.activity = activity
        self.failure = failure
        self.speechModel = speechModel
        self.recordingAdvice = recordingAdvice
        self.recents = recents
        self.canCheckForUpdates = canCheckForUpdates
        self.updateProgress = updateProgress
    }
}

// MARK: - What the menu is

/// What choosing a menu item means, named so the app owns every window and the menu none.
public enum MenuBarIntent: Sendable, Equatable {
    case startDictation
    /// Ends a dictation, as its own intent so a rebuild cannot mistake it for starting one.
    case stopDictation
    /// Carry out the one fix the current failure offered.
    case recover(RecoveryAction)
    /// A position into ``MenuBarState/recents``, so no text travels back to the app that has it.
    case insertRecent(index: Int)
    case copyRecent(index: Int)
    case open(Destination)
    /// Opens the clipboard panel, which is otherwise reachable only by a shortcut nothing mentions.
    case openClipboard
    /// Ask the feed now, and the one path allowed to put an update window on screen.
    case checkForUpdates
    case quit
}

/// One modifier, as a case as well as a flag, so translating them is a switch and not a list of `if`s.
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
    /// Added for the clipboard's ⇧⌘V, which the dictation shortcut's two could not describe.
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

    /// The shipping dictation shortcut, as a character because a binding stores a key code.
    public static let dictation = MenuBarShortcut(key: " ", modifiers: .option)
}

/// One thing the user can choose, and whether they may.
public struct MenuBarCommand: Sendable, Equatable {
    public let title: String
    public let intent: MenuBarIntent
    public let shortcut: MenuBarShortcut?
    /// Decided here and nowhere else: an enabled item that does nothing reads as a broken app.
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

/// What is drawn in the slot: the mark at rest, and a symbol the moment something is happening.
public enum MenuBarIcon: Sendable, Hashable {
    /// The Uttrflow mark, a template image so the system tints it for the bar.
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
    /// Read aloud by VoiceOver, for whom the icon is often the only part of Uttrflow on screen.
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

    /// Whether the icon is tinted, derived so it cannot disagree with the status line.
    public var isAttentionNeeded: Bool { emphasis == .attention }

    /// Every command in order, so a caller need not walk past separators and headers.
    public var commands: [MenuBarCommand] {
        items.compactMap { if case .command(let command) = $0 { command } else { nil } }
    }
}

// MARK: - Deciding it

/// Works out the whole menu, and is the only place that decides what the menu bar offers.
public enum MenuBarPresenter {
    public static func present(_ state: MenuBarState) -> MenuBarPresentation {
        // Only a failure placed here lights the icon, or a working app wears an orange bar.
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

    /// Four states that differ at a glance, so the bar alone says whether the microphone is live.
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

    /// What is happening, failure first, and setting up above resting.
    static func statusLine(for state: MenuBarState) -> String {
        if let failure = state.failure { return failure.headline }

        // Above the model and the activity, below a failure: it takes the app away, but is not a fault.
        if let updating = updateLine(for: state.updateProgress) { return updating }

        switch state.speechModel {
        case .downloading(let fraction):
            guard let fraction else { return "Setting up…" }
            return "Setting up… \(percentage(of: fraction))%"
        case .loading:
            return "Getting ready…"
        case .notInstalled:
            return "Setup hasn't finished"
        case .ready:
            return switch state.activity {
            case .idle: "Ready"
            case .listening: listeningLine(for: state.recordingAdvice)
            case .working: "Tidying up…"
            case .finished: "Inserted"
            }
        }
    }

    /// What an update in progress says, with "checking" absent unless the user asked.
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

    /// Clamped, because the menu bar is the wrong place to learn the downloader has a bug.
    static func percentage(of fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// The status line as VoiceOver reads it, built from the same string so the two cannot drift.
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

        // The problem and its fix together at the top, with nothing between them.
        if let action = state.failure?.action {
            items.append(
                .command(MenuBarCommand(title: menuTitle(for: action), intent: .recover(action.recovery))))
        }
        items.append(.separator)

        // A toggle, so a dictation begun here has a way to end here.
        items.append(
            .command(
                MenuBarCommand(
                    title: isDictating(in: state) ? "Stop Dictation" : "Start Dictation",
                    intent: isDictating(in: state) ? .stopDictation : .startDictation,
                    shortcut: .dictation,
                    isEnabled: isDictating(in: state) || canStartDictation(in: state))))

        // Directly under dictation: the app's two halves, and this is where a forgotten shortcut is looked up.
        items.append(
            .command(
                MenuBarCommand(
                    title: "Clipboard", intent: .openClipboard,
                    shortcut: MenuBarShortcut(key: "v", modifiers: [.command, .shift]))))

        items.append(contentsOf: recentItems(for: state))

        items.append(.separator)
        // The menu names the place and the app opens it.
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
        // Only in a build that can update, since neither an enabled nor a greyed item would read well.
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

    /// What a recording says about itself, counting down once it nears its cap.
    static func listeningLine(for advice: DictationAdvice) -> String {
        guard let remaining = RemainingTime.phrase(for: advice) else { return "Listening…" }
        return "Listening… \(remaining)"
    }

    /// Whether the microphone is open, and so whether Stop must be offered. Never while working.
    static func isDictating(in state: MenuBarState) -> Bool {
        state.activity == .listening
    }

    /// Greyed for all three reasons dictation cannot begin, since a dead item reads as broken.
    static func canStartDictation(in state: MenuBarState) -> Bool {
        guard state.failure?.severity != .blocking else { return false }
        guard state.speechModel == .ready else { return false }
        return switch state.activity {
        case .idle, .finished: true
        case .listening, .working: false
        }
    }

    /// The Recent section, absent rather than empty, since a greyed row says nothing.
    static func recentItems(for state: MenuBarState) -> [MenuBarItem] {
        guard !state.recents.isEmpty else { return [] }

        // Reaching in while the pipeline runs would race the insertion already on its way.
        let isEnabled = !isBusy(state.activity)
        var items: [MenuBarItem] = [.sectionHeader("Recent")]
        for (index, recent) in state.recents.enumerated() {
            items.append(
                .command(
                    MenuBarCommand(
                        title: recent.title, intent: .insertRecent(index: index),
                        isEnabled: isEnabled, tooltip: recent.fullText)))
            // Copying hides behind Option rather than doubling the section's length.
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

    /// The banner button's words, plus the ellipsis macOS puts on anything that opens something first.
    static func menuTitle(for action: FailureAction) -> String {
        switch action.recovery {
        case .openSystemSettings: "\(action.title)…"
        case .retry, .downloadSpeechModel, .pasteManually, .showRecentDictations: action.title
        }
    }
}

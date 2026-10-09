public import struct Foundation.UUID
public import UttrflowClipboard
public import UttrflowCore

// MARK: - What the menu needs to know

/// Where a dictation has got to, in as much detail as a menu needs and no more.
public enum DictationActivity: Sendable, Equatable, CaseIterable {
    case idle
    case listening
    case working
    /// Text was confirmed in the target app.
    case inserted
    /// Text was confirmed, but part of the speech decoded to no words and is missing from it.
    case partial
    /// The target did not confirm the text, which remains on the clipboard.
    case unconfirmed
    /// Text remains on the clipboard for the user to paste.
    case copied
    /// A long recording was cancelled, so nothing was typed.
    case discarded
    /// A command-key utterance ran an edit, so nothing was typed.
    case executed

    /// Carries the insertion outcome through the menu without claiming text arrived when it did not.
    public static func completion(
        method: TextInsertionMethod, arrival: InsertionArrival, missedPieces: Int = 0
    ) -> Self {
        if method == .clipboard { return .copied }
        if arrival == .unconfirmed { return .unconfirmed }
        return MissedSpeech.isMissing(missedPieces) ? .partial : .inserted
    }
}

/// How far the speech model has got. Nothing can be dictated until it is ready.
public enum SpeechModelReadiness: Sendable, Equatable {
    case ready
    /// Being fetched, with how far along it is when that is known.
    case downloading(fractionCompleted: Double?)
    /// On disk, but not yet loaded into memory, which is cold-start slow.
    case loading
    /// On disk, but the load ended without a model that can transcribe; one reload is offered.
    case loadFailed
    /// On disk, but the reload failed as well, so only a fresh download repairs it.
    case loadFailedAgain
    /// Its folder is on disk but lacks a file it needs, so it must be downloaded again.
    case incomplete
    case notInstalled

    /// Where a completed model load leaves readiness, before retry and incomplete-folder details are applied.
    public static func afterLoad(isReady: Bool, isInstalled: Bool) -> SpeechModelReadiness {
        if isReady { return .ready }
        return isInstalled ? .loadFailed : .notInstalled
    }

    /// What to tell a person about the load, timed from `start`; `nil` when there is no load to speak of.
    public func load<Moment: InstantProtocol>(
        since start: Moment?, now: Moment
    ) -> SpeechModelLoad? where Moment.Duration == Duration {
        switch self {
        case .loading: .loading(elapsed: start.map { $0.duration(to: now) } ?? .zero)
        case .loadFailed: .failed
        case .loadFailedAgain, .incomplete: .broken
        case .notInstalled: .missing
        case .ready, .downloading: nil
        }
    }

    /// Where a load that has ended leaves the model: ready, short of files, or failed once or twice.
    public static func settled(
        isReady: Bool, isInstalled: Bool, isIncomplete: Bool, failedBefore: Bool
    ) -> SpeechModelReadiness {
        switch afterLoad(isReady: isReady, isInstalled: isInstalled) {
        case .ready: .ready
        case .loadFailed: failedBefore ? .loadFailedAgain : .loadFailed
        case .notInstalled: isIncomplete ? .incomplete : .notInstalled
        case .downloading, .loading, .loadFailedAgain, .incomplete: .notInstalled
        }
    }

    /// What fixes a model that cannot dictate: one reload after a first failure, a download otherwise.
    public var recovery: RecoveryAction? {
        switch self {
        case .loadFailed: .retry
        case .loadFailedAgain, .incomplete, .notInstalled: .downloadSpeechModel
        case .ready, .downloading, .loading: nil
        }
    }
}

/// A recent dictation, as much of it as a menu can show.
public struct MenuBarRecent: Sendable, Equatable {
    /// Identifies the dictation across menu redraws.
    public let id: UUID
    /// Already shortened by whoever keeps the list, so only one place decides a menu's width.
    public let title: String
    /// The whole of it, for the tooltip, since the row says less than it will insert.
    public let fullText: String
    /// Whether the text is a secret and its tooltip must be omitted.
    public let isSecret: Bool

    public init(id: UUID = UUID(), title: String, fullText: String, isSecret: Bool = false) {
        self.id = id
        self.title = title
        self.fullText = fullText
        self.isSecret = isSecret
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

/// One of the three halves of the product, each switched on and off without touching the others.
public enum MenuBarFeature: String, Sendable, Equatable, CaseIterable {
    case dictation
    case clipboard
    case suggestions

    /// What the switch is called in the menu.
    public var title: String {
        switch self {
        case .dictation: "Dictation"
        case .clipboard: "Clipboard"
        case .suggestions: "AI Suggestions"
        }
    }

    /// Whether the feature name carries a beta badge.
    public var isBeta: Bool { self != .dictation }
}

/// Which of the three are on, held as three answers so switching one cannot move another.
public struct MenuBarFeatures: Sendable, Equatable {
    public var dictation: Bool
    public var clipboard: Bool
    /// Off to begin with, the same as the setting it stands for.
    public var suggestions: Bool

    public init(dictation: Bool = true, clipboard: Bool = true, suggestions: Bool = false) {
        self.dictation = dictation
        self.clipboard = clipboard
        self.suggestions = suggestions
    }

    public func isOn(_ feature: MenuBarFeature) -> Bool {
        switch feature {
        case .dictation: dictation
        case .clipboard: clipboard
        case .suggestions: suggestions
        }
    }

    /// Answers a copy with one switch moved, which is the whole of the independence promise.
    public func setting(_ feature: MenuBarFeature, isOn: Bool) -> MenuBarFeatures {
        var updated = self
        switch feature {
        case .dictation: updated.dictation = isOn
        case .clipboard: updated.clipboard = isOn
        case .suggestions: updated.suggestions = isOn
        }
        return updated
    }
}

/// What the product is doing, in the only terms the menu bar needs it.
public struct MenuBarState: Sendable, Equatable {
    public var activity: DictationActivity
    /// The last thing that went wrong and has not yet been dealt with.
    public var failure: FailurePresentation?
    public var speechModel: SpeechModelReadiness
    /// How long the speech model's load has run, which paces its estimate; ignored unless it is loading.
    public var speechLoadElapsed: Duration
    /// How a long recording is going, so the status line can count it down.
    public var recordingAdvice: DictationAdvice
    /// What ends the recording under way, so the status line says how to finish one that release does not.
    public var stopGesture: StopGesture
    /// Newest first.
    public var recents: [MenuBarRecent]
    /// The clipboard's kept copies, newest first; the popover shows the first few.
    public var clips: [Clip]
    /// Words the dictionary learned within ``RecentlyLearned/holdingPeriod``, newest first.
    public var learned: [LearnedWord]
    /// How far along an update is, if one is under way.
    public var updateProgress: UpdateProgress
    /// Whether this build has a configured, verifiable update feed.
    public var canCheckForUpdates: Bool

    /// Which of the three halves of the product are switched on.
    public var features: MenuBarFeatures

    /// What the user actually bound, so the menu never advertises a key that does nothing.
    public var shortcuts: ShortcutSet

    /// Shortcuts the app could not claim, so the menu never advertises a key that does nothing.
    public var unarmedShortcuts: Set<ShortcutAction>

    /// Why the dictation shortcut cannot be heard right now, or nil when it can.
    public var shortcutUnheard: String?
    /// Why AI suggestions cannot receive keyboard input right now, or nil when they can.
    public var suggestionUnheard: String?
    /// Whether AI suggestions can receive keyboard input right now.
    public var suggestionRuntime: SuggestionRuntimeStatus
    /// How far along the AI suggestion model is, so a switch that is on but waiting says so.
    public var suggestionModel: SuggestionModelReadiness
    /// Whether the dictation shortcut is held or pressed, so the hint uses the right verb.
    public var activation: HotkeyActivation
    /// What the speech model costs to download, for the line that offers it.
    public var speechModelBytes: Int64?

    public init(
        activity: DictationActivity = .idle,
        failure: FailurePresentation? = nil,
        speechModel: SpeechModelReadiness = .ready,
        speechLoadElapsed: Duration = .zero,
        recordingAdvice: DictationAdvice = .keepGoing,
        stopGesture: StopGesture = .letGo,
        recents: [MenuBarRecent] = [],
        clips: [Clip] = [],
        learned: [LearnedWord] = [],
        updateProgress: UpdateProgress = .idle,
        canCheckForUpdates: Bool = false,
        features: MenuBarFeatures = MenuBarFeatures(),
        shortcuts: ShortcutSet = .default,
        unarmedShortcuts: Set<ShortcutAction> = [],
        shortcutUnheard: String? = nil,
        suggestionUnheard: String? = nil,
        suggestionRuntime: SuggestionRuntimeStatus = .idle,
        suggestionModel: SuggestionModelReadiness = .notAsked,
        activation: HotkeyActivation = .holdToTalk,
        speechModelBytes: Int64? = nil
    ) {
        self.activity = activity
        self.failure = failure
        self.speechModel = speechModel
        self.speechLoadElapsed = speechLoadElapsed
        self.recordingAdvice = recordingAdvice
        self.stopGesture = stopGesture
        self.recents = recents
        self.clips = clips
        self.learned = learned
        self.updateProgress = updateProgress
        self.canCheckForUpdates = canCheckForUpdates
        self.features = features
        self.shortcuts = shortcuts
        self.unarmedShortcuts = unarmedShortcuts
        self.shortcutUnheard = shortcutUnheard
        self.suggestionUnheard = suggestionUnheard
        self.suggestionRuntime = suggestionRuntime
        self.suggestionModel = suggestionModel
        self.activation = activation
        self.speechModelBytes = speechModelBytes
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
    /// Identifies the dictation to insert, so a redraw cannot change the chosen words.
    case insertRecent(id: UUID)
    case copyRecent(id: UUID)
    /// Identifies the clip to insert, so a redraw cannot change the chosen copy.
    case insertClip(id: UUID)
    case copyClip(id: UUID)
    /// Removes and refuses a learned word, named by its entry so a redraw cannot change which.
    case undoLearnedWord(id: UUID)
    case open(AppLocation)
    /// Opens the clipboard panel, which is otherwise reachable only by a shortcut nothing mentions.
    case openClipboard
    /// Move one of the three switches, naming the one it moves so the other two cannot follow.
    case setFeature(MenuBarFeature, isOn: Bool)
    /// Starts a manual update check when the current build has a trusted update feed.
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

    /// The key equivalent for a binding, or nothing when the key cannot be one — `fn` has no character.
    public static func forBinding(_ binding: HotkeyBinding?) -> MenuBarShortcut? {
        guard let binding, let key = keyEquivalents[binding.keyCode] else { return nil }
        // A menu item cannot carry ⌃, and a shortcut missing a modifier is a different shortcut.
        guard !binding.modifiers.contains(.control) else { return nil }
        var modifiers: MenuBarModifiers = []
        if binding.modifiers.contains(.command) { modifiers.insert(.command) }
        if binding.modifiers.contains(.option) { modifiers.insert(.option) }
        if binding.modifiers.contains(.shift) { modifiers.insert(.shift) }
        return MenuBarShortcut(key: key, modifiers: modifiers)
    }

    /// The key codes an `NSMenuItem` can pair with, by ANSI position; everything else has no character.
    private static let keyEquivalents: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u",
        34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 25: "9", 26: "7", 28: "8",
        29: "0", 24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",",
        44: "/", 47: ".", 50: "`", 49: " ",
    ]
}

/// One thing the user can choose, and whether they may.
public struct MenuBarCommand: Sendable, Equatable {
    public let title: String
    public let intent: MenuBarIntent
    public let shortcut: MenuBarShortcut?
    /// Decided here and nowhere else: an enabled item that does nothing reads as a broken app.
    public let isEnabled: Bool
    /// The whole of a title that had to be shortened.
    public let tooltip: String?
    /// Whether the item wears a tick, which only a switch ever does.
    public let isChecked: Bool

    public init(
        title: String, intent: MenuBarIntent, shortcut: MenuBarShortcut? = nil,
        isEnabled: Bool = true, tooltip: String? = nil,
        isChecked: Bool = false
    ) {
        self.title = title
        self.intent = intent
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.tooltip = tooltip
        self.isChecked = isChecked
    }
}

/// How the status line, and the dot beside it, are coloured.
public enum MenuBarEmphasis: Sendable, Equatable, CaseIterable {
    case normal
    /// The microphone is live.
    case live
    /// Something is waiting on the user.
    case attention

    /// The SF Symbol beside the status line: one dot, or a shape per emphasis when colour must not carry it alone.
    public func marker(differentiatesWithoutColour: Bool) -> String {
        guard differentiatesWithoutColour else { return "circlebadge.fill" }
        return switch self {
        case .normal: "circle.fill"
        case .live: "record.circle"
        case .attention: "exclamationmark.triangle.fill"
        }
    }
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

/// What the menu bar item shows: its icon, the popover behind it, and its right-click menu.
public struct MenuBarPresentation: Sendable, Equatable {
    /// What the slot draws — the mark at rest, a symbol for everything else.
    public let icon: MenuBarIcon
    public let statusLine: String
    public let emphasis: MenuBarEmphasis
    /// Read aloud by VoiceOver, for whom the icon is often the only part of Uttrflow on screen.
    public let accessibilityLabel: String
    /// Whether the status item marks clipboard capture as available.
    public let clipboardCaptureEnabled: Bool
    /// The popover's top line: the talk hint at rest, or what is happening instead.
    public let header: MenuBarHeader
    /// The popover's round buttons, left to right.
    public let buttons: [MenuBarButton]
    /// The newest dictation, or nothing when there is none to show.
    public let lastDictation: MenuBarRow?
    /// The newest clips, empty when there are none or the clipboard is switched off.
    public let clips: [MenuBarRow]
    /// Words learned lately, each with its Undo; empty when there are none.
    public let learned: [MenuBarLearnedRow]
    /// The right-click menu, in the order it shows them.
    public let items: [MenuBarItem]

    public init(
        icon: MenuBarIcon, statusLine: String, emphasis: MenuBarEmphasis,
        accessibilityLabel: String, clipboardCaptureEnabled: Bool = true,
        header: MenuBarHeader, buttons: [MenuBarButton],
        lastDictation: MenuBarRow?, clips: [MenuBarRow], learned: [MenuBarLearnedRow] = [],
        items: [MenuBarItem]
    ) {
        self.icon = icon
        self.statusLine = statusLine
        self.emphasis = emphasis
        self.accessibilityLabel = accessibilityLabel
        self.clipboardCaptureEnabled = clipboardCaptureEnabled
        self.header = header
        self.buttons = buttons
        self.lastDictation = lastDictation
        self.clips = clips
        self.learned = learned
        self.items = items
    }

    /// Whether the icon is tinted, derived so it cannot disagree with the status line.
    public var isAttentionNeeded: Bool { emphasis == .attention }

    /// Every command the popover and its menu offer, header first, so a caller can find one by intent.
    public var commands: [MenuBarCommand] {
        let action: [MenuBarCommand] =
            if case .status(let status) = header, let command = status.action { [command] } else { [] }
        let rows =
            ([lastDictation].compactMap(\.self) + clips).flatMap { [$0.insert, $0.copy] }
            + learned.map(\.undo)
        let menu = items.compactMap { if case .command(let command) = $0 { command } else { nil } }
        return action + buttons.map(\.command) + rows + menu
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
            icon: icon(
                for: state.activity, failure: state.failure, dictationEnabled: state.features.dictation),
            statusLine: statusLine,
            emphasis: emphasis,
            accessibilityLabel: spokenForm(of: statusLine),
            clipboardCaptureEnabled: state.features.clipboard,
            header: header(for: state, statusLine: statusLine),
            buttons: buttons(for: state),
            lastDictation: lastDictation(for: state),
            clips: clipRows(for: state),
            learned: learnedRows(for: state),
            items: items(for: state, statusLine: statusLine, emphasis: emphasis)
        )
    }

    // MARK: The icon

    /// States differ at a glance, so the bar alone says whether the microphone is live or text arrived.
    static func icon(
        for activity: DictationActivity, failure: FailurePresentation?, dictationEnabled: Bool = true
    ) -> MenuBarIcon {
        if let failure { return icon(for: failure) }
        guard dictationEnabled else { return .symbol("mic.slash") }
        return switch activity {
        case .idle: .mark
        case .listening: .symbol("mic.fill")
        case .working: .symbol("sparkles")
        case .inserted: .symbol("checkmark")
        case .partial: .symbol("exclamationmark.circle")
        case .unconfirmed: .symbol("questionmark.circle")
        case .copied: .symbol("doc.on.clipboard")
        case .discarded: .symbol("trash")
        case .executed: .symbol("checkmark.circle")
        }
    }

    /// A failure's glyph differs by shape from every activity, so it never looks like rest or success.
    static func icon(for failure: FailurePresentation) -> MenuBarIcon {
        if failure.placement == .menuBar { return .symbol("exclamationmark.triangle.fill") }
        return failure.severity == .informational ? .symbol("info.circle") : .symbol("xmark.circle")
    }

    // MARK: The status line

    /// What is happening, failure first, and setting up above resting.
    static func statusLine(for state: MenuBarState) -> String {
        if let failure = state.failure { return failure.headline }

        // Above the model and a resting activity, below a failure and a live dictation, which it waits for.
        if !isBusy(state.activity), let updating = updateLine(for: state.updateProgress) { return updating }

        switch state.speechModel {
        case .downloading(let fraction):
            guard let fraction else { return "Setting up…" }
            return "Setting up… \(percentage(of: fraction))%"
        case .loading:
            return loadEstimate(for: state)?.heading ?? "Getting ready…"
        case .loadFailed:
            return "Speech model didn't load"
        case .loadFailedAgain, .incomplete:
            return SpeechModelLoad.broken.status
        case .notInstalled:
            return SpeechModelLoad.missing.status
        case .ready:
            guard state.features.dictation else { return "Dictation off" }
            return switch state.activity {
            case .idle: "Ready"
            case .listening: listeningLine(for: state.recordingAdvice, stopGesture: state.stopGesture)
            case .working: "Tidying up…"
            case .inserted: "Inserted"
            case .partial: MissedSpeech.line
            case .unconfirmed: "Inserted — not confirmed"
            case .copied: "Copied — press ⌘V"
            case .discarded: "Discarded"
            case .executed: "Done"
            }
        }
    }

    /// The load's estimate once it has run long enough to need one, and `nil` otherwise.
    static func loadEstimate(for state: MenuBarState) -> SpeechModelLoadEstimate? {
        guard state.speechModel == .loading else { return nil }
        return SpeechModelLoad.loading(elapsed: state.speechLoadElapsed).estimate
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
    public static func percentage(of fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// The status line as VoiceOver reads it, built from the same string so the two cannot drift.
    static func spokenForm(of statusLine: String) -> String {
        // An ellipsis means "still going" to the eye; to the ear it is a pause before what follows, or nothing.
        let spoken = statusLine.replacing("… ", with: ". ").filter { $0 != "…" }
        let stop = spoken.hasSuffix(".") ? "" : "."
        return "Uttrflow. \(spoken)\(stop)"
    }

    // MARK: The right-click menu

    /// What a right-click on the icon or the popover offers: the switches, the windows, and Quit.
    static func items(
        for state: MenuBarState, statusLine: String, emphasis: MenuBarEmphasis
    ) -> [MenuBarItem] {
        var items: [MenuBarItem] = [.status(text: statusLine, emphasis: emphasis), .separator]
        if let recovery = recovery(for: state) {
            items.append(.command(recovery))
            items.append(.separator)
        }
        items.append(contentsOf: featureItems(for: state.features, suggestionModel: state.suggestionModel))

        items.append(.separator)
        // The menu names the place and the app opens it.
        items.append(
            .command(
                MenuBarCommand(
                    title: "Open Uttrflow", intent: .open(.main(.home)),
                    shortcut: MenuBarShortcut(key: "0", modifiers: .command))))
        items.append(
            .command(
                MenuBarCommand(
                    title: "Settings…", intent: .open(.settings(.general)),
                    shortcut: MenuBarShortcut(key: ",", modifiers: .command))))

        if state.canCheckForUpdates {
            items.append(
                .command(MenuBarCommand(title: "Check for Updates…", intent: .checkForUpdates)))
        }

        items.append(.separator)
        items.append(
            .command(
                MenuBarCommand(
                    title: "Quit Uttrflow", intent: .quit,
                    shortcut: MenuBarShortcut(key: "q", modifiers: .command))))
        return items
    }

    /// The three switches, always all three, so turning one off never hides another.
    static func featureItems(
        for features: MenuBarFeatures, suggestionModel: SuggestionModelReadiness = .notAsked
    ) -> [MenuBarItem] {
        [.sectionHeader("Turn on and off")]
            + MenuBarFeature.allCases.map { feature in
                let isOn = features.isOn(feature)
                return .command(
                    MenuBarCommand(
                        title: title(of: feature, isOn: isOn, suggestionModel: suggestionModel),
                        intent: .setFeature(feature, isOn: !isOn),
                        isChecked: isOn))
            }
    }

    /// A switch's name, followed for AI suggestions that are on by what their model is waiting on.
    static func title(
        of feature: MenuBarFeature, isOn: Bool, suggestionModel: SuggestionModelReadiness
    ) -> String {
        let name = feature.isBeta ? "\(feature.title), \(BetaFeature.label)" : feature.title
        guard feature == .suggestions, isOn, let headline = suggestionModel.headline else {
            return name
        }
        return "\(name) — \(headline)"
    }

    /// What a recording says about itself: how to finish when releasing the keys does not, and a countdown near its cap.
    static func listeningLine(for advice: DictationAdvice, stopGesture: StopGesture = .letGo) -> String {
        let instruction: String? =
            switch stopGesture {
            case .pressAgain, .pressAgainHandsFree: stopGesture.recordingLine
            case .letGo, .clickAgain: nil
            }
        let details = [instruction, RemainingTime.phrase(for: advice)].compactMap(\.self)
        guard !details.isEmpty else { return "Listening…" }
        return "Listening… \(details.joined(separator: ", "))"
    }

    /// Whether the microphone is open, and so whether Stop must be offered. Never while working.
    static func isDictating(in state: MenuBarState) -> Bool {
        state.activity == .listening
    }

    /// Greyed for all three reasons dictation cannot begin, since a dead item reads as broken.
    static func canStartDictation(in state: MenuBarState) -> Bool {
        guard state.features.dictation else { return false }
        guard state.failure?.severity != .blocking else { return false }
        guard state.speechModel == .ready else { return false }
        return switch state.activity {
        case .idle, .inserted, .partial, .unconfirmed, .copied, .discarded, .executed: true
        case .listening, .working: false
        }
    }

    /// The reload or download a speech model that cannot dictate needs, offered wherever no failure brings its own fix.
    static func setupAction(for speechModel: SpeechModelReadiness) -> FailureAction? {
        guard let recovery = speechModel.recovery else { return nil }
        return FailureAction(title: FailurePresenter.title(for: recovery), recovery: recovery)
    }

    static func isBusy(_ activity: DictationActivity) -> Bool {
        switch activity {
        case .listening, .working: true
        case .idle, .inserted, .partial, .unconfirmed, .copied, .discarded, .executed: false
        }
    }

    /// The banner button's words, plus the ellipsis macOS puts on anything that opens something first.
    static func menuTitle(for action: FailureAction) -> String {
        switch action.recovery {
        case .openSystemSettings: "\(action.title)…"
        case .retry, .downloadSpeechModel, .pasteManually, .showHistory, .retryFromRecording,
            .restoreRecording, .copyTranscript:
            action.title
        }
    }
}

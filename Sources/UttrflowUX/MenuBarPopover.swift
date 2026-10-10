// The menu bar popover: its header, its round buttons and its two short lists.

import UttrflowClipboard
import UttrflowCore

// MARK: - What the popover is

/// The popover's top line: how to talk while nothing else needs saying, and what is happening otherwise.
public enum MenuBarHeader: Sendable, Equatable {
    case hint(MenuBarHint)
    case status(MenuBarStatus)
}

/// "hold ⌃⌥ to talk", in three parts so the keys can sit on a keycap.
public struct MenuBarHint: Sendable, Equatable {
    /// "hold" or "press", following how the shortcut is set up.
    public let verb: String
    /// The bound shortcut as one run of glyphs.
    public let keys: String
    public let trail: String

    public init(verb: String, keys: String, trail: String = "to talk") {
        self.verb = verb
        self.keys = keys
        self.trail = trail
    }
}

/// How far along something the header is waiting on has got.
public enum MenuBarProgress: Sendable, Equatable {
    /// Between zero and one.
    case fraction(Double)
    /// Under way, with no way to say how far; drawn as a sliding bar.
    case indeterminate
}

/// A header that says what is happening, with the one thing to do about it.
public struct MenuBarStatus: Sendable, Equatable {
    public let title: String
    public let detail: String?
    /// The dot's colour: teal at work, red while listening, amber when something needs the user.
    public let emphasis: MenuBarEmphasis
    public let progress: MenuBarProgress?
    /// The one fix, drawn as a pill beside the title.
    public let action: MenuBarCommand?
    /// The pill's colour, which is amber for a repair and teal for a first download.
    public let actionEmphasis: MenuBarEmphasis

    public init(
        title: String, detail: String? = nil, emphasis: MenuBarEmphasis = .normal,
        progress: MenuBarProgress? = nil, action: MenuBarCommand? = nil,
        actionEmphasis: MenuBarEmphasis = .normal
    ) {
        self.title = title
        self.detail = detail
        self.emphasis = emphasis
        self.progress = progress
        self.action = action
        self.actionEmphasis = actionEmphasis
    }
}

/// One of the popover's round buttons.
public struct MenuBarButton: Sendable, Equatable {
    /// SF Symbol drawn in the disc.
    public let symbolName: String
    /// The white disc, which only Talk wears.
    public let isPrimary: Bool
    /// What it does and its label, with whether it may.
    public let command: MenuBarCommand

    public init(symbolName: String, isPrimary: Bool = false, command: MenuBarCommand) {
        self.symbolName = symbolName
        self.isPrimary = isPrimary
        self.command = command
    }
}

/// A one-line row: a click pastes it at the cursor, Option-click or the row's menu copies it.
public struct MenuBarRow: Sendable, Equatable {
    /// The row's words, cut to one line by the view.
    public let title: String
    /// The whole of it, absent for a secret, which the row says as little about as it can.
    public let tooltip: String?
    public let insert: MenuBarCommand
    public let copy: MenuBarCommand

    public init(title: String, tooltip: String?, insert: MenuBarCommand, copy: MenuBarCommand) {
        self.title = title
        self.tooltip = tooltip
        self.insert = insert
        self.copy = copy
    }
}

/// A word the dictionary just learned, where it came from, and the Undo that removes and refuses it.
public struct MenuBarLearnedRow: Sendable, Equatable {
    public let word: String
    /// "from a correction" or "from the screen".
    public let source: String
    public let undo: MenuBarCommand

    public init(word: String, source: String, undo: MenuBarCommand) {
        self.word = word
        self.source = source
        self.undo = undo
    }
}

// MARK: - Deciding it

extension MenuBarPresenter {
    /// How many clips the popover lists.
    public static let clipCount = 5

    // MARK: The header

    /// The hint at rest, and a status the moment there is something else to say, in the status line's order.
    static func header(for state: MenuBarState, statusLine: String) -> MenuBarHeader {
        let fix = recovery(for: state)
        if let failure = state.failure {
            let emphasis: MenuBarEmphasis = failure.severity == .informational ? .normal : .attention
            return .status(
                MenuBarStatus(
                    title: statusLine, detail: failure.detail, emphasis: emphasis,
                    action: fix, actionEmphasis: emphasis))
        }
        if updateLine(for: state.updateProgress) != nil {
            return .status(MenuBarStatus(title: statusLine, progress: progress(of: state.updateProgress)))
        }
        if let setup = setupStatus(for: state, statusLine: statusLine, fix: fix) {
            return .status(setup)
        }
        switch state.activity {
        case .listening:
            return .status(MenuBarStatus(title: statusLine, emphasis: .live))
        case .working:
            return .status(MenuBarStatus(title: statusLine))
        case .idle, .inserted, .partial, .unconfirmed, .copied, .discarded, .executed:
            break
        }
        if let notice = state.suggestionUnheard, state.features.suggestions {
            return .status(
                MenuBarStatus(title: "AI suggestions paused", detail: notice, emphasis: .attention))
        }
        if state.features.suggestions, let status = suggestionStatus(state.suggestionRuntime) {
            return .status(status)
        }
        if state.shortcutUnheard != nil, state.features.dictation {
            return .status(
                MenuBarStatus(
                    title: "Shortcut can’t be heard", detail: state.shortcutUnheard,
                    emphasis: .attention))
        }
        return .hint(hint(for: state))
    }

    private static func suggestionStatus(_ runtime: SuggestionRuntimeStatus) -> MenuBarStatus? {
        let detail: String
        switch runtime {
        case .idle, .starting, .running:
            return nil
        case .tapResting:
            detail = "The key tap is restarting. Suggestions will resume automatically."
        case .restarting:
            detail = "Suggestions are restarting and will resume automatically."
        case .secureInputBlocked:
            detail = "A secure input field is active. Suggestions resume when you leave it."
        case .accessibilityDenied:
            detail = SuggestionRuntimeStatus.accessibilityDeniedMessage
        case .tapFailed:
            detail =
                "Allow Uttrflow to monitor input in Privacy & Security, then turn suggestions off and on again."
        case .corpusFailed:
            detail =
                "The suggestion corpus could not be opened. Check its file access, then turn suggestions off and on again."
        }
        return MenuBarStatus(title: "AI suggestions paused", detail: detail, emphasis: .attention)
    }

    /// Each speech-model state, with the words and the one action its design gives it.
    static func setupStatus(
        for state: MenuBarState, statusLine: String, fix: MenuBarCommand?
    ) -> MenuBarStatus? {
        switch state.speechModel {
        case .ready:
            return nil
        case .downloading(let fraction):
            return MenuBarStatus(
                title: statusLine, detail: "Downloading the speech model",
                progress: fraction.map { .fraction(min(max($0, 0), 1)) } ?? .indeterminate)
        case .loading:
            return MenuBarStatus(
                title: statusLine, detail: "Loading the speech model",
                progress: loadEstimate(for: state).map { .fraction($0.fraction) } ?? .indeterminate)
        case .loadFailed:
            return MenuBarStatus(
                title: "Model didn’t load", detail: "Nothing was lost", emphasis: .attention,
                action: fix, actionEmphasis: .attention)
        case .loadFailedAgain, .incomplete:
            return MenuBarStatus(
                title: "Model is damaged", detail: "Download it again to repair it",
                emphasis: .attention, action: fix, actionEmphasis: .attention)
        case .notInstalled:
            let offline = "works offline after"
            return MenuBarStatus(
                title: "Speech model needed",
                detail: state.speechModelBytes.map { "\(size(of: $0)) · \(offline)" }
                    ?? "Works offline after",
                emphasis: .attention, action: fix, actionEmphasis: .normal)
        }
    }

    /// The header's pill: the failure's own fix, else the model download, in the words the design uses.
    static func recovery(for state: MenuBarState) -> MenuBarCommand? {
        if let action = state.failure?.action {
            return MenuBarCommand(title: menuTitle(for: action), intent: .recover(action.recovery))
        }
        guard let setup = setupAction(for: state.speechModel) else { return nil }
        let title =
            switch state.speechModel {
            case .loadFailed: "Try again"
            case .loadFailedAgain, .incomplete: "Download again"
            case .ready, .downloading, .loading, .notInstalled: "Download"
            }
        return MenuBarCommand(title: title, intent: .recover(setup.recovery))
    }

    /// An update's bar: a fraction while it downloads, sliding while it checks or installs.
    static func progress(of update: UpdateProgress) -> MenuBarProgress? {
        switch update {
        case .idle, .readyToInstall: nil
        case .checking, .installing: .indeterminate
        case .downloading(let fraction): fraction.map { .fraction(min(max($0, 0), 1)) } ?? .indeterminate
        }
    }

    /// The talk hint with the shortcut the user actually bound.
    static func hint(for state: MenuBarState) -> MenuBarHint {
        let binding = state.shortcuts.first(for: .dictate) ?? .functionHold
        return MenuBarHint(
            verb: state.activation == .holdToTalk ? "hold" : "press",
            keys: SettingsShortcut.compact(binding))
    }

    /// Bytes in decimal megabytes or gigabytes, rounded up so a download is never undersold.
    static func size(of bytes: Int64) -> String {
        let bytes = max(bytes, 0)
        let megabytes = bytes / 1_000_000 + (bytes % 1_000_000 == 0 ? 0 : 1)
        guard megabytes >= 1_000 else { return "\(megabytes) MB" }
        let tenths = megabytes / 100 + (megabytes % 100 == 0 ? 0 : 1)
        return "\(tenths / 10).\(tenths % 10) GB"
    }

    // MARK: The buttons

    /// Talk, Clipboard, Settings and Home, each greyed rather than hidden when it cannot act.
    static func buttons(for state: MenuBarState) -> [MenuBarButton] {
        let dictating = isDictating(in: state)
        return [
            // A toggle, so a dictation begun here has a way to end here.
            MenuBarButton(
                symbolName: dictating ? "stop.fill" : "mic", isPrimary: true,
                command: MenuBarCommand(
                    title: dictating ? "Stop" : "Talk",
                    intent: dictating ? .stopDictation : .startDictation,
                    shortcut: MenuBarShortcut.forBinding(state.shortcuts.first(for: .dictate)),
                    isEnabled: dictating || canStartDictation(in: state))),
            MenuBarButton(
                symbolName: "clipboard",
                command: MenuBarCommand(
                    title: "Clipboard", intent: .openClipboard,
                    shortcut: state.unarmedShortcuts.contains(.clipboard)
                        ? nil
                        : MenuBarShortcut.forBinding(state.shortcuts.first(for: .clipboard)),
                    isEnabled: state.features.clipboard)),
            MenuBarButton(
                symbolName: "gearshape",
                command: MenuBarCommand(title: "Settings", intent: .open(.settings(.general)))),
            MenuBarButton(
                symbolName: "square.grid.2x2",
                command: MenuBarCommand(title: "Home", intent: .open(.main(.home)))),
        ]
    }

    // MARK: The lists

    /// The newest dictation, absent rather than empty, since a greyed row says nothing.
    static func lastDictation(for state: MenuBarState) -> MenuBarRow? {
        guard let recent = state.recents.first else { return nil }
        return row(
            title: recent.title, tooltip: recent.isSecret ? nil : recent.fullText,
            insert: .insertRecent(id: recent.id),
            copy: .copyRecent(id: recent.id), in: state)
    }

    /// The newest clips while the clipboard is on, a secret masked and a picture named by its size.
    static func clipRows(for state: MenuBarState) -> [MenuBarRow] {
        guard state.features.clipboard else { return [] }
        return state.clips.prefix(clipCount).map { clip in
            let isSecret = clip.kind == .secret
            return row(
                title: title(of: clip), tooltip: isSecret ? nil : clip.text,
                insert: .insertClip(id: clip.id), copy: .copyClip(id: clip.id), in: state)
        }
    }

    /// A clip's one line: the mask for a secret, the size for a picture, else its first line.
    static func title(of clip: Clip) -> String {
        if clip.kind == .secret { return PanelPresenter.mask }
        if let image = clip.image, clip.summary.isEmpty { return "Picture · \(image.dimensions)" }
        return clip.summary
    }

    /// How many learned words the popover lists.
    public static let learnedCount = 5

    /// The newest learned words, each with an Undo that a running dictation does not race.
    static func learnedRows(for state: MenuBarState) -> [MenuBarLearnedRow] {
        state.learned.prefix(learnedCount).map { word in
            MenuBarLearnedRow(
                word: word.word, source: word.source,
                undo: MenuBarCommand(
                    title: "Undo", intent: .undoLearnedWord(id: word.id),
                    isEnabled: !isBusy(state.activity),
                    tooltip: "Remove “\(word.word)” and stop learning it"))
        }
    }

    /// A row whose two commands are greyed while a dictation runs, which a paste would race.
    private static func row(
        title: String, tooltip: String?, insert: MenuBarIntent, copy: MenuBarIntent,
        in state: MenuBarState
    ) -> MenuBarRow {
        let isEnabled = !isBusy(state.activity)
        return MenuBarRow(
            title: title, tooltip: tooltip,
            insert: MenuBarCommand(title: "Paste", intent: insert, isEnabled: isEnabled, tooltip: tooltip),
            copy: MenuBarCommand(title: "Copy", intent: copy, isEnabled: isEnabled, tooltip: tooltip))
    }
}

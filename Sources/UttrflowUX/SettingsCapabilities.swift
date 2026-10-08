// What this Mac can do, passed in so the settings screens can be tested on a Mac that can.
public import UttrflowCore
public import UttrflowSettings

/// What macOS does when the user presses the Globe or Fn key.
public enum GlobeKeyAction: Sendable, Equatable {
    case doNothing
    case changeInputSource
    case showEmojiAndSymbols
    case startDictation
    case unknown

    /// Maps the value macOS stores in `AppleFnUsageType` to its Keyboard setting.
    public init(rawValue: Int?) {
        switch rawValue {
        case 0: self = .doNothing
        case 1: self = .changeInputSource
        case 2: self = .showEmojiAndSymbols
        case 3: self = .startDictation
        default: self = .unknown
        }
    }

    /// The action name shown when Fn could also trigger macOS.
    public var title: String {
        switch self {
        case .doNothing: "Do Nothing"
        case .changeInputSource: "Change Input Source"
        case .showEmojiAndSymbols: "Show Emoji & Symbols"
        case .startDictation: "Start Dictation"
        case .unknown: "an unknown action"
        }
    }

    /// The warning shown when a hold-Fn shortcut would also trigger macOS.
    public var warning: String? {
        guard self != .doNothing else { return nil }
        return
            "macOS is set to \(title) when you press the Globe key. Holding fn for Uttrflow can trigger both actions. Set System Settings → Keyboard → ‘Press 🌐 key to’ to Do Nothing."
    }
}

/// What this particular Mac can do, passed in so every refusal is testable on a machine that can.
public struct SettingsCapabilities: Sendable, Equatable {
    /// What macOS will do with Uttrflow at the next login, including nothing for want of a login item.
    public var launchAtLogin: LaunchAtLoginStatus

    /// Whether there is anywhere to play the start-of-recording cue.
    public var canPlayRecordingSound: Bool

    /// What this build calls itself, e.g. "0.2.2 (5)"; passed in because this module has no bundle.
    public var versionDescription: String?

    /// Whether this build has an update feed; false without `SUFeedURL` or `SUPublicEDKey`.
    public var canCheckForUpdates: Bool

    /// The clean-up engines above the floor that are usable now; the floor itself is always ready.
    public var readyTransformers: Set<TransformerKind>

    /// Apple's typed availability, so the tidying setting can distinguish a fix from a wait or a limit.
    public var foundationModelAvailability: TransformerAvailability?

    /// Typed answers retained from the same probe that builds ``readyTransformers``.
    public var transformerAvailability: [TransformerKind: TransformerAvailability]

    /// How far along the model tab-to-complete needs is, so the screen can say why it is silent.
    public var suggestionModel: SuggestionModelReadiness

    /// Whether the suggestions key tap is starting or why it stopped.
    public var suggestionRuntime: SuggestionRuntimeStatus

    /// Shortcuts the app could not claim, each with the refusal, so a row says why its key does nothing.
    public var unarmedShortcuts: [ShortcutAction: HotkeyError]

    /// Whether clipboard capture is within its temporary pause window.
    public var clipboardCapturePaused: Bool

    /// What macOS does when the Globe or Fn key is pressed by itself.
    public var globeKeyAction: GlobeKeyAction

    /// The input devices present, as UID and name, for the microphone choice.
    public var microphones: [SettingsMicrophone]

    /// Builds the answers; updates and the version default to absent.
    public init(
        launchAtLogin: LaunchAtLoginStatus,
        canPlayRecordingSound: Bool,
        canCheckForUpdates: Bool = false,
        versionDescription: String? = nil,
        readyTransformers: Set<TransformerKind>,
        foundationModelAvailability: TransformerAvailability? = nil,
        transformerAvailability: [TransformerKind: TransformerAvailability] = [:],
        suggestionModel: SuggestionModelReadiness = .notAsked,
        suggestionRuntime: SuggestionRuntimeStatus = .idle,
        unarmedShortcuts: [ShortcutAction: HotkeyError] = [:],
        clipboardCapturePaused: Bool = false,
        globeKeyAction: GlobeKeyAction = .doNothing,
        microphones: [SettingsMicrophone] = []
    ) {
        self.launchAtLogin = launchAtLogin
        self.canPlayRecordingSound = canPlayRecordingSound
        self.canCheckForUpdates = canCheckForUpdates
        self.versionDescription = versionDescription
        self.readyTransformers = readyTransformers
        self.foundationModelAvailability = foundationModelAvailability
        self.transformerAvailability = transformerAvailability
        self.suggestionModel = suggestionModel
        self.suggestionRuntime = suggestionRuntime
        self.unarmedShortcuts = unarmedShortcuts
        self.clipboardCapturePaused = clipboardCapturePaused
        self.globeKeyAction = globeKeyAction
        self.microphones = microphones
    }

    /// A Mac that can do everything: the start of a real probe, and a test's default.
    public static let everything = SettingsCapabilities(
        launchAtLogin: .enabled,
        canPlayRecordingSound: true,
        canCheckForUpdates: true,
        versionDescription: "1.0.0 (1)",
        readyTransformers: Set(TransformerKind.selectable),
        suggestionModel: .ready
    )

    /// Whether anything above the floor can tidy text; the floor is excluded, or this is true everywhere.
    public var canTidyBeyondTheFloor: Bool {
        readyTransformers.contains { $0 != SettingsEngines.floor }
    }

    /// Warns only when the selected shortcut holds Fn by itself.
    public func globeKeyWarning(for binding: HotkeyBinding) -> String? {
        guard binding.isFunctionHold else { return nil }
        return globeKeyAction.warning
    }
}

/// An input device as the microphone choice offers it: a stable UID and the name macOS gives it.
public struct SettingsMicrophone: Sendable, Equatable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Whether suggestions can currently receive keystrokes.
public enum SuggestionRuntimeStatus: Sendable, Equatable {
    case idle
    case starting
    case tapResting
    case restarting
    case running
    case secureInputBlocked
    case accessibilityDenied
    case tapFailed
    case corpusFailed
}

extension SuggestionRuntimeStatus {
    static let accessibilityDeniedMessage =
        String(
            localized: "Allow Uttrflow under Accessibility settings; return to resume suggestions.",
            comment: "Suggestion runtime status when Accessibility permission is denied")
}

/// How far along the model tab-to-complete needs is, so a switch that is on can say what it is doing.
public enum SuggestionModelReadiness: Sendable, Equatable {
    /// Nothing has been asked for yet, which is every Mac where the feature was never turned on.
    case notAsked
    /// Being fetched, with how far along it is when that is known.
    case downloading(fractionCompleted: Double?)
    /// On disk, being read into memory, which is the slow part on every launch after the first.
    case loading
    /// Loaded, so a completion can be judged.
    case ready
    /// Set aside while this Mac is short of memory, and loaded again once memory has stayed free for a while.
    case releasedForMemory
    /// The fetch or initial prepare failed; connection advice can help.
    case fetchFailed
    /// The weights are on disk, but reading them into memory failed.
    case loadFailed
    /// A failed fetch, for callers that still use the earlier spelling.
    case failed

    /// What the model is doing in a few words, the same in Settings and the menu bar, or nothing when it is ready or not asked for.
    public var headline: String? {
        switch self {
        case .notAsked, .ready: nil
        case .downloading(let fraction):
            fraction.map { "Getting ready — \(MenuBarPresenter.percentage(of: $0))%" } ?? "Getting ready"
        case .loading: "Getting ready"
        case .releasedForMemory: "Paused to free memory"
        case .fetchFailed, .failed: "The model could not be fetched"
        case .loadFailed: "The model could not be loaded"
        }
    }
}

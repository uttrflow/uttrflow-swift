public import UttrflowCore
public import UttrflowPredict

// The user's choices as one value, and the forgiving decoding that keeps them.
/// Every choice the user has made, as one value. See `Docs/settings-decoding.md`.
public struct Settings: Sendable, Equatable, Codable {
    /// Which implementations the pipeline runs.
    public var engines: EngineConfiguration

    /// Who the user is and how they write.
    public var profile: UserProfile

    /// Which clean-up steps run, so a user can switch one off and see what it was doing.
    public var cleaning: CleaningSteps

    /// The apps the user has told Uttrflow to treat as somewhere other than the table says.
    public var destinations: DestinationOverrides

    /// Every shortcut the user has, by what it is for. See `Docs/shortcuts.md`.
    public var shortcuts: ShortcutSet

    /// Whether the dictation shortcut is held down or pressed twice.
    public var hotkeyActivation: HotkeyActivation

    /// Whether double-tapping the held Dictate keys keeps the microphone open until they are tapped again.
    public var handsFreeEnabled: Bool

    /// How long two Dictate taps may be apart to start or stop hands-free dictation.
    public var handsFreeDoubleTapMilliseconds: Int

    /// How long a Dictate press may last and still count as a tap rather than a hold.
    public var handsFreeHoldMilliseconds: Int

    /// Seconds of quiet that end a recording no key is holding; 0, the default, leaves it to the stop gesture.
    public var endOnSilenceSeconds: Int

    /// Shortcuts that were a modifier held alone and are back to their defaults, until the user chooses again.
    public var shortcutsReturnedToDefault: Set<ShortcutAction>

    /// The dictation shortcut, which is ``shortcuts`` seen from the one angle most screens want.
    public var hotkey: HotkeyBinding {
        get { shortcuts.first(for: .dictate) ?? .functionHold }
        set { shortcuts.replace(at: 0, with: newValue, for: .dictate) }
    }

    /// The clipboard shortcut the same way, which may be nothing at all.
    public var clipboardHotkey: HotkeyBinding? {
        get { shortcuts.first(for: .clipboard) }
        set {
            guard let newValue else { return shortcuts.remove(at: 0, from: .clipboard) }
            shortcuts.replace(at: 0, with: newValue, for: .clipboard)
        }
    }

    /// Whether dictation answers at all: off, the shortcut is released and the floating button hidden.
    public var dictationEnabled: Bool

    /// Whether copies are recorded and the clipboard shortcut claimed.
    public var clipboardEnabled: Bool

    /// Whether the floating button is on screen at all.
    public var showsFloatingButton: Bool

    /// Which screen edge the floating button is parked on.
    public var floatingButtonAnchor: DockAnchor

    /// Whether the button collapses to a grip until the pointer approaches it.
    public var shrinksToGripWhenIdle: Bool

    /// Whether the main window gets out of the way, so the user can see what they dictate into.
    public var minimisesWhileDictating: Bool

    /// Whether recording starts with an audible cue.
    public var playsSoundWhenRecordingStarts: Bool

    /// Whether macOS launches Uttrflow when the user logs in.
    public var opensAtLogin: Bool

    /// Whether Sparkle checks for releases on its own.
    public var checksForUpdatesAutomatically: Bool

    /// Whether a found update installs itself or waits to be asked; `UpdateGate` picks the moment.
    public var installsUpdatesAutomatically: Bool

    /// Whether counts and timings are sent, tied to the signed-in account. See `Docs/account-telemetry.md`.
    public var sharesUsageStatistics: Bool
    /// Whether crash and hang reports go to Uttrflow; off until the user turns it on. See `Docs/crash-reporting.md`.
    public var sendsCrashReports: Bool

    /// Whether the interface is drawn light, dark, or however the Mac is set.
    public var appearance: AppAppearance

    /// How many days finished text is kept before it is deleted automatically; ``keepAlwaysDays`` keeps it.
    public var transcriptRetentionDays: Int

    /// How many days an unkept clip survives; a clip with an alias, category or pin has no clock.
    public var clipboardRetentionDays: Int

    /// Everything the user has decided about tab-to-complete.
    public var suggestions: SuggestionPreferences

    /// The input device dictation opens, by its stable UID; nil follows the system default.
    public var microphoneUID: String?

    /// How much of the front application a dictation reads: its name only, or the text around the caret too.
    public var contextLevel: ContextLevel

    /// Takes the shipped default for anything the caller does not choose.
    public init(
        engines: EngineConfiguration = .default,
        profile: UserProfile = .default,
        cleaning: CleaningSteps = .default,
        destinations: DestinationOverrides = .none,
        shortcuts: ShortcutSet = .default,
        hotkeyActivation: HotkeyActivation = .holdToTalk,
        handsFreeEnabled: Bool = true,
        handsFreeDoubleTapMilliseconds: Int = 450,
        handsFreeHoldMilliseconds: Int = 200,
        endOnSilenceSeconds: Int = 0,
        shortcutsReturnedToDefault: Set<ShortcutAction> = [],
        dictationEnabled: Bool = true,
        clipboardEnabled: Bool = true,
        showsFloatingButton: Bool = true,
        floatingButtonAnchor: DockAnchor = .bottomRight,
        shrinksToGripWhenIdle: Bool = true,
        minimisesWhileDictating: Bool = true,
        playsSoundWhenRecordingStarts: Bool = true,
        opensAtLogin: Bool = true,
        checksForUpdatesAutomatically: Bool = true,
        installsUpdatesAutomatically: Bool = true,
        sharesUsageStatistics: Bool = false,
        sendsCrashReports: Bool = false,
        appearance: AppAppearance = .dark,
        transcriptRetentionDays: Int = Settings.defaultTranscriptRetentionDays,
        clipboardRetentionDays: Int = Settings.defaultRetentionDays,
        suggestions: SuggestionPreferences = .default,
        microphoneUID: String? = nil,
        contextLevel: ContextLevel = .nearCaret
    ) {
        self.engines = engines
        self.profile = profile
        self.cleaning = cleaning
        self.destinations = destinations
        self.shortcuts = shortcuts
        self.hotkeyActivation = hotkeyActivation
        self.handsFreeEnabled = handsFreeEnabled
        self.handsFreeDoubleTapMilliseconds = Self.validDoubleTapMilliseconds(
            handsFreeDoubleTapMilliseconds)
        self.handsFreeHoldMilliseconds = Self.validHoldMilliseconds(handsFreeHoldMilliseconds)
        self.endOnSilenceSeconds = SilenceStop(seconds: endOnSilenceSeconds) == nil ? 0 : endOnSilenceSeconds
        self.shortcutsReturnedToDefault = shortcutsReturnedToDefault
        self.dictationEnabled = dictationEnabled
        self.clipboardEnabled = clipboardEnabled
        self.showsFloatingButton = showsFloatingButton
        self.floatingButtonAnchor = floatingButtonAnchor
        self.shrinksToGripWhenIdle = shrinksToGripWhenIdle
        self.minimisesWhileDictating = minimisesWhileDictating
        self.playsSoundWhenRecordingStarts = playsSoundWhenRecordingStarts
        self.opensAtLogin = opensAtLogin
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.installsUpdatesAutomatically = installsUpdatesAutomatically
        self.sharesUsageStatistics = sharesUsageStatistics
        self.sendsCrashReports = sendsCrashReports
        self.appearance = appearance
        self.transcriptRetentionDays = transcriptRetentionDays
        self.clipboardRetentionDays = clipboardRetentionDays
        self.suggestions = suggestions
        self.microphoneUID = microphoneUID
        self.contextLevel = contextLevel
    }

    /// A week: how long an unkept clip lives unless the user chooses otherwise.
    public static let defaultRetentionDays = 7

    /// The period that stands for "keep until I delete it", longer than anything can be kept waiting.
    public static let keepAlwaysDays = RetentionWindow.keepAlwaysDays

    /// Bounds finite retention values read from settings files; the keep-always sentinel is separate.
    public static let maximumFiniteRetentionDays = 365

    /// Transcripts stay until the user deletes them or chooses a shorter period.
    public static let defaultTranscriptRetentionDays = keepAlwaysDays

    /// Accepted hands-free intervals, including the existing default.
    public static let handsFreeDoubleTapChoices = [450, 600, 800]

    /// Keeps decoded timing choices within the values the Settings UI offers.
    public static func validDoubleTapMilliseconds(_ value: Int) -> Int {
        handsFreeDoubleTapChoices.contains(value) ? value : 450
    }

    /// Accepted hold lengths, longest last, for presses that need longer to count as a tap.
    public static let handsFreeHoldChoices = [200, 300, 500]

    /// Keeps a decoded hold length within the values the Settings UI offers.
    static func validHoldMilliseconds(_ value: Int) -> Int {
        handsFreeHoldChoices.contains(value) ? value : 200
    }

    /// What a user gets before they configure anything.
    public static let `default` = Settings()

    /// The defaults an install onboarded on an earlier build keeps: ⌥Space, and transcripts kept for a week.
    public static let earlierInstall = Settings(
        shortcuts: .earlierDefault, transcriptRetentionDays: Settings.defaultRetentionDays)
}

extension Settings {
    /// The two fields shortcuts replaced, read once so a settings file written before them still opens.
    enum LegacyShortcutKeys: String, CodingKey {
        case hotkey
        case clipboardHotkey
    }

    /// The names the choices are stored under, which are fixed for the life of the format.
    enum CodingKeys: String, CodingKey {
        case engines
        case profile
        case cleaning
        case destinations
        case shortcuts
        case hotkeyActivation
        case handsFreeEnabled
        case handsFreeDoubleTapMilliseconds
        case handsFreeHoldMilliseconds
        case endOnSilenceSeconds
        case shortcutsReturnedToDefault
        case dictationEnabled
        case clipboardEnabled
        case showsFloatingButton
        case floatingButtonAnchor
        case shrinksToGripWhenIdle
        case minimisesWhileDictating
        case playsSoundWhenRecordingStarts
        case opensAtLogin
        case checksForUpdatesAutomatically
        case installsUpdatesAutomatically
        case sharesUsageStatistics
        case sendsCrashReports
        case appearance
        case transcriptRetentionDays
        case clipboardRetentionDays
        case suggestions
        case microphoneUID
        case contextLevel
    }

    /// Decodes field by field, defaulting anything missing or unreadable. See `Docs/settings-decoding.md`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let fallback = Settings.default
        self.init(
            engines: container.value(forKey: .engines, default: fallback.engines),
            profile: container.value(forKey: .profile, default: fallback.profile),
            cleaning: container.value(forKey: .cleaning, default: fallback.cleaning),
            destinations: container.value(forKey: .destinations, default: fallback.destinations),
            // A saved file with no dictation shortcut predates ⌃⌥ held, so it keeps ⌥Space.
            shortcuts: Settings.shortcuts(from: decoder, default: .earlierDefault),
            hotkeyActivation: container.value(
                forKey: .hotkeyActivation, default: fallback.hotkeyActivation
            ),
            handsFreeEnabled: container.value(
                forKey: .handsFreeEnabled, default: fallback.handsFreeEnabled),
            handsFreeDoubleTapMilliseconds: container.value(
                forKey: .handsFreeDoubleTapMilliseconds,
                default: fallback.handsFreeDoubleTapMilliseconds),
            handsFreeHoldMilliseconds: container.value(
                forKey: .handsFreeHoldMilliseconds, default: fallback.handsFreeHoldMilliseconds),
            endOnSilenceSeconds: container.value(
                forKey: .endOnSilenceSeconds, default: fallback.endOnSilenceSeconds),
            shortcutsReturnedToDefault: container.value(
                forKey: .shortcutsReturnedToDefault, default: fallback.shortcutsReturnedToDefault
            ).union(Settings.shortcutsReturned(from: decoder)),
            dictationEnabled: container.value(
                forKey: .dictationEnabled, default: fallback.dictationEnabled),
            clipboardEnabled: container.value(
                forKey: .clipboardEnabled, default: fallback.clipboardEnabled),
            showsFloatingButton: container.value(
                forKey: .showsFloatingButton, default: fallback.showsFloatingButton
            ),
            floatingButtonAnchor: container.value(
                forKey: .floatingButtonAnchor, default: fallback.floatingButtonAnchor
            ),
            shrinksToGripWhenIdle: container.value(
                forKey: .shrinksToGripWhenIdle, default: fallback.shrinksToGripWhenIdle
            ),
            minimisesWhileDictating: container.value(
                forKey: .minimisesWhileDictating, default: fallback.minimisesWhileDictating
            ),
            playsSoundWhenRecordingStarts: container.value(
                forKey: .playsSoundWhenRecordingStarts,
                default: fallback.playsSoundWhenRecordingStarts
            ),
            opensAtLogin: container.value(forKey: .opensAtLogin, default: fallback.opensAtLogin),
            checksForUpdatesAutomatically: container.value(
                forKey: .checksForUpdatesAutomatically,
                default: fallback.checksForUpdatesAutomatically
            ),
            installsUpdatesAutomatically: container.value(
                forKey: .installsUpdatesAutomatically,
                default: fallback.installsUpdatesAutomatically
            ),
            sharesUsageStatistics: container.value(
                forKey: .sharesUsageStatistics, default: fallback.sharesUsageStatistics
            ),
            sendsCrashReports: container.value(
                forKey: .sendsCrashReports, default: fallback.sendsCrashReports),
            appearance: container.value(forKey: .appearance, default: fallback.appearance),
            transcriptRetentionDays: Settings.retention(
                container.value(
                    forKey: .transcriptRetentionDays, default: fallback.transcriptRetentionDays
                ),
                default: fallback.transcriptRetentionDays, keepsAlways: true
            ),
            clipboardRetentionDays: Settings.retention(
                container.value(
                    forKey: .clipboardRetentionDays, default: fallback.clipboardRetentionDays
                ),
                default: fallback.clipboardRetentionDays
            ),
            suggestions: container.value(forKey: .suggestions, default: fallback.suggestions),
            microphoneUID: (try? container.decodeIfPresent(String.self, forKey: .microphoneUID)) ?? nil,
            contextLevel: container.value(forKey: .contextLevel, default: fallback.contextLevel)
        )
    }

    /// The stored retention, or `fallback` when it is invalid. Finite periods cannot exceed a year.
    static func retention(_ days: Int, default fallback: Int, keepsAlways: Bool = false) -> Int {
        guard days > 0 else { return fallback }
        guard keepsAlways, days == keepAlwaysDays else {
            return min(days, maximumFiniteRetentionDays)
        }
        return keepAlwaysDays
    }

    /// The dictation shortcut, or Option+Space when macOS could never deliver it.
    static func shortcut(_ binding: HotkeyBinding) -> HotkeyBinding {
        binding.isDeliverable ? binding : .optionSpace
    }

    /// The actions this file bound only to a modifier held alone, which reading it has just put back to their defaults.
    static func shortcutsReturned(from decoder: any Decoder) -> Set<ShortcutAction> {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
            let stored = try? container.decodeIfPresent([String: [HotkeyBinding]].self, forKey: .shortcuts)
        {
            var bound: [ShortcutAction: [HotkeyBinding]] = [:]
            for (name, bindings) in stored {
                if let action = ShortcutAction(rawValue: name) { bound[action] = bindings }
            }
            return ShortcutSet.boundOnlyToBareModifiers(in: bound)
        }
        guard let legacy = try? decoder.container(keyedBy: LegacyShortcutKeys.self) else { return [] }
        let fields: [(LegacyShortcutKeys, ShortcutAction)] = [
            (.hotkey, .dictate), (.clipboardHotkey, .clipboard),
        ]
        return Set(
            fields.filter { key, _ in
                legacy.optionalValue(forKey: key, default: nil as HotkeyBinding?)?.isBareModifier == true
            }
            .map(\.1))
    }

    /// The shortcuts on disk, reading the two fields that came before them when they are all there is.
    static func shortcuts(from decoder: any Decoder, default fallback: ShortcutSet) -> ShortcutSet {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
            let stored = try? container.decodeIfPresent(ShortcutSet.self, forKey: .shortcuts),
            stored.isBound(.dictate)
        {
            return stored
        }
        guard let legacy = try? decoder.container(keyedBy: LegacyShortcutKeys.self) else {
            return fallback
        }
        // Written before shortcuts were a set: one dictation shortcut and maybe a clipboard one.
        let dictation = Settings.shortcut(
            legacy.value(forKey: .hotkey, default: fallback.first(for: .dictate) ?? .optionSpace))
        // Starts from the defaults, so upgrading brings the shortcuts this build added.
        var migrated = fallback
        migrated.replace(at: 0, with: dictation, for: .dictate)
        // Absent means the default, `null` means switched off, and unreadable means the default.
        let clipboard = legacy.optionalValue(
            forKey: .clipboardHotkey, default: fallback.first(for: .clipboard))
        // A clipboard shortcut that is the dictation one would fire both, so it is dropped.
        if let clipboard, clipboard.isDeliverable, clipboard != dictation {
            migrated.replace(at: 0, with: clipboard, for: .clipboard)
        } else if clipboard?.isBareModifier != true || fallback.first(for: .clipboard) == dictation {
            // Dropped, except a modifier held alone: this build refuses that choice, so it leaves the default in place.
            migrated.remove(at: 0, from: .clipboard)
        }
        return migrated
    }
}

/// Reads one settings field at a time, so one unreadable value costs the user only that value.
extension KeyedDecodingContainer {
    /// Reads one field, answering with `fallback` when it is absent or unreadable.
    fileprivate func value<T: Decodable>(forKey key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// Reads a field where absent and `null` mean different things. See `Docs/settings-decoding.md`.
    fileprivate func optionalValue<T: Decodable>(forKey key: Key, default fallback: T?) -> T? {
        guard contains(key) else { return fallback }
        do {
            // Caught by hand because `try?` would flatten "it threw" and "it decoded a null" into one `nil`.
            return try decodeIfPresent(T.self, forKey: key)
        } catch {
            return fallback
        }
    }
}

/// Reads and writes the user's choices; neither call fails, because the defaults always answer.
public protocol SettingsStore: Sendable {
    /// The stored settings, or the defaults when there are none to be had.
    func load() -> Settings

    /// Replaces everything stored with `settings`.
    func save(_ settings: Settings)
}

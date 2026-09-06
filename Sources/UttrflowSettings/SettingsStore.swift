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

    /// The shortcut that starts a dictation.
    public var hotkey: HotkeyBinding

    /// Whether that shortcut is held down or pressed twice.
    public var hotkeyActivation: HotkeyActivation

    /// The shortcut that opens the clipboard panel, or nothing. See `Docs/settings-decoding.md`.
    public var clipboardHotkey: HotkeyBinding?

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

    /// Whether a found update installs itself or waits to be asked; `UpdateGate` picks the moment.
    public var installsUpdatesAutomatically: Bool

    /// Whether the interface is drawn light, dark, or however the Mac is set.
    public var appearance: AppAppearance

    /// How many days finished text is kept before it is deleted automatically.
    public var transcriptRetentionDays: Int

    /// How many days an unkept clip survives; a clip with an alias, category or pin has no clock.
    public var clipboardRetentionDays: Int

    /// Everything the user has decided about tab-to-complete.
    public var suggestions: SuggestionPreferences

    /// Takes the shipped default for anything the caller does not choose.
    public init(
        engines: EngineConfiguration = .default,
        profile: UserProfile = .default,
        cleaning: CleaningSteps = .default,
        destinations: DestinationOverrides = .none,
        hotkey: HotkeyBinding = .optionSpace,
        hotkeyActivation: HotkeyActivation = .holdToTalk,
        clipboardHotkey: HotkeyBinding? = .shiftCommandV,
        showsFloatingButton: Bool = true,
        floatingButtonAnchor: DockAnchor = .bottomRight,
        shrinksToGripWhenIdle: Bool = true,
        minimisesWhileDictating: Bool = true,
        playsSoundWhenRecordingStarts: Bool = true,
        opensAtLogin: Bool = true,
        installsUpdatesAutomatically: Bool = true,
        appearance: AppAppearance = .dark,
        transcriptRetentionDays: Int = Settings.defaultRetentionDays,
        clipboardRetentionDays: Int = Settings.defaultRetentionDays,
        suggestions: SuggestionPreferences = .default
    ) {
        self.engines = engines
        self.profile = profile
        self.cleaning = cleaning
        self.destinations = destinations
        self.hotkey = hotkey
        self.hotkeyActivation = hotkeyActivation
        self.clipboardHotkey = clipboardHotkey
        self.showsFloatingButton = showsFloatingButton
        self.floatingButtonAnchor = floatingButtonAnchor
        self.shrinksToGripWhenIdle = shrinksToGripWhenIdle
        self.minimisesWhileDictating = minimisesWhileDictating
        self.playsSoundWhenRecordingStarts = playsSoundWhenRecordingStarts
        self.opensAtLogin = opensAtLogin
        self.installsUpdatesAutomatically = installsUpdatesAutomatically
        self.appearance = appearance
        self.transcriptRetentionDays = transcriptRetentionDays
        self.clipboardRetentionDays = clipboardRetentionDays
        self.suggestions = suggestions
    }

    /// A week: long enough to find yesterday's dictation, short enough not to hoard the user's words.
    public static let defaultRetentionDays = 7

    /// What a user gets before they configure anything.
    public static let `default` = Settings()
}

extension Settings {
    /// The names the choices are stored under, which are fixed for the life of the format.
    enum CodingKeys: String, CodingKey {
        case engines
        case profile
        case cleaning
        case destinations
        case hotkey
        case hotkeyActivation
        case clipboardHotkey
        case showsFloatingButton
        case floatingButtonAnchor
        case shrinksToGripWhenIdle
        case minimisesWhileDictating
        case playsSoundWhenRecordingStarts
        case opensAtLogin
        case installsUpdatesAutomatically
        case appearance
        case transcriptRetentionDays
        case clipboardRetentionDays
        case suggestions
    }

    /// Decodes field by field, defaulting anything missing or unreadable. See `Docs/settings-decoding.md`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let fallback = Settings.default
        // Resolved first because the clipboard shortcut is only valid relative to this one.
        let dictation = Settings.shortcut(
            container.value(forKey: .hotkey, default: fallback.hotkey)
        )
        self.init(
            engines: container.value(forKey: .engines, default: fallback.engines),
            profile: container.value(forKey: .profile, default: fallback.profile),
            cleaning: container.value(forKey: .cleaning, default: fallback.cleaning),
            destinations: container.value(forKey: .destinations, default: fallback.destinations),
            hotkey: dictation,
            hotkeyActivation: container.value(
                forKey: .hotkeyActivation, default: fallback.hotkeyActivation
            ),
            clipboardHotkey: Settings.clipboardShortcut(
                container.optionalValue(
                    forKey: .clipboardHotkey, default: fallback.clipboardHotkey
                ),
                alongside: dictation
            ),
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
            installsUpdatesAutomatically: container.value(
                forKey: .installsUpdatesAutomatically,
                default: fallback.installsUpdatesAutomatically
            ),
            appearance: container.value(forKey: .appearance, default: fallback.appearance),
            transcriptRetentionDays: Settings.retention(
                container.value(
                    forKey: .transcriptRetentionDays, default: fallback.transcriptRetentionDays
                )
            ),
            clipboardRetentionDays: Settings.retention(
                container.value(
                    forKey: .clipboardRetentionDays, default: fallback.clipboardRetentionDays
                )
            ),
            suggestions: container.value(forKey: .suggestions, default: fallback.suggestions)
        )
    }

    /// The stored retention, or the default when it is zero or less and would wipe the history at once.
    static func retention(_ days: Int) -> Int {
        days > 0 ? days : defaultRetentionDays
    }

    /// The dictation shortcut, or Option+Space when macOS could never deliver it.
    static func shortcut(_ binding: HotkeyBinding) -> HotkeyBinding {
        binding.isDeliverable ? binding : .optionSpace
    }

    /// The clipboard shortcut, or nothing when macOS cannot deliver it or `dictation` owns it.
    static func clipboardShortcut(
        _ binding: HotkeyBinding?, alongside dictation: HotkeyBinding
    ) -> HotkeyBinding? {
        guard let binding, binding.isDeliverable, binding != dictation else { return nil }
        return binding
    }
}

/// Reads one settings field at a time, so one unreadable value costs the user only that value.
extension KeyedDecodingContainer where Key == Settings.CodingKeys {
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

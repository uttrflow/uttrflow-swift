public import UttrflowCore
public import UttrflowPredict

/// Where the floating button parks itself.
///

/// Every choice the user has made, as one value.
///
/// One value rather than a scattering of keys: a screen can be handed the whole of the
/// configuration, compare it, and write it back in a single step, so a half-applied
/// change is not representable. Nothing here leaves the Mac.
public struct Settings: Sendable, Equatable, Codable {
    /// Which implementations the pipeline runs.
    public var engines: EngineConfiguration

    /// Who the user is and how they write.
    public var profile: UserProfile

    /// Whether the shortcut is held down or pressed twice.
    /// The shortcut itself, not merely how holding it behaves.
    public var hotkey: HotkeyBinding

    public var hotkeyActivation: HotkeyActivation

    /// The shortcut that opens the clipboard panel, or nothing if the user does not
    /// want one.
    ///
    /// Optional because "no clipboard shortcut" is a position a user can hold — the
    /// panel is still reachable from the menu bar — and because it is where a collision
    /// with ``hotkey`` lands. Two registrations of one combination both succeed and then
    /// both fire, which would start a dictation and open the panel on the same keypress;
    /// rather than silently move the clipboard key somewhere the user never chose,
    /// the collision resolves to nothing and says so on the shortcuts screen.
    public var clipboardHotkey: HotkeyBinding?

    /// Whether the floating button is on screen at all.
    public var showsFloatingButton: Bool

    /// Which screen edge the floating button is parked on.
    public var floatingButtonAnchor: DockAnchor

    /// Whether the button collapses to a grip until the pointer approaches it.
    public var shrinksToGripWhenIdle: Bool

    /// Whether the main window gets out of the way while a dictation is running, so
    /// the user can see the app they are dictating into.
    public var minimisesWhileDictating: Bool

    /// Whether recording starts with an audible cue.
    public var playsSoundWhenRecordingStarts: Bool

    /// Whether macOS launches Uttrflow when the user logs in.
    public var opensAtLogin: Bool

    /// Whether a found update installs itself, or waits to be asked.
    ///
    /// On by default, which is the choice that keeps the most people on a build that has
    /// the fixes. It is a setting rather than a policy because an update replaces the
    /// binary holding somebody's microphone and Accessibility grants, and a person who
    /// wants to know before that happens is not being unreasonable.
    ///
    /// Nothing is installed *while dictating* either way — see `UpdateGate`. This decides
    /// whether the user is asked first, not whether the moment is chosen carefully.
    public var installsUpdatesAutomatically: Bool

    /// Whether the interface is drawn light, dark, or however the Mac is set.
    public var appearance: AppAppearance

    /// How many days finished text is kept before it is deleted automatically.
    public var transcriptRetentionDays: Int

    /// How many days an unkept clip survives in the clipboard panel.
    ///
    /// Separate from ``transcriptRetentionDays`` because they are separate promises
    /// about separate things. Someone who keeps dictation transcripts for a day has said
    /// something about what Uttrflow writes down, not about their own clipboard, and
    /// folding the two together would quietly empty the panel on their behalf.
    ///
    /// It governs history alone. A clip with an alias, a category or a pin has no clock
    /// on it at all.
    public var clipboardRetentionDays: Int

    /// Everything the user has decided about tab-to-complete.
    public var suggestions: SuggestionPreferences

    public init(
        engines: EngineConfiguration = .default,
        profile: UserProfile = .default,
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

    /// A week: long enough to find yesterday's dictation, short enough that a user who
    /// never opens this screen is not quietly hoarding their own words.
    public static let defaultRetentionDays = 7

    /// What a user gets before they configure anything.
    public static let `default` = Settings()
}

extension Settings {
    enum CodingKeys: String, CodingKey {
        case engines
        case profile
        case hotkey
        case hotkeyActivation
        case clipboardHotkey
        case showsFloatingButton
        case floatingButtonAnchor
        case shrinksToGripWhenIdle
        case minimisesWhileDictating
        case playsSoundWhenRecordingStarts
        case opensAtLogin
        case appearance
        case transcriptRetentionDays
        case clipboardRetentionDays
        case suggestions
    }

    /// Decodes field by field, defaulting anything missing or unreadable.
    ///
    /// Synthesised decoding is all-or-nothing: one field a newer build added, or one a
    /// hand-edited preferences file mangled, and the user loses every other choice they
    /// ever made. Settings are worth less than the confidence that they survive, so a
    /// field that cannot be read is simply the field the user never changed.
    ///
    /// The same forgiveness runs the other way. A key this build no longer has a case
    /// for — `recordingRetentionDays`, which set the retention of audio Uttrflow never
    /// wrote to disk — is one keyed decoding is never asked for, so a blob an older
    /// build left behind still yields every choice that does still mean something.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let fallback = Settings.default
        // Resolved before the call rather than inside it because the clipboard shortcut
        // is only valid relative to this one, and the argument order of an initialiser
        // is not a place to hide a dependency between two of its arguments.
        let dictation = Settings.shortcut(
            container.value(forKey: .hotkey, default: fallback.hotkey)
        )
        self.init(
            engines: container.value(forKey: .engines, default: fallback.engines),
            profile: container.value(forKey: .profile, default: fallback.profile),
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

    /// A retention of zero or less would wipe the user's history the instant the app
    /// launched, so a value that says so is treated as a corrupt one.
    static func retention(_ days: Int) -> Int {
        days > 0 ? days : defaultRetentionDays
    }

    /// A shortcut macOS cannot deliver leaves the user with nothing to press, and until
    /// there is a screen for choosing another, nothing they can do about it either —
    /// the only way back is deleting the preferences file from a terminal. So a stored
    /// shortcut that cannot work is treated as a corrupt one, exactly as a retention of
    /// zero is, rather than being handed on to be refused at registration.
    ///
    /// Decoding cleanly is not the same as being usable: `{"keyCode": 49, "modifiers":
    /// []}` is a perfectly good ``HotkeyBinding`` and a shortcut that never fires.
    static func shortcut(_ binding: HotkeyBinding) -> HotkeyBinding {
        binding.isDeliverable ? binding : .optionSpace
    }

    /// The clipboard shortcut, or nothing when it cannot be honoured.
    ///
    /// Answers `nil` in the two cases where registering it would do harm rather than
    /// nothing: a combination macOS will not deliver, and the combination already
    /// spoken for by `dictation`. The second is the one worth naming — Carbon accepts
    /// both registrations of a single combination and then fires both, so a collision
    /// left in place starts a dictation *and* opens the panel on one keypress.
    ///
    /// It does not substitute a different key. A shortcut the user never chose, chosen
    /// for them because the one they did choose clashed, is a key they will press by
    /// accident somewhere else.
    static func clipboardShortcut(
        _ binding: HotkeyBinding?, alongside dictation: HotkeyBinding
    ) -> HotkeyBinding? {
        guard let binding, binding.isDeliverable, binding != dictation else { return nil }
        return binding
    }
}

extension KeyedDecodingContainer where Key == Settings.CodingKeys {
    /// Reads one field, answering with `fallback` when it is absent or unreadable.
    ///
    /// `try?` flattens the two ways a field can fail to arrive into the one `nil` that
    /// matters here: either way, the user never expressed a preference this build can
    /// act on, so the default is the honest answer.
    fileprivate func value<T: Decodable>(forKey key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// Reads a field whose absence and whose emptiness mean different things.
    ///
    /// ``value(forKey:default:)`` cannot be used for one: `decodeIfPresent` answers the
    /// same `nil` whether the key was missing or written as an explicit `null`, so a
    /// setting the user had deliberately switched off would come back as the default on
    /// the next launch — the shortcut they turned off returning by itself.
    ///
    /// The three cases are kept apart deliberately. Absent is "never chosen", and takes
    /// the default. `null` is a choice, and is honoured. Present-but-unreadable is
    /// neither, and takes the default for the reason ``init(from:)`` gives: a field
    /// nothing can read is a field the user never expressed a preference in.
    fileprivate func optionalValue<T: Decodable>(forKey key: Key, default fallback: T?) -> T? {
        guard contains(key) else { return fallback }
        do {
            // MEASURED FOOTGUN: `try?` flattens nested optionals, so
            // `try? decodeIfPresent(...)` collapses "it threw" and "it decoded a null"
            // into the one `nil` this method exists to tell apart — and does it
            // silently, with the right type and no warning. The error is caught by hand
            // for that reason.
            return try decodeIfPresent(T.self, forKey: key)
        } catch {
            return fallback
        }
    }
}

/// Reads and writes the user's choices.
///
/// Neither call can fail. Losing the app to an unreadable preferences file is worse
/// than starting from the defaults, so ``load()`` answers with them rather than
/// throwing, and every caller is spared a `catch` that has only one sensible body.
public protocol SettingsStore: Sendable {
    /// The stored settings, or the defaults when there are none to be had.
    func load() -> Settings

    func save(_ settings: Settings)
}

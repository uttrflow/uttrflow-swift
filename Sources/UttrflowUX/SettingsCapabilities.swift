// What this Mac can do, passed in so the settings screens can be tested on a Mac that can.
public import UttrflowCore
public import UttrflowSettings

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

    /// The speech engines whose model is present and usable right now.
    public var readySpeechEngines: Set<SpeechEngineKind>

    /// The clean-up engines above the floor that are usable now; the floor itself is always ready.
    public var readyTransformers: Set<TransformerKind>

    /// Builds the answers; updates and the version default to absent.
    public init(
        launchAtLogin: LaunchAtLoginStatus,
        canPlayRecordingSound: Bool,
        canCheckForUpdates: Bool = false,
        versionDescription: String? = nil,
        readySpeechEngines: Set<SpeechEngineKind>,
        readyTransformers: Set<TransformerKind>
    ) {
        self.launchAtLogin = launchAtLogin
        self.canPlayRecordingSound = canPlayRecordingSound
        self.canCheckForUpdates = canCheckForUpdates
        self.versionDescription = versionDescription
        self.readySpeechEngines = readySpeechEngines
        self.readyTransformers = readyTransformers
    }

    /// A Mac that can do everything: the start of a real probe, and a test's default.
    public static let everything = SettingsCapabilities(
        launchAtLogin: .enabled,
        canPlayRecordingSound: true,
        canCheckForUpdates: true,
        versionDescription: "1.0.0 (1)",
        readySpeechEngines: Set(SpeechEngineKind.allCases),
        readyTransformers: Set(TransformerKind.selectable)
    )

    /// Whether anything above the floor can tidy text; the floor is excluded, or this is true everywhere.
    public var canTidyBeyondTheFloor: Bool {
        readyTransformers.contains { $0 != SettingsEngines.floor }
    }
}

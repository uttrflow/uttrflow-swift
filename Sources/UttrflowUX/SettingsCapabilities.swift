public import UttrflowCore
public import UttrflowSettings

/// What this particular Mac can actually do, as far as this screen is concerned.
///
/// Every field exists because there is a real machine on which the answer is no: a
/// build run from the command line has no login item, a Mac with no output device has
/// nothing to play a cue through, and an engine whose model has not been downloaded
/// cannot transcribe. Passing the answers in rather than asking the system for them
/// keeps this module free of the platform, and lets every refusal be tested on a
/// machine that can in fact do the thing.
public struct SettingsCapabilities: Sendable, Equatable {
    /// What macOS will do with Uttrflow at the next login — including "nothing, because
    /// there is no login item to act on".
    public var launchAtLogin: LaunchAtLoginStatus

    /// Whether there is anywhere to play the start-of-recording cue.
    public var canPlayRecordingSound: Bool

    /// The speech engines whose model is present and usable right now.
    public var readySpeechEngines: Set<SpeechEngineKind>

    /// The clean-up engines above the floor that are usable right now. The floor
    /// itself is always ready, which is what makes it the floor.
    public var readyTransformers: Set<TransformerKind>

    public init(
        launchAtLogin: LaunchAtLoginStatus,
        canPlayRecordingSound: Bool,
        readySpeechEngines: Set<SpeechEngineKind>,
        readyTransformers: Set<TransformerKind>
    ) {
        self.launchAtLogin = launchAtLogin
        self.canPlayRecordingSound = canPlayRecordingSound
        self.readySpeechEngines = readySpeechEngines
        self.readyTransformers = readyTransformers
    }

    /// A Mac that can do everything. The starting point for a real probe, and what a
    /// test uses when the capability under examination is not the point of the test.
    public static let everything = SettingsCapabilities(
        launchAtLogin: .enabled,
        canPlayRecordingSound: true,
        readySpeechEngines: Set(SpeechEngineKind.allCases),
        readyTransformers: Set(TransformerKind.selectable)
    )

    /// Whether anything above the floor can tidy text on this Mac.
    ///
    /// The floor is excluded deliberately: it is always ready, so counting it would
    /// make this true everywhere and the standard level would never admit it had
    /// nothing extra to offer.
    public var canTidyBeyondTheFloor: Bool {
        readyTransformers.contains { $0 != SettingsEngines.floor }
    }
}

import CoreAudio
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

/// Asks this Mac what it can actually do.
///
/// The only file that turns a real machine into ``SettingsCapabilities``. Kept apart
/// from the screen so that every refusal the screen shows can be tested against a
/// made-up machine, and kept out of `UttrflowUX` so that module stays free of the
/// platform.
///
/// Excluded from the coverage gate: every line of it reads the state of the machine it
/// is running on, and a test machine can only ever report one of the answers.
extension SettingsCapabilities {
    /// What is knowable without waiting.
    ///
    /// Optimistic about tidying beyond the floor, and corrected by ``refreshed()`` a
    /// moment later: the on-device model will only say whether it is available
    /// asynchronously, and holding the window shut until it answers would be a worse
    /// trade than a control that is briefly operable on the few Macs where it is not.
    static func thisMac() -> SettingsCapabilities {
        SettingsCapabilities(
            launchAtLogin: LaunchAtLogin().status,
            canPlayRecordingSound: hasAudioOutput,
            canCheckForUpdates: UpdateController.isConfigured,
            versionDescription: versionDescription,
            readySpeechEngines: readySpeechEngines,
            readyTransformers: Set(TransformerKind.selectable))
    }

    /// The same answers, with the ones that had to be waited for.
    ///
    /// - Parameter profile: Who the user is, so an engine is asked whether it can help
    ///   with the language they actually speak.
    /// - Returns: Everything ``thisMac()`` knows, with the clean-up engines replaced by
    ///   the ones that answered that they could run.
    static func refreshed(for profile: UserProfile) async -> SettingsCapabilities {
        var capabilities = thisMac()
        capabilities.readyTransformers = await readyTransformers(for: profile)
        return capabilities
    }

    /// What this build calls itself, as "short (build)".
    ///
    /// Both halves, because they answer different questions: the short version is what a
    /// release is called, and the build number is what tells two builds of the same
    /// release apart — which is the difference that matters when somebody says an update
    /// did not take.
    private static var versionDescription: String? {
        let version = AppVersion.ofThisBuild
        guard version.isKnown else { return nil }
        return version.build == version.short ? version.short : version.full
    }

    /// Which engines could transcribe right now.
    ///
    /// The system recogniser needs no download, so it is always ready; the higher
    /// quality one is ready only once its model is on disk.
    private static var readySpeechEngines: Set<SpeechEngineKind> {
        var ready: Set<SpeechEngineKind> = [.appleSpeech]
        if FileSystemSpeechModelStore.whisperKit().isInstalled(.default) {
            ready.insert(.whisperKit)
        }
        return ready
    }

    /// Which clean-up engines could run right now.
    ///
    /// Asked of the transformers themselves rather than of a list kept here, so an
    /// engine added to the build appears without this file changing. The floor is added
    /// unconditionally because it is the one engine that cannot decline.
    ///
    /// The question is asked of the user's own first language rather than of nothing in
    /// particular: an engine that cannot handle the language they speak is of no use to
    /// them, whatever it can do in general.
    private static func readyTransformers(
        for profile: UserProfile
    ) async -> Set<TransformerKind> {
        let probe = TransformationRequest(
            transcription: Transcription(text: ""), profile: profile)
        var ready: Set<TransformerKind> = [SettingsEngines.floor]
        for engine in TextTransformers.all() {
            guard await engine.availability(for: probe).isAvailable else { continue }
            ready.insert(engine.kind)
        }
        return ready
    }

    /// Whether macOS has an output device to play a cue through.
    ///
    /// A Mac with its audio interface unplugged reports the unknown device id, and
    /// `NSSound.play()` on one returns false without saying why — which is exactly the
    /// switch that looks as though it works and never does.
    private static var hasAudioOutput: Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != AudioDeviceID(kAudioObjectUnknown)
    }
}

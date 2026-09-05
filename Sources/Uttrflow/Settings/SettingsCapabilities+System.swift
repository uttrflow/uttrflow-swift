// What this Mac can do, asked of the real machine.

import CoreAudio
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowSettings
import UttrflowSpeech
import UttrflowUX

/// Asks this Mac what it can do; the one file that turns a real machine into `SettingsCapabilities`.
extension SettingsCapabilities {
    /// What is knowable without waiting; optimistic about the model until `refreshed()` corrects it.
    static func thisMac() -> SettingsCapabilities {
        SettingsCapabilities(
            launchAtLogin: LaunchAtLogin().status,
            canPlayRecordingSound: hasAudioOutput,
            canCheckForUpdates: UpdateController.isConfigured,
            versionDescription: versionDescription,
            readySpeechEngines: readySpeechEngines,
            readyTransformers: Set(TransformerKind.selectable))
    }

    /// The same answers with the clean-up engines that answered they could run for `profile`'s language.
    static func refreshed(for profile: UserProfile) async -> SettingsCapabilities {
        var capabilities = thisMac()
        capabilities.readyTransformers = await readyTransformers(for: profile)
        return capabilities
    }

    /// What this build calls itself, as "short (build)", since two builds of one release differ.
    private static var versionDescription: String? {
        let version = AppVersion.ofThisBuild
        guard version.isKnown else { return nil }
        return version.build == version.short ? version.short : version.full
    }

    /// Which engines could transcribe right now; the higher quality one needs its model on disk.
    private static var readySpeechEngines: Set<SpeechEngineKind> {
        var ready: Set<SpeechEngineKind> = [.appleSpeech]
        if FileSystemSpeechModelStore.whisperKit().isInstalled(.default) {
            ready.insert(.whisperKit)
        }
        return ready
    }

    /// Which clean-up engines could run for the user's own first language, asked of the engines themselves.
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

    /// Whether macOS has an output device; `NSSound.play()` on none returns false without saying why.
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

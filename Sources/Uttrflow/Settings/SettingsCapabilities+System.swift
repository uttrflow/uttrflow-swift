// What this Mac can do, asked of the real machine.

import CoreAudio
import Foundation
import UttrflowAI
import UttrflowAudio
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
            readyTransformers: Set(TransformerKind.selectable),
            globeKeyAction: GlobeKeySettings.action,
            microphones: SystemInputDeviceCatalog().inputDevices().map {
                SettingsMicrophone(uid: $0.uid, name: $0.name)
            })
    }

    /// The same answers with the clean-up engines that answered they could run for `profile`'s language.
    static func refreshed(for profile: UserProfile) async -> SettingsCapabilities {
        var capabilities = thisMac()
        let availability = await transformerAvailability(for: profile)
        capabilities.transformerAvailability = availability
        capabilities.readyTransformers = Set(
            availability.compactMap { kind, value in
                value.isAvailable ? kind : nil
            }
        ).union([SettingsEngines.floor])
        capabilities.foundationModelAvailability = availability[.foundationModels]
        return capabilities
    }

    private static func transformerAvailability(
        for profile: UserProfile
    ) async -> [TransformerKind: TransformerAvailability] {
        let probe = TransformationRequest(transcription: Transcription(text: ""), profile: profile)
        var availability: [TransformerKind: TransformerAvailability] = [:]
        for engine in TextTransformers.all() {
            availability[engine.kind] = await engine.availability(for: probe)
        }
        return availability
    }

    /// What this build calls itself, as "short (build)", since two builds of one release differ.
    private static var versionDescription: String? {
        let version = AppVersion.ofThisBuild
        guard version.isKnown else { return nil }
        return version.build == version.short ? version.short : version.full
    }

    /// Whether macOS has an output device; `NSSound.play()` on none returns false without saying why.
    private static var hasAudioOutput: Bool {
        hasAudioDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// Whether macOS has an input device, even when microphone permission has already been granted.
    static var hasAudioInput: Bool {
        hasAudioDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Whether Core Audio has a default device for the requested direction.
    private static func hasAudioDevice(_ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != AudioDeviceID(kAudioObjectUnknown)
    }
}

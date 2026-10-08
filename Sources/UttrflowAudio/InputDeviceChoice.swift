// Which input device a recording opens, chosen by stable UID rather than by the system default.
import CoreAudio

/// An input device as a user can choose it, identified by the UID that survives a reconnect.
public struct AudioInputDevice: Sendable, Equatable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// The input devices present right now, behind a seam so a test needs no hardware.
public protocol AudioInputDeviceCatalog: Sendable {
    func inputDevices() -> [AudioInputDevice]
}

/// What one open resolved to, so a capture summary can say when the chosen device was missing.
public enum InputSelection: Sendable, Equatable {
    /// Nothing was chosen, so the engine uses whatever macOS has as default.
    case systemDefault
    /// The chosen device was present and is the one opened.
    case chosen(uid: String)
    /// A device was chosen but is absent, so the system default is opened instead.
    case fellBack

    /// Resolves a preference against the devices present at the moment of opening.
    public static func resolve(preferredUID: String?, present: [AudioInputDevice]) -> InputSelection {
        guard let preferredUID else { return .systemDefault }
        return present.contains { $0.uid == preferredUID } ? .chosen(uid: preferredUID) : .fellBack
    }

    /// The UID to set on the engine, nil when the default is what opens.
    public var deviceUID: String? {
        if case .chosen(let uid) = self { return uid }
        return nil
    }
}

/// The devices CoreAudio reports with at least one input stream.
public struct SystemInputDeviceCatalog: AudioInputDeviceCatalog {
    public init() {}

    public func inputDevices() -> [AudioInputDevice] {
        Self.allDeviceIDs().compactMap { id in
            guard Self.hasInput(id), let uid = Self.string(id, kAudioDevicePropertyDeviceUID),
                let name = Self.string(id, kAudioObjectPropertyName)
            else { return nil }
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    /// The CoreAudio id for a UID now, which changes across reconnects while the UID does not.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        Self.allDeviceIDs().first {
            Self.hasInput($0) && Self.string($0, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var property = address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var property = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector, kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }
}

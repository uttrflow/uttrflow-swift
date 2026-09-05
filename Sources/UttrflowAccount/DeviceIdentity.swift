public import struct Foundation.Data
public import struct Foundation.UUID

/// What this installation tells the backend about itself.
///
/// Four fields, and the restraint is the point. The backend keeps one row per
/// installation so that somebody can look at a list of the machines they are signed in on
/// and end any one of them; that list needs a name they will recognise and nothing else.
/// No model, no serial, no operating-system build — none of which would make the list
/// more useful, and all of which would make it a profile of the person's hardware.
public struct DeviceRegistration: Sendable, Equatable, Codable {
    /// This installation's own random identifier, generated once and kept locally.
    public let installID: String

    /// Which kind of machine. The wire spelling the backend's enum uses.
    public let platform: String

    /// What the person will recognise: "Naveen's MacBook Pro".
    public let name: String

    /// The build talking, so a support question does not begin by asking.
    public let appVersion: String?

    public init(installID: String, platform: String, name: String, appVersion: String?) {
        self.installID = installID
        self.platform = platform
        self.name = name
        self.appVersion = appVersion
    }

    /// The wire spelling the backend reads.
    enum CodingKeys: String, CodingKey {
        case installID = "installId"
        case platform, name, appVersion
    }
}

/// Whatever can say what this machine is.
public protocol DeviceIdentifying: Sendable {
    func registration() -> DeviceRegistration
}

/// This Mac.
///
/// The install identifier is **generated here and kept in the app's own defaults** — it is
/// not a serial number, not the hardware UUID, and not an `IDFV`. Those outlive an
/// uninstall, are shared with every other app on the machine, and are a tracking vector
/// this product would then have to explain on a privacy page whose whole claim is that
/// nothing leaves your Mac. A random value that dies when the app is deleted identifies an
/// installation just as well, which is all the backend needs.
public struct MacDeviceIdentity: DeviceIdentifying {
    public static let defaultKey = "com.uttrflow.device.install-id.v1"

    /// The wire spelling the backend's `device_platform` enum uses for a Mac.
    public static let platform = "macos"

    private let storage: any SessionStorage
    private let key: String
    private let name: @Sendable () -> String
    private let appVersion: String?
    private let makeInstallIdentifier: @Sendable () -> String

    public init(
        storage: any SessionStorage,
        name: @escaping @Sendable () -> String,
        appVersion: String?,
        key: String = defaultKey,
        makeInstallIdentifier: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.storage = storage
        self.key = key
        self.name = name
        self.appVersion = appVersion
        self.makeInstallIdentifier = makeInstallIdentifier
    }

    public func registration() -> DeviceRegistration {
        DeviceRegistration(
            installID: installIdentifier(), platform: Self.platform, name: name(),
            appVersion: appVersion)
    }

    /// The identifier for this installation, minted on first use and kept thereafter.
    ///
    /// A lost identifier costs one extra row in somebody's device list, which is why the
    /// failure to read one is answered by minting another rather than by refusing to sign
    /// in. Stored as raw UTF-8 rather than as JSON so that a value written by a future
    /// build with a different encoder is still readable by this one.
    private func installIdentifier() -> String {
        if let data = storage.data(forKey: key), !data.isEmpty,
            let existing = String(data: data, encoding: .utf8)
        {
            return existing
        }
        let minted = makeInstallIdentifier()
        storage.set(Data(minted.utf8), forKey: key)
        return minted
    }
}

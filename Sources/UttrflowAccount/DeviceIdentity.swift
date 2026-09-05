// What this installation tells the backend about itself.
public import struct Foundation.Data
public import struct Foundation.UUID

/// The four fields the backend keeps per installation: enough to recognise a machine and nothing more.
public struct DeviceRegistration: Sendable, Equatable, Codable {
    /// This installation's own random identifier, generated once and kept locally.
    public let installID: String

    /// Which kind of machine. The wire spelling the backend's enum uses.
    public let platform: String

    /// What the person will recognise: "Naveen's MacBook Pro".
    public let name: String

    /// The build talking, so a support question does not begin by asking.
    public let appVersion: String?

    /// Assembles a registration.
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
    /// This installation, as the backend records it.
    func registration() -> DeviceRegistration
}

/// This Mac, identified by a random value in the app's own defaults, never by anything the hardware carries.
public struct MacDeviceIdentity: DeviceIdentifying {
    /// The defaults key the install identifier is under, versioned.
    public static let defaultKey = "com.uttrflow.device.install-id.v1"

    /// The wire spelling the backend's `device_platform` enum uses for a Mac.
    public static let platform = "macos"

    /// Where the install identifier lives.
    private let storage: any SessionStorage
    /// The key it is under.
    private let key: String
    /// What the person calls this Mac, read when asked.
    private let name: @Sendable () -> String
    /// This build.
    private let appVersion: String?
    /// Mints a fresh identifier, injected so a test can pin one.
    private let makeInstallIdentifier: @Sendable () -> String

    /// Everything but the key and the minter must be supplied.
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

    /// This Mac's registration, minting the install identifier on first use.
    public func registration() -> DeviceRegistration {
        DeviceRegistration(
            installID: installIdentifier(), platform: Self.platform, name: name(),
            appVersion: appVersion)
    }

    /// The install identifier, minted when none reads back; raw UTF-8, so a future encoder cannot break it.
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

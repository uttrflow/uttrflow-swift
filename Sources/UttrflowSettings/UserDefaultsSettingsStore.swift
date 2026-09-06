// The settings store backed by `UserDefaults`, and the two-call key-value protocol it is tested through.
public import Foundation

/// One blob of bytes under one name: the two `UserDefaults` calls the store makes, so tests need no domain.
public protocol KeyValueStore: Sendable {
    /// The bytes stored under `key`, or `nil` when there are none.
    func data(forKey key: String) -> Data?

    /// Stores `data`, or removes the value when it is `nil`.
    func set(_ data: Data?, forKey key: String)
}

/// The user's settings kept in `UserDefaults` as one JSON blob, so a save is whole and needs no migration.
public struct UserDefaultsSettingsStore: SettingsStore {
    /// Versioned so a shape too different to read field by field can live beside this one.
    public static let defaultKey = "com.uttrflow.settings.v1"

    /// Where the blob is kept.
    private let store: any KeyValueStore
    /// The name the blob is kept under.
    private let key: String

    /// Uses the app's own defaults domain and key unless a store or key is given.
    public init(store: any KeyValueStore = SystemUserDefaults(), key: String = defaultKey) {
        self.store = store
        self.key = key
    }

    /// The saved settings, or the defaults when the blob is absent, corrupt or shaped by another build.
    public func load() -> Settings {
        guard let data = store.data(forKey: key),
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return settings
    }

    /// Writes the blob; encoding settings made of strings, numbers, booleans and arrays cannot fail.
    public func save(_ settings: Settings) {
        store.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}

/// The app's own defaults domain, as the thinnest adapter so nothing above it needs real preferences.
public struct SystemUserDefaults: KeyValueStore {
    /// A defaults domain to use instead of the app's own; only a test passes one.
    private let suiteName: String?

    /// Uses the app's own domain unless `suiteName` names another, which only a test does.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// Named rather than held, because `UserDefaults` is not `Sendable` though documented as thread-safe.
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Reads the blob under `key`.
    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    /// Writes `data` under `key`, removing it when `nil`.
    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

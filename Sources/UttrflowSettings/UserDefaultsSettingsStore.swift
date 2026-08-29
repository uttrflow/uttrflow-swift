public import Foundation

/// A place to put one blob of bytes under one name, and get it back.
///
/// The whole of `UserDefaults` reduced to the two calls the settings store actually
/// makes. Injecting this rather than a `UserDefaults` instance means the store's real
/// behaviour — what it writes, and what it does with what it reads back — is tested
/// without a defaults domain, a suite name, or anything that outlives the test.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?

    /// Stores `data`, or removes the value when it is `nil`.
    func set(_ data: Data?, forKey key: String)
}

/// The user's settings, kept in `UserDefaults` as one JSON blob.
///
/// One blob rather than a key per setting: the settings are written and read as a
/// whole, so there is no state in which half of a saved change survived a crash, and
/// adding a setting does not mean inventing a migration.
public struct UserDefaultsSettingsStore: SettingsStore {
    /// Versioned so that a future shape too different to be read field by field can be
    /// introduced beside this one rather than on top of it.
    public static let defaultKey = "com.uttrflow.settings.v1"

    private let store: any KeyValueStore
    private let key: String

    public init(store: any KeyValueStore = SystemUserDefaults(), key: String = defaultKey) {
        self.store = store
        self.key = key
    }

    /// Absent, truncated, corrupt or written by a build that knew different fields —
    /// every one of them means the same thing to a user, which is that the app should
    /// still open. ``Settings`` recovers what it can field by field; anything it cannot
    /// read at all becomes the defaults here.
    public func load() -> Settings {
        guard let data = store.data(forKey: key),
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .default }
        return settings
    }

    /// Encoding a value whose every field is a string, number, boolean or array of the
    /// same cannot fail, so there is no failure to report and no caller left holding an
    /// error it could do nothing about. Written as one expression rather than a guard
    /// so the store carries no branch that can never be taken.
    public func save(_ settings: Settings) {
        store.set(try? JSONEncoder().encode(settings), forKey: key)
    }
}

/// The real thing: the app's own defaults domain.
///
/// Deliberately the thinnest possible adapter. It holds no logic to get wrong, which
/// is what lets everything above it be tested without touching the user's preferences.
public struct SystemUserDefaults: KeyValueStore {
    private let suiteName: String?

    /// - Parameter suiteName: A defaults domain to use instead of the app's own.
    ///   Nothing but a test has a reason to pass one.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// `UserDefaults` is not `Sendable`, though it is documented as safe to use from
    /// any thread. Naming the domain rather than holding an instance keeps that
    /// promise checkable by the compiler instead of asserted in a comment.
    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

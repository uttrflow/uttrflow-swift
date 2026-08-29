import Foundation

public import UttrflowSettings

/// Whether the user has been through first-run onboarding, remembered between launches.
///
/// Deliberately the only thing onboarding writes down about itself. Everything else it
/// could remember — which permissions were granted, how far the user got — would be a
/// claim about the system that the system is free to have changed since, and a first
/// run that trusted such a claim would show a page saying "granted" over a permission
/// the user had just taken away. Those are read afresh on every launch instead.
public protocol OnboardingRecordStore: Sendable {
    var hasFinished: Bool { get }

    /// Records that the user reached the last page and closed it.
    func recordFinished()
}

/// The record, kept in `UserDefaults` beside the user's settings.
///
/// The fact has nothing to it beyond its own presence, so presence is how it is stored:
/// a key that exists means the user has been through onboarding, and there is no second
/// state in which the key exists and says no. That leaves no way to write a value this
/// build could misread, which is the whole risk a one-field preference carries.
public struct UserDefaultsOnboardingRecordStore: OnboardingRecordStore {
    /// Versioned so that a later build wanting to walk everybody through a new step can
    /// do it by asking a new question rather than by rewriting the answer to this one.
    public static let defaultKey = "com.uttrflow.onboarding.v1"

    private let store: any KeyValueStore
    private let key: String

    public init(store: any KeyValueStore = SystemUserDefaults(), key: String = defaultKey) {
        self.store = store
        self.key = key
    }

    public var hasFinished: Bool { store.data(forKey: key) != nil }

    public func recordFinished() {
        store.set(Data(), forKey: key)
    }
}

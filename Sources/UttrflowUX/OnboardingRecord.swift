// Whether the user has finished onboarding: the only thing onboarding writes down about itself.
import Foundation

public import UttrflowSettings

/// Whether the user has been through onboarding; the only fact kept, since everything else is re-read.
public protocol OnboardingRecordStore: Sendable {
    /// Whether the user reached the last page and closed it.
    var hasFinished: Bool { get }

    /// Records that the user reached the last page and closed it.
    func recordFinished()
}

/// The record in `UserDefaults`; the key's presence is the fact, so there is no value to misread.
public struct UserDefaultsOnboardingRecordStore: OnboardingRecordStore {
    /// Versioned, so a later build can walk everybody through a new step by asking a new question.
    public static let defaultKey = "com.uttrflow.onboarding.v1"

    /// Where the key lives.
    private let store: any KeyValueStore
    /// The key whose presence is the record.
    private let key: String

    /// Records in the given store under the given key.
    public init(store: any KeyValueStore = SystemUserDefaults(), key: String = defaultKey) {
        self.store = store
        self.key = key
    }

    /// Whether the key is present.
    public var hasFinished: Bool { store.data(forKey: key) != nil }

    /// Writes the key.
    public func recordFinished() {
        store.set(Data(), forKey: key)
    }
}

// Whether the user has finished onboarding, and whether they have answered the clipboard page.
import Foundation

public import UttrflowSettings

/// Whether the user has been through onboarding, and past the clipboard page; everything else is re-read.
public protocol OnboardingRecordStore: Sendable {
    /// Whether the user reached the last page and closed it.
    var hasFinished: Bool { get }

    /// Records that the user reached the last page and closed it.
    func recordFinished()

    /// Whether the user has left the clipboard page; the setting cannot say so, since keeping is its default.
    var hasAnsweredClipboard: Bool { get }

    /// Records that the user left the clipboard page with the choice it showed.
    func recordClipboardAnswered()
}

/// The record in `UserDefaults`; the key's presence is the fact, so there is no value to misread.
public struct UserDefaultsOnboardingRecordStore: OnboardingRecordStore {
    /// Versioned, so a later build can walk everybody through a new step by asking a new question.
    public static let defaultKey = "com.uttrflow.onboarding.v1"

    /// Where the key lives.
    private let store: any KeyValueStore
    /// The key whose presence is the record.
    private let key: String

    /// The key whose presence says the clipboard page was answered.
    static let clipboardKey = "com.uttrflow.onboarding.clipboard.v1"

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

    /// Whether the clipboard key is present.
    public var hasAnsweredClipboard: Bool { store.data(forKey: Self.clipboardKey) != nil }

    /// Writes the clipboard key.
    public func recordClipboardAnswered() {
        store.set(Data(), forKey: Self.clipboardKey)
    }
}

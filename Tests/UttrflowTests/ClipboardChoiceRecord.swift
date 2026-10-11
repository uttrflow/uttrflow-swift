// An onboarding record held in memory, so a test never reads or writes this Mac's defaults.

import Foundation
import UttrflowAccount
import UttrflowSettings
import UttrflowUX

/// Bytes in memory, so no test reads or writes the real defaults domain.
final class MemoryDefaults: KeyValueStore, SessionStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }

    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

/// A record with nothing answered, or with the clipboard page answered, in a store of its own.
func isolatedOnboardingRecord(clipboardAnswered: Bool = false) -> UserDefaultsOnboardingRecordStore {
    let record = UserDefaultsOnboardingRecordStore(store: MemoryDefaults())
    if clipboardAnswered { record.recordClipboardAnswered() }
    return record
}

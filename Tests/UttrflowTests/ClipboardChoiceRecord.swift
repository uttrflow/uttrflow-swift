// An onboarding record held in its own defaults suite, so a test never reads or writes this Mac's.

import Foundation
import UttrflowSettings
import UttrflowUX

/// A record with nothing answered, or with the clipboard page answered, in a suite of its own.
func isolatedOnboardingRecord(clipboardAnswered: Bool = false) -> UserDefaultsOnboardingRecordStore {
    let record = UserDefaultsOnboardingRecordStore(
        store: SystemUserDefaults(suiteName: "com.uttrflow.tests.record.\(UUID().uuidString)"))
    if clipboardAnswered { record.recordClipboardAnswered() }
    return record
}

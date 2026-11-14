// Tests for the onboarding record kept in UserDefaults.
import Testing

@testable import UttrflowSettings
@testable import UttrflowUX

@Suite("Onboarding record")
struct OnboardingRecordTests {
    @Test("a Mac that has never run Uttrflow has nothing written down")
    func nothingWrittenDownAtFirst() {
        let store = UserDefaultsOnboardingRecordStore(store: InMemoryKeyValueStore())
        #expect(!store.hasFinished)
    }

    @Test("survives the launch it was written in")
    func survivesARelaunch() {
        let defaults = InMemoryKeyValueStore()
        UserDefaultsOnboardingRecordStore(store: defaults).recordFinished()

        // A second store over the same defaults is what the next launch sees.
        #expect(UserDefaultsOnboardingRecordStore(store: defaults).hasFinished)
    }

    @Test("keeps its own key, so a rewritten settings blob cannot answer for it")
    func keepsItsOwnKey() {
        let defaults = InMemoryKeyValueStore()
        UserDefaultsOnboardingRecordStore(store: defaults).recordFinished()

        #expect(defaults.keys == [UserDefaultsOnboardingRecordStore.defaultKey])
        #expect(!defaults.keys.contains(UserDefaultsSettingsStore.defaultKey))
    }

    @Test("recording it twice is recording it once")
    func recordingIsIdempotent() {
        let defaults = InMemoryKeyValueStore()
        let store = UserDefaultsOnboardingRecordStore(store: defaults)
        store.recordFinished()
        store.recordFinished()

        #expect(store.hasFinished)
        #expect(defaults.keys.count == 1)
    }
}

// A settings row that asks for something to happen must reach the app, not be saved and lost.

import Foundation
import Testing
import UttrflowHistory
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

/// Settings held in memory, so the routing is tested without a file behind it.
private final class RecordingStore: SettingsStore, @unchecked Sendable {
    private(set) var saves = 0
    private var settings = Settings.default

    func load() -> Settings { settings }

    func save(_ settings: Settings) {
        self.settings = settings
        saves += 1
    }
}

/// Personalisation that has nothing to count and nothing to remove.
private struct EmptyPersonalisation: SettingsPersonalisationStore {
    func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        SettingsPersonalisation(learnedWords: 0, addedWords: 0, transcripts: 0)
    }

    func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure) {}
}

@MainActor
@Suite("A settings row that asks for something to happen")
struct SettingsRequestWiringTests {
    /// Builds a model over the recording store, reporting what each callback was handed.
    private func model(
        _ store: RecordingStore,
        onChange: @escaping (Settings) -> Void = { _ in },
        onRequest: @escaping (SettingsChange) -> Void = { _ in }
    ) -> SettingsViewModel {
        SettingsViewModel(
            store: store, personalisation: EmptyPersonalisation(), capabilities: .everything,
            onChange: onChange, onRequest: onRequest)
    }

    @Test("Check Now reaches the app, which is the only thing that can ask the feed")
    func checkNowIsHandedOn() {
        var asked: [SettingsChange] = []
        let store = RecordingStore()
        let model = model(store, onRequest: { asked.append($0) })

        model.apply(.checkForUpdatesNow)

        #expect(asked == [.checkForUpdatesNow])
    }

    @Test("and is not saved, since it changes no setting")
    func checkNowSavesNothing() {
        var changed = 0
        let store = RecordingStore()
        let model = model(store, onChange: { _ in changed += 1 })

        model.apply(.checkForUpdatesNow)

        #expect(store.saves == 0)
        #expect(changed == 0)
    }

    @Test("an ordinary change still saves and still reports, and asks for nothing")
    func anOrdinaryChangeIsUnaffected() {
        var changed: [Settings] = []
        var asked: [SettingsChange] = []
        let store = RecordingStore()
        let model = model(store, onChange: { changed.append($0) }, onRequest: { asked.append($0) })

        model.apply(.toggle(.playsSoundWhenRecordingStarts, isOn: true))

        #expect(store.saves == 1)
        #expect(changed.count == 1)
        #expect(changed.first?.playsSoundWhenRecordingStarts == true)
        #expect(asked.isEmpty)
    }
}

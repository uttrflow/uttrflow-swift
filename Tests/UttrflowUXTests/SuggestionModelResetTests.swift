import Foundation
import UttrflowClipboard
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import Testing

@testable import UttrflowUX

private actor ResetCalls {
    private(set) var targets: [String] = []
    func add(_ target: String) { targets.append(target) }
}

@Suite("Full reset includes suggestion model files")
struct SuggestionModelResetTests {
    @Test("full reset dispatches to the suggestion model cache owner")
    func fullResetRemovesSuggestionModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "suggestion-model-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = ResetCalls()
        let store = FilePersonalisationStore(
            dictionary: PersonalDictionaryStore(file: directory.appending(path: "dictionary.json")),
            history: DictationHistoryStore(file: directory.appending(path: "history.json")),
            clipboard: ClipboardStore(file: directory.appending(path: "clipboard.json")),
            elsewhere: KeptElsewhere(suggestionModel: { await calls.add("model") }),
            ledger: NetworkActivityLedger(file: nil))

        #expect(SettingsReset.everything.targets.contains(.suggestionModel))
        try await store.carryOut(.everything)
        #expect(await calls.targets == ["model"])
    }
}

import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

private let moment = Date(timeIntervalSince1970: 1_800_000_000)

/// A terminal prompt in the named folder.
private func shell(_ folder: String) -> Surface {
    Surface(bundleIdentifier: "com.example.term", role: "AXTextArea", locator: "Prompt", scope: folder)
}

@Suite("How many folders one lookup reads")
struct ScopeBoundTests {
    @Test("A lookup reads this folder and the most recently used others, never every folder ever used.")
    func lookupReadsBoundedRecentFolders() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        let folders = PredictStore.scopeLimit * 4
        for index in 0..<folders {
            try await store.record(
                "make target\(index)", in: shell("/f\(index)"), at: moment.addingTimeInterval(Double(index)))
        }
        let here = shell("/f0")
        let texts = Set(try await store.candidates(for: here, matching: "make").map(\.text))
        #expect(texts.count == PredictStore.scopeLimit)
        #expect(texts.contains("make target0"))
        #expect(texts.contains("make target\(folders - 1)"))
        #expect(!texts.contains("make target1"))
        let recent = try await store.recent(in: here, limit: folders)
        #expect(recent.count == PredictStore.scopeLimit)
        #expect(recent.first == "make target0")
    }
}

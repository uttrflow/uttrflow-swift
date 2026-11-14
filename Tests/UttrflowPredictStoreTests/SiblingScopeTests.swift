// Tests what a folder with no history of its own is offered from the same field's other folders.
import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

private let moment = Date(timeIntervalSince1970: 1_700_000_000)

private func document(_ name: String) -> Surface {
    Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", locator: "prompt", scope: name)
}

@Suite("A folder beside others of its field")
struct SiblingScopeTests {
    @Test("a new folder is offered the lines typed in its field's other folders")
    func newDocumentSeesSiblings() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("deploy staging", in: document("a"), at: moment)
        #expect(try await store.recent(in: document("b"), limit: 5) == ["deploy staging"])
        let found = try await store.candidates(for: document("b"), matching: "deploy s")
        #expect(found.map(\.text) == ["deploy staging"])
        #expect(found.first?.evidence?.count == 1)
    }

    @Test("a line typed in two folders is one candidate whose count is both")
    func sameLineInTwoDocuments() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("deploy staging", in: document("a"), at: moment)
        try await store.record("deploy staging", in: document("a"), at: moment.addingTimeInterval(1))
        try await store.record("deploy staging", in: document("b"), at: moment.addingTimeInterval(2))
        let found = try await store.candidates(for: document("b"), matching: "deploy s")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 3)
    }

    @Test("a query whose letters pass the character filter but are too many edits away offers nothing")
    func overBudgetFuzzyMatchIsDropped() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("deploy staging", in: document("a"), at: moment)
        // The same letters as "deploy", transposed several times over.
        let found = try await store.candidates(for: document("a"), matching: "ydolpe")
        #expect(found.isEmpty)
    }
}

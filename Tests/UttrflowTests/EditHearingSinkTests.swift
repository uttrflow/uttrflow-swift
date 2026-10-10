import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore

@testable import Uttrflow

@Suite("Edit hearing sink")
struct EditHearingSinkTests {
    private let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextField")
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func corpus() throws -> (store: PredictStore, folder: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "edit-hearing-sink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = try PredictStore(path: PredictStore.defaultFile(in: folder).path(percentEncoded: false))
        return (store, folder)
    }

    @Test("a finished value reaches the corpus, and a later correction of it replaces it there")
    func finishedValuesAndCorrectionsReachTheCorpus() async throws {
        let (store, folder) = try corpus()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = EditHearingSink(store: store, heard: { _ in })

        try await sink.record("see you at noon", in: surface, after: nil, as: .typed, at: moment)
        #expect(try await store.recent(in: surface, limit: 5) == ["see you at noon"])

        try await sink.supersede(
            "see you at noon", with: "see you at one o'clock", in: surface)
        try await sink.record(
            "see you at one o'clock", in: surface, after: nil, as: .finished, at: moment)
        #expect(try await store.recent(in: surface, limit: 5).contains("see you at one o'clock"))
    }

    @Test("an accepted suggestion is noted, and taking the acceptance back removes it")
    func acceptanceCanBeRetracted() async throws {
        let (store, folder) = try corpus()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = EditHearingSink(store: store, heard: { _ in })

        try await sink.record(
            "thanks for the update", in: surface, after: nil, as: .suggestion, at: moment)
        try await sink.recordAccepted("thanks for the update", in: surface)
        try await sink.retractAcceptance("thanks for the update", in: surface)
        #expect(try await store.recent(in: surface, limit: 5).count <= 1)
    }

    @Test("an edit inside inserted words goes to the dictation side and not to the corpus")
    func editedSpansGoToTheHearingHandler() async throws {
        let (store, folder) = try corpus()
        defer { try? FileManager.default.removeItem(at: folder) }
        let heard = HeardEdits()
        let sink = EditHearingSink(store: store, heard: { await heard.add($0) })

        let edit = EditedSpan(position: 2, old: ["there"], new: ["their"])
        try await sink.recordEditedSpan(edit, in: surface)

        #expect(await heard.all == [edit])
        #expect(try await store.recent(in: surface, limit: 5).isEmpty)
    }
}

private actor HeardEdits {
    private(set) var all: [EditedSpan] = []
    func add(_ edit: EditedSpan) { all.append(edit) }
}

import Foundation
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowPredictStore

private let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("A line the person finished is learned even when a longer line starts with it")
struct FinishedLineTests {
    @Test("A short command run on its own after a longer one is counted every time.")
    func shortLineAfterLongerLineIsCounted() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("ls -la", in: terminal, as: .finished, at: moment)
        for _ in 0..<10 { try await store.record("ls", in: terminal, as: .finished, at: moment) }
        let found = try await store.candidates(for: terminal, matching: "ls")
        #expect(found.first { $0.text == "ls" }?.evidence?.count == 10)
        #expect(found.contains { $0.text == "ls -la" })
    }

    @Test("A longer line does not retire a shorter line the person finished.")
    func longerLineLeavesAFinishedLineStanding() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("ls", in: terminal, as: .finished, at: moment)
        try await store.record("ls -la", in: terminal, as: .finished, at: moment)
        let found = try await store.candidates(for: terminal, matching: "ls").map(\.text)
        #expect(Set(found) == ["ls", "ls -la"])
    }

    @Test("A finished line still retires the unfinished draft it grew out of.")
    func finishedLineRetiresItsDraft() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git statu", in: terminal, at: moment)
        try await store.record("git status", in: terminal, as: .finished, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git s").map(\.text) == ["git status"])
    }

    @Test("Finishing a line that was a draft keeps it from being retired by a longer line later.")
    func finishingADraftKeepsIt() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git push", in: terminal, as: .finished, at: moment)
        try await store.record("git push origin", in: terminal, as: .finished, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git p").map(\.text)
        #expect(Set(found) == ["git push", "git push origin"])
    }

    @Test("Retiring a draft never retires a finished line with the same text.")
    func supersedeLeavesAFinishedLineStanding() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, as: .finished, at: moment)
        try await store.supersede("git push", with: "git push origin", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git p").map(\.text) == ["git push"])
    }

    @Test("A draft of a line the person already finished is still counted.")
    func draftOfAFinishedLineIsCounted() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, as: .finished, at: moment)
        try await store.record("git push origin", in: terminal, as: .finished, at: moment)
        try await store.record("git push", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git push")
        #expect(found.first { $0.text == "git push" }?.evidence?.count == 2)
    }

    @Test("A file from the previous schema gains the finished mark, with every older line unfinished.")
    func migratesThePreviousSchema() async throws {
        let corpus = Corpus()
        do {
            let store = try store(corpus)
            try await store.record("ls", in: terminal, at: moment)
        }
        let database = try Database(path: corpus.path)
        try database.execute("ALTER TABLE entry DROP COLUMN finished")
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(Schema.version - 1)) }

        let store = try store(corpus)
        try await store.record("ls -la", in: terminal, as: .finished, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "ls").map(\.text) == ["ls -la"])
        let version = try Database(path: corpus.path).rows("SELECT version FROM schema_version", { _ in }) {
            $0.integer(0)
        }
        #expect(version == [Schema.version])
    }
}

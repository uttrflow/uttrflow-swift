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

    @Test("A field evicts its least recently used scopes and their entries.")
    func evictsOldScopesAndTheirDependents() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        for index in 0...PredictStore.surfacesPerField {
            let scope = shell("/f\(index)")
            try await store.record(
                "command \(index)", in: scope, at: moment.addingTimeInterval(Double(index)))
        }
        let counts = try Database(path: corpus.path).rows(
            "SELECT (SELECT COUNT(*) FROM surface), (SELECT COUNT(*) FROM entry)", { _ in }
        ) { [$0.integer(0), $0.integer(1)] }
        #expect(counts == [[PredictStore.surfacesPerField, PredictStore.surfacesPerField]])
        // A lookup also reads sibling folders, so which scopes survive is read from the table itself.
        let scopes = Set(
            try Database(path: corpus.path).rows("SELECT scope FROM surface", { _ in }) { $0.text(0) })
        #expect(!scopes.contains("/f0"))
        #expect(scopes.contains("/f\(PredictStore.surfacesPerField)"))
        let offered = try await store.candidates(for: shell("/f0"), matching: "command").map(\.text)
        #expect(!offered.contains("command 0"))
    }

    @Test("a large scope eviction reclaims the freed pages")
    func compactsAfterLargeScopeEviction() async throws {
        let corpus = Corpus()
        let store = try PredictStore(path: corpus.path)
        let sizeBefore: Int
        do {
            let database = try Database(path: corpus.path)
            var oldestSurface: Int64?
            for index in 0..<PredictStore.surfacesPerField {
                try database.run(
                    "INSERT INTO surface (bundle_id, role, locator, scope, last_used) VALUES (?, ?, ?, ?, ?)"
                ) {
                    $0.bind(1, "com.example.term")
                    $0.bind(2, "AXTextArea")
                    $0.bind(3, "Prompt")
                    $0.bind(4, "/f\(index)")
                    $0.bind(5, Double(index + 1))
                }
                if index == 0 { oldestSurface = database.lastInsertedIdentifier }
            }
            guard let oldestSurface else { Issue.record("Missing oldest scope"); return }
            for index in 0..<512 {
                let text = "entry-\(index)-" + String(repeating: "x", count: 1_000)
                try database.run(
                    "INSERT INTO entry (surface_id, text, text_lower, last_used) VALUES (?, ?, ?, ?)"
                ) {
                    $0.bind(1, oldestSurface)
                    $0.bind(2, text)
                    $0.bind(3, text.lowercased())
                    $0.bind(4, Double(index))
                }
            }
            _ = try database.rows("PRAGMA wal_checkpoint(TRUNCATE)", { _ in }) { $0.integer(0) }
            sizeBefore =
                (try FileManager.default.attributesOfItem(atPath: corpus.path)[.size] as? NSNumber)?.intValue
                ?? 0
        }
        #expect(sizeBefore > PredictStore.compactionThresholdPages * 4_096)

        try await store.record("new command", in: shell("/new"), at: moment)

        let database = try Database(path: corpus.path)
        let pagesAfter = try database.rows("PRAGMA freelist_count", { _ in }) { $0.integer(0) }.first ?? 0
        let sizeAfter =
            (try FileManager.default.attributesOfItem(atPath: corpus.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(pagesAfter == 0)
        #expect(sizeAfter < sizeBefore)
    }
}

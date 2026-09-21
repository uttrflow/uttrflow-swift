// Tests that a keystroke matching nothing does not materialise every line learned (#870).
import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("What the fuzzy tier reads", .serialized)
struct FuzzyScanBoundTests {
    static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    static func surface(_ scope: String) -> Surface {
        Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: scope)
    }

    @Test("a long line that matches nothing reads far fewer rows than are stored")
    func aLongMissReadsFewRows() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for scope in 1...10 {
            for line in 1...1_000 {
                try await store.record(
                    "git commit -m fix \(line)", in: Self.surface("/work/\(scope)"), at: Self.moment)
            }
        }

        PredictStore.rowsScanned.withLock { $0 = 0 }
        let typed = "kubectl describe deployment payments-api --namespace staging"
        let found = try await store.candidates(for: Self.surface("/work/3"), matching: typed)
        let scanned = PredictStore.rowsScanned.withLock { $0 }

        #expect(found.isEmpty)
        #expect(scanned < 100, "\(scanned) rows of 10,000 reached Swift")
    }

    @Test("a typo in a short line still matches what was learned")
    func aTypoStillMatches() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: Self.surface("/work/1"), at: Self.moment)

        let found = try await store.candidates(for: Self.surface("/work/1"), matching: "gti sta")

        #expect(found.map(\.text) == ["git status"])
    }
}

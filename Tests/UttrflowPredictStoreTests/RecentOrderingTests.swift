// Tests the order the recency read gives: this document first, then newest, each line once (#880).
import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictStore

@Suite("The lines offered as recently entered")
struct RecentOrderingTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func surface(_ scope: String) -> Surface {
        Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: scope)
    }

    @Test("the document in hand comes first, then the newest, and each line once")
    func orderIsDocumentThenNewest() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Self.surface("/here")
        let elsewhere = Self.surface("/elsewhere")

        try await store.record("older elsewhere", in: elsewhere, at: Self.start)
        try await store.record("newest elsewhere", in: elsewhere, at: Self.start.addingTimeInterval(300))
        try await store.record("older here", in: here, at: Self.start.addingTimeInterval(60))
        try await store.record("newer here", in: here, at: Self.start.addingTimeInterval(120))
        // The same line in both places is one line, ranked by the document in hand.
        try await store.record("shared line", in: elsewhere, at: Self.start.addingTimeInterval(400))
        try await store.record("shared line", in: here, at: Self.start.addingTimeInterval(30))

        let recent = try await store.recent(in: here, limit: 6)

        // A line entered here ranks ahead of one entered only elsewhere, by its newest use anywhere.
        #expect(recent.prefix(3) == ["shared line", "newer here", "older here"])
        #expect(recent.dropFirst(3) == ["newest elsewhere", "older elsewhere"])
    }

    @Test("the limit is honoured across scopes")
    func limitIsHonoured() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for scope in 1...4 {
            for line in 1...10 {
                try await store.record(
                    "line \(scope)-\(line)", in: Self.surface("/s\(scope)"),
                    at: Self.start.addingTimeInterval(Double(scope * 100 + line)))
            }
        }

        #expect(try await store.recent(in: Self.surface("/s1"), limit: 6).count == 6)
    }
}

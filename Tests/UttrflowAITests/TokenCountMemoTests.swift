// Tests for counting unchanging text once, ahead of the request that needs the count.

import Synchronization
import Testing

@testable import UttrflowAI

/// What was counted, in order: the point is how often the slow counter runs.
private final class Counted: Sendable {
    private let texts = Mutex<[String]>([])

    func add(_ text: String) { texts.withLock { $0.append(text) } }

    var all: [String] { texts.withLock { $0 } }
}

/// A counter that fails, as the system tokenizer can.
private struct CountFailed: Error {}

@Suite("Counting unchanging text once")
struct TokenCountMemoTests {
    @Test("counts the same text once and answers from memory after")
    func countsOnce() async throws {
        let counted = Counted()
        let memo = TokenCountMemo()
        let counter: @Sendable (String) async throws -> Int = { text in
            counted.add(text)
            return text.count
        }

        #expect(try await memo.tokens(for: "tidy this", counting: counter) == 9)
        #expect(try await memo.tokens(for: "tidy this", counting: counter) == 9)
        #expect(counted.all == ["tidy this"])
    }

    @Test("counts again when the text changes, and remembers the new one")
    func countsChangedText() async throws {
        let counted = Counted()
        let memo = TokenCountMemo()
        let counter: @Sendable (String) async throws -> Int = { text in
            counted.add(text)
            return text.count
        }

        _ = try await memo.tokens(for: "plain", counting: counter)
        #expect(try await memo.tokens(for: "email", counting: counter) == 5)
        _ = try await memo.tokens(for: "email", counting: counter)
        #expect(counted.all == ["plain", "email"])
    }

    @Test("remembers nothing when counting fails, so the next request counts again")
    func failureIsNotRemembered() async throws {
        let counted = Counted()
        let memo = TokenCountMemo()

        await #expect(throws: CountFailed.self) {
            try await memo.tokens(for: "plain") { text in
                counted.add(text)
                throw CountFailed()
            }
        }
        #expect(try await memo.tokens(for: "plain") { _ in 7 } == 7)
        #expect(counted.all == ["plain"])
    }
}

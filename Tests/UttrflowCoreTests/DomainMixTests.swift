// Tests that the domain mix recovers a synthetic persona's known usage from the style rows alone.
import Testing

@testable import UttrflowCore

@Suite("The domain mix")
struct DomainMixTests {
    private func rows(_ usage: [(Destination, dictations: Int, words: Int)]) -> [EvidenceRow] {
        usage.flatMap { destination, dictations, words in
            (0..<dictations).flatMap { _ in
                StyleSignals.rows(
                    for: Array(repeating: "word", count: words).joined(separator: " "), into: destination,
                    day: 1)
            }
        }
    }

    @Test("recovers a persona who codes mostly, writes some mail and chats a little")
    func recoversKnownMix() {
        // 60% code, 30% mail, 10% chat by words.
        let mix = DomainMix.project(rows([(.codeEditor, 12, 30), (.email, 6, 30), (.messaging, 10, 6)]))
        #expect(abs((mix[.codeEditor] ?? 0) - 0.6) < 0.01)
        #expect(abs((mix[.email] ?? 0) - 0.3) < 0.01)
        #expect(abs((mix[.messaging] ?? 0) - 0.1) < 0.01)
        #expect(abs(mix.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test("claims no mix from only a few words")
    func abstainsWhenThin() {
        #expect(DomainMix.project(rows([(.codeEditor, 2, 10)])).isEmpty)
    }
}

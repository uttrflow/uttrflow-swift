// Tests for style numbers counted per destination and kept with no text.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowCore

@Suite("Style signals")
struct StyleSignalsTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    /// An invented persona: terse in messaging, full sentences in email.
    private static let persona: [(String, Destination)] = [
        ("see you at the depot", .messaging),
        ("running late, ten minutes", .messaging),
        ("Sure. Bring the blue folder.", .messaging),
        ("Thanks for the notes on the harbour plan. I will send the figures by Friday.", .email),
        ("The meeting moved to room four. Please bring the draft.", .email),
    ]

    private static func rows(day: Int = 20_000) -> [EvidenceRow] {
        persona.flatMap { StyleSignals.rows(for: $0.0, into: $0.1, day: day) }
    }

    @Test("a synthetic persona projects the stated numbers per destination")
    func personaNumbers() throws {
        let rows = Self.rows()
        let messaging = StyleSignals.project(rows, for: .messaging)
        #expect(messaging.messages == 3)
        #expect(messaging.words == 14)
        #expect(messaging.sentences == 4)
        #expect(try #require(messaging.meanSentenceLength) == 3.5)
        #expect(try #require(messaging.closingStopRate) == 1.0 / 3.0)
        let email = StyleSignals.project(rows, for: .email)
        #expect(email.words == 25)
        #expect(email.sentences == 4)
        #expect(email.shortMessages == 1)
        #expect(email.closingStopRate == 1)
        #expect(StyleSignals.project(rows, for: .document).meanSentenceLength == nil)
    }

    @Test("two runs of the persona through the ledger give equal numbers")
    func reproducible() async throws {
        var results: [StyleSignals] = []
        for _ in 0..<2 {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys()))
            let window = RetentionWindow(days: 30, now: Date(timeIntervalSince1970: 20_000.5 * 86_400))
            try await store.append(Self.rows(), keeping: window)
            results.append(StyleSignals.project(await store.rows(keeping: window), for: .email))
            try await store.reset()
        }
        #expect(results[0] == results[1])
        #expect(results[0].messages == 2)
    }

    @Test("no row carries any word of the text")
    func noText() {
        for row in Self.rows() {
            #expect(Destination(rawValue: row.subject) != nil)
            #expect(row.provenance == .dictation)
        }
    }

    @Test("an empty dictation adds nothing")
    func emptyAddsNothing() {
        #expect(StyleSignals.rows(for: " ... ", into: .plain, day: 1).isEmpty)
    }

    @Test("sentence marks inside numbers do not split a sentence")
    func decimals() {
        #expect(StyleSignals.sentenceCount("It costs 4.50 today. Fine") == 2)
        #expect(StyleSignals.sentenceCount("Really?! Yes.") == 2)
    }
}

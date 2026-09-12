import Testing

@testable import UttrflowInput

/// A synthetic keystroke carries 16 UTF-16 units; where the cut falls is a rule, not an API call. See #224.
@Suite("Cutting text for a synthetic keystroke")
struct UTF16ChunkingTests {
    private let limit = 16

    /// Rejoining every chunk must give back exactly what was asked for, whatever the text.
    private func rejoined(_ text: String) -> String {
        UTF16Chunking.chunks(of: text, limit: limit)
            .flatMap { $0 }
            .withUTF16String()
    }

    @Test("loses nothing, at every offset an emoji can sit at")
    func keepsEveryCharacter() {
        for padding in 0..<40 {
            let text = String(repeating: "a", count: padding) + "🙂" + "tail"
            #expect(rejoined(text) == text, "padding \(padding)")
        }
    }

    /// The corruption itself: one event ends on a high surrogate and the next opens on its partner.
    @Test("never cuts a surrogate pair across two keystrokes")
    func neverSplitsAScalar() {
        for padding in 0..<40 {
            let text = String(repeating: "a", count: padding) + "🙂🙂🙂"
            for chunk in UTF16Chunking.chunks(of: text, limit: limit) {
                #expect(chunk.first.map { !UTF16.isTrailSurrogate($0) } ?? true, "padding \(padding)")
                #expect(chunk.last.map { !UTF16.isLeadSurrogate($0) } ?? true, "padding \(padding)")
            }
        }
    }

    @Test("keeps every chunk inside the limit the API enforces")
    func honoursTheLimit() {
        for padding in 0..<40 {
            let text = String(repeating: "a", count: padding) + "🙂👩‍👩‍👧‍👦e\u{0301}"
            for chunk in UTF16Chunking.chunks(of: text, limit: limit) {
                #expect(chunk.count <= limit, "padding \(padding)")
            }
        }
    }

    @Test("carries a family and a combining accent through unchanged")
    func keepsCompositeSequences() {
        let text = "family 👩‍👩‍👧‍👦 and cafe\u{0301} and 🇮🇳 flag"

        #expect(rejoined(text) == text)
    }

    @Test("has nothing to say about nothing, and refuses a limit that cannot hold a scalar")
    func edges() {
        #expect(UTF16Chunking.chunks(of: "", limit: limit).isEmpty)
        #expect(UTF16Chunking.chunks(of: "abc", limit: 0).isEmpty)
        // One unit cannot hold an emoji, so the pair stays whole and overruns rather than breaking.
        #expect(UTF16Chunking.chunks(of: "🙂", limit: 1) == [Array("🙂".utf16)])
    }
}

extension [UInt16] {
    /// The string these units spell, which is only well defined when no pair was cut.
    fileprivate func withUTF16String() -> String {
        String(decoding: self, as: UTF16.self)
    }
}

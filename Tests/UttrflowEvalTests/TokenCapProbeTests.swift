import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Token cap probe: which Hindi pieces run the decoder out of positions")
struct TokenCapProbeTests {
    private static let piece = TokenCapPiece(id: "hindi-1", language: .hindi, text: "एक दो तीन चार")

    private static func row(seconds: Double, heard: Int = 4, effort: DecodeEffort = .none) -> TokenCapRow {
        TokenCapRow(piece: piece, audioSeconds: seconds, transcriptWords: heard, effort: effort)
    }

    @Test("pieces join one more passage at a time, per language, and skip English")
    func growing() {
        func passage(
            _ id: String, _ language: TranscriptionCase.Language, _ text: String?
        ) -> TranscriptionCase {
            TranscriptionCase(
                id: id, language: language, stressor: .everyday, romanised: id, devanagari: text)
        }
        let pieces = TokenCapPiece.growing(
            from: [
                passage("e", .english, nil), passage("h1", .hindi, "क ख"), passage("h2", .hindi, "ग घ"),
                passage("m1", .hinglish, "च छ"), passage("m2", .hinglish, "ज झ"),
            ])
        #expect(pieces.map(\.id) == ["hindi-1", "hindi-2", "hinglish-1", "hinglish-2"])
        #expect(pieces.map(\.text) == ["क ख", "क ख ग घ", "च छ", "च छ ज झ"])
    }

    @Test("a decode again, or a cap with no resume point, is a piece that reached the cap")
    func reachedCap() {
        #expect(!Self.row(seconds: 8).reachedCap)
        #expect(Self.row(seconds: 8, effort: DecodeEffort(retrySeconds: 1.5)).reachedCap)
        #expect(Self.row(seconds: 8, effort: DecodeEffort(capUnresolved: true)).reachedCap)
    }

    @Test("the ratio is the words out over the words read")
    func wordRatio() {
        #expect(Self.row(seconds: 8, heard: 4).wordRatio == 1)
        #expect(Self.row(seconds: 8, heard: 2).wordRatio == 0.5)
    }

    @Test("the table groups the rows by how long the piece ran")
    func table() {
        let rows = [
            Self.row(seconds: 5), Self.row(seconds: 25, effort: DecodeEffort(retrySeconds: 2)),
            Self.row(seconds: 28, effort: DecodeEffort(capUnresolved: true)),
        ]
        let markdown = TokenCapTable(rows: rows).markdown
        #expect(markdown.contains("| under 10 s | 1 | 0 | 0 |"))
        #expect(markdown.contains("| 20 to 30 s | 2 | 2 | 1 |"))
        #expect(!markdown.contains("over 30 s"))
    }
}

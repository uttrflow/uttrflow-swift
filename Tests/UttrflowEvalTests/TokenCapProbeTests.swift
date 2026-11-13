import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Token cap probe: which Hindi pieces run the decoder out of positions")
struct TokenCapProbeTests {
    private static let piece = TokenCapPiece(id: "hindi-1", language: .hindi, text: "एक दो तीन चार")

    private static func row(seconds: Double, heard: Int = 4, effort: DecodeEffort = .none) -> TokenCapRow {
        TokenCapRow(piece: piece, audioSeconds: seconds, transcriptWords: heard, effort: effort)
    }

    @Test("pieces grow by one passage at a time, per language")
    func growing() {
        let pieces = TokenCapPiece.growing(from: TranscriptionCorpus.all)
        let hindi = pieces.filter { $0.language == .hindi }
        #expect(!hindi.isEmpty)
        #expect(zip(hindi, hindi.dropFirst()).allSatisfy { $0.words < $1.words })
        #expect(pieces.allSatisfy { $0.language != .english })
        #expect(Set(pieces.map(\.id)).count == pieces.count)
    }

    @Test("a decode again, or a cap with no resume point, is a piece that reached the cap")
    func reachedCap() {
        #expect(!Self.row(seconds: 8).reachedCap)
        #expect(Self.row(seconds: 8, effort: DecodeEffort(retrySeconds: 1.5)).reachedCap)
        #expect(Self.row(seconds: 8, effort: DecodeEffort(capUnresolved: true)).reachedCap)
    }

    @Test("a piece that lost its end shows as under a whole share of its words")
    func wordShare() {
        #expect(Self.row(seconds: 8, heard: 4).wordShare == 1)
        #expect(Self.row(seconds: 8, heard: 2).wordShare == 0.5)
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

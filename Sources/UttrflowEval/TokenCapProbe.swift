// How often a Hindi piece runs the decoder out of positions, and what the recovery costs.
package import UttrflowCore

/// One piece of Hindi speech: a run of the corpus's passages said without a pause between them.
package struct TokenCapPiece: Sendable, Equatable {
    package let id: String
    package let language: TranscriptionCase.Language
    /// The Devanagari text the voice reads.
    package let text: String

    /// How many words the voice reads.
    package var words: Int { WordTokens.words(text, .display).count }

    /// For each language, the first passage, then the first two joined, and so on, so the pieces grow in length.
    package static func growing(from passages: [TranscriptionCase]) -> [TokenCapPiece] {
        var pieces: [TokenCapPiece] = []
        for language in [TranscriptionCase.Language.hindi, .hinglish] {
            let texts = passages.filter { $0.language == language }.compactMap(\.devanagari)
            for count in texts.indices.map({ $0 + 1 }) {
                pieces.append(
                    TokenCapPiece(
                        id: "\(language.rawValue)-\(count)", language: language,
                        text: texts.prefix(count).joined(separator: " ")))
            }
        }
        return pieces
    }
}

/// One piece decoded once, with how long it ran and what the recogniser did to recover.
package struct TokenCapRow: Sendable, Equatable {
    package let piece: TokenCapPiece
    package let audioSeconds: Double
    package let transcriptWords: Int
    package let effort: DecodeEffort

    package init(piece: TokenCapPiece, audioSeconds: Double, transcriptWords: Int, effort: DecodeEffort) {
        self.piece = piece
        self.audioSeconds = audioSeconds
        self.transcriptWords = transcriptWords
        self.effort = effort
    }

    /// Whether the decode ran out of positions: the tail was decoded again, or no point to resume from was found.
    package var reachedCap: Bool { effort.retrySeconds > 0 || effort.capUnresolved }

    /// The words of the transcript against the words read, so a piece that lost its end shows as under 1.
    package var wordShare: Double { Double(transcriptWords) / Double(max(piece.words, 1)) }
}

/// The rows summed by how long the piece ran, as `Docs/hindi-token-cap.md` records them.
package struct TokenCapTable: Sendable {
    package let rows: [TokenCapRow]

    package init(rows: [TokenCapRow]) { self.rows = rows }

    /// The audio lengths the rows fall into, in seconds: the upper edge of each and its label.
    package static let lengths: [(edge: Double, label: String)] = [
        (10, "under 10 s"), (20, "10 to 20 s"), (30, "20 to 30 s"), (.infinity, "over 30 s"),
    ]

    /// One line per length: pieces, pieces that reached the cap, pieces left unresolved, and the mean decode again time and word share.
    package var markdown: String {
        var lines = [
            "| Piece length | Pieces | Reached the cap | Unresolved | Seconds decoding again | Words kept |",
            "|---|---|---|---|---|---|",
        ]
        var floor = 0.0
        for (edge, label) in Self.lengths {
            let group = rows.filter { $0.audioSeconds >= floor && $0.audioSeconds < edge }
            floor = edge
            guard !group.isEmpty else { continue }
            let count = Double(group.count)
            let cells = [
                label, "\(group.count)", "\(group.count { $0.reachedCap })",
                "\(group.count { $0.effort.capUnresolved })",
                String(format: "%.1f", group.reduce(0) { $0 + $1.effort.retrySeconds } / count),
                String(format: "%.0f%%", group.reduce(0) { $0 + $1.wordShare } / count * 100),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}

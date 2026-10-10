import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// One dictation writes every em dash in one style, whether the speaker named it or the recogniser wrote it, spaced or not.
@Suite("Dash style within one dictation")
struct DashStylePropertyTests {
    /// How an em dash between two clauses reaches the cleaner.
    enum Source: String, CaseIterable {
        case spoken, glued, spaced

        /// The two clauses joined by a dash from this source.
        func join(_ left: String, _ right: String) -> String {
            switch self {
            case .spoken:
                "\(left) \(SpokenCommands.marks.first { $0.text == Self.dash }?.words.joined(separator: " ") ?? "") \(right)"
            case .glued: "\(left)\(Self.dash)\(right)"
            case .spaced: "\(left) \(Self.dash) \(right)"
            }
        }

        static let dash = "\u{2014}"
    }

    /// Clauses that each open on a function word, so a spoken "dash" between them is the clause dash.
    static let clauses = ["we went home", "the night was late", "it was cold"]

    /// Every way of joining the three clauses with two dashes, named by their sources.
    static let dictations: [(name: String, spoken: String)] = Source.allCases.flatMap { first in
        Source.allCases.map { second in
            let spoken = second.join(first.join(clauses[0], clauses[1]), clauses[2])
            return ("\(first.rawValue) \(second.rawValue)", spoken)
        }
    }

    /// The styles of the em dashes in `text`: spaced on both sides, or glued on both.
    static func styles(in text: String) -> Set<String> {
        Set(
            text.indices.filter { String(text[$0]) == Source.dash }.map { index in
                let before = index > text.startIndex && text[text.index(before: index)].isWhitespace
                let next = text.index(after: index)
                let after = next < text.endIndex && text[next].isWhitespace
                return before == after ? (before ? "spaced" : "glued") : "lopsided"
            })
    }

    @Test("writes every em dash of one dictation in one style, in every destination")
    func oneStylePerDictation() async throws {
        var mixed: [String: [String]] = [:]
        for (name, spoken) in Self.dictations {
            for destination in Destination.allCases {
                let text = try await MarkSpacingMatrixTests.rulesText(spoken, in: destination)
                let styles = Self.styles(in: text)
                if styles.count > 1 || styles.contains("lopsided") {
                    mixed[name, default: []].append("\(destination.rawValue): \"\(text)\"")
                }
            }
        }
        let known = MarkSpacingKnownFaults.dashes
        for (name, texts) in mixed.sorted(by: { $0.key < $1.key }) where known[name] == nil {
            Issue.record("\(name): \(texts.joined(separator: "; "))")
        }
        for (name, issue) in known.sorted(by: { $0.key < $1.key }) where mixed[name] == nil {
            Issue.record(
                "\(name) now writes one style: take it off MarkSpacingKnownFaults.dashes (#\(issue))")
        }
    }
}

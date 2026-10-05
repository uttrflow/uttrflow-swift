public import UttrflowCore

/// Takes out each mark a rewrite added after a word where `MarkLegality` forbids one, keeping every word and every mark the input already had.
public enum AddedMarkCheck {
    /// One mark taken out: the word it followed, the mark, and the table row that refused it.
    public struct Removal: Sendable, Equatable {
        public let word: String
        public let mark: Character
        public let state: MarkLegality.TokenState
    }

    /// The rewrite with its illegal added marks taken out, and what was taken.
    public static func checked(_ rewritten: String, against input: String) -> (text: String, removed: [Removal]) {
        let kept = tokens(in: input)
        let written = tokens(in: rewritten)
        let pairs = pairing(kept.map(\.matching), written.map(\.matching))
        var removed: [Removal] = []
        var edits: [(range: Range<String.Index>, text: String)] = []
        for index in written.indices {
            let token = written[index]
            guard let mark = token.mark, let tableMark = marks[mark] else { continue }
            if let keptIndex = pairs[index], kept[keptIndex].mark == mark { continue }
            // At the end of a line nothing runs on, so the opens rows have nothing to hold open.
            guard index + 1 < written.count, token.followedOnSameLine else { continue }
            let state = MarkLegality.state(of: token.bare)
            guard MarkLegality.verdict(tableMark, after: state) == .illegal else { continue }
            removed.append(Removal(word: token.bare, mark: mark, state: state))
            edits.append((token.markRange, ""))
            if let next = recased(written[index + 1], keptAt: pairs[index + 1].map { kept[$0] }) {
                edits.append((written[index + 1].firstLetter, next))
            }
        }
        var text = rewritten
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            text.replaceSubrange(edit.range, with: edit.text)
        }
        return (text, removed)
    }

    private static let marks: [Character: MarkLegality.Mark] = [
        ".": .stop, "?": .question, "!": .exclamation, ",": .comma, ":": .colon,
    ]

    private struct Token {
        let bare: String
        let matching: String
        let mark: Character?
        let markRange: Range<String.Index>
        let firstLetter: Range<String.Index>
        let followedOnSameLine: Bool
    }

    /// The input's first letter back on a word the rewrite capitalised only because of the stop it added.
    private static func recased(_ next: Token, keptAt kept: Token?) -> String? {
        guard let kept, let first = kept.bare.first, let now = next.bare.first,
            first.isLowercase, now.isUppercase
        else { return nil }
        return String(first)
    }

    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var start = text.startIndex
        while start < text.endIndex {
            guard !text[start].isWhitespace else {
                start = text.index(after: start)
                continue
            }
            var end = start
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let word = String(text[start..<end])
            let last = text.index(before: end)
            let mark = marks[text[last]] != nil && word.count > 1 ? text[last] : nil
            let bareEnd = mark == nil ? end : last
            let bare = String(text[start..<bareEnd])
            let letter = text[start..<bareEnd].firstIndex(where: \.isLetter) ?? start
            let gap = text[end...].prefix(while: \.isWhitespace)
            result.append(
                Token(
                    bare: bare,
                    matching: bare.lowercased().filter { $0.isLetter || $0.isNumber },
                    mark: mark, markRange: last..<end,
                    firstLetter: letter..<(letter < bareEnd ? text.index(after: letter) : letter),
                    followedOnSameLine: !gap.contains(where: \.isNewline)))
            start = end
        }
        return result
    }

    /// For each rewritten word, the input word it is, by the longest run of words the two share in order.
    private static func pairing(_ kept: [String], _ written: [String]) -> [Int?] {
        let rows = kept.count, columns = written.count
        var length = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                length[row][column] =
                    kept[row] == written[column] && !kept[row].isEmpty
                    ? length[row + 1][column + 1] + 1
                    : max(length[row + 1][column], length[row][column + 1])
            }
        }
        var pairs = [Int?](repeating: nil, count: columns)
        var row = 0, column = 0
        while row < rows, column < columns {
            if kept[row] == written[column], !kept[row].isEmpty {
                pairs[column] = row
                row += 1
                column += 1
            } else if length[row + 1][column] >= length[row][column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return pairs
    }
}

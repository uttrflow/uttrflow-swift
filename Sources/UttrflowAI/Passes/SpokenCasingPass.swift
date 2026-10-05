public import UttrflowCore

/// Writes the words a spoken casing command covers in the style it names, and drops the command.
public struct SpokenCasingPass: PieceCleaningPass {
    public static let id: PassID = .spokenCasing

    /// Where the words are going, which picks the table rows that apply.
    let destination: Destination

    public init(destination: Destination) {
        self.destination = destination
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var position = 0
        while position < draft.presentIndices.count {
            let live = draft.presentIndices
            if let cased = casing(at: position, in: live, of: draft) {
                apply(cased, at: position, in: live, to: &draft)
            }
            position += 1
        }
        return draft
    }

    private enum Style: String {
        case camel, snake, kebab, upper, hashtag
    }

    /// One command found: the words it covers and how many trailing words close it.
    private struct Cased {
        let style: Style
        let named: Int
        let covered: Range<Int>
        let closing: Int
    }

    private func casing(at position: Int, in live: [Int], of draft: Draft) -> Cased? {
        for row in SpokenCommands.casings where row.isEnabled(in: destination) {
            guard draft.spells(row.words, at: position, in: live, acrossSentences: row.reach == .clause),
                let style = Style(rawValue: row.text)
            else { continue }
            let start = position + row.words.count
            if row.reach != .clause,
                MentionGuard.namesCasing(at: position, spanning: row.words.count, in: live, of: draft)
            {
                return nil
            }
            guard let (covered, closing) = Self.reach(of: row, from: start, in: live, of: draft) else {
                return nil
            }
            return Cased(style: style, named: row.words.count, covered: covered, closing: closing)
        }
        return nil
    }

    /// The words a row covers from `start`, and the length of the closing phrase after them.
    private static func reach(
        of row: SpokenCommand, from start: Int, in live: [Int], of draft: Draft
    ) -> (Range<Int>, Int)? {
        switch row.reach {
        case .clause:
            var end = start
            while end < live.count {
                let shape = draft.shape(at: live[end])
                if isSpokenClauseWord(shape) { break }
                end += 1
                if shape.endsClause || WordShape.trailsOff(shape.suffix) { break }
            }
            return end > start ? (start..<end, 0) : nil
        case .word:
            guard start < live.count, !isSpokenClauseWord(draft.shape(at: live[start])) else { return nil }
            return (start..<(start + 1), 0)
        case .pause:
            var end = start
            while end < live.count {
                let shape = draft.shape(at: live[end])
                if isSpokenClauseWord(shape) { break }
                if end > start, let pause = draft.pause(before: live[end]), pause >= tagPause { break }
                end += 1
                if shape.endsClause || WordShape.trailsOff(shape.suffix) { break }
            }
            return end > start ? (start..<end, 0) : nil
        case .span:
            let sentenceEnd = draft.sentenceRun(from: start, in: live).upperBound
            for end in start..<sentenceEnd where end > start && draft.spells(row.until, at: end, in: live) {
                return (start..<end, row.until.count)
            }
            return nil
        }
    }

    /// The silence after which the speaker has left a tag; the words before it are the tag's.
    static let tagPause: Duration = .milliseconds(300)

    private static func isSpokenClauseWord(_ shape: WordShape) -> Bool {
        SpokenCommands.marks.contains { $0.placement == .trailing && $0.words == [shape.key] }
    }

    private func apply(_ cased: Cased, at position: Int, in live: [Int], to draft: inout Draft) {
        let values = cased.covered.map { draft.shape(at: live[$0]).core }
        let last = cased.covered.upperBound - 1 + cased.closing
        let suffix = draft.shape(at: live[last]).suffix
        switch cased.style {
        case .camel:
            let joined = values.enumerated().map { index, value in
                index == 0 ? value.lowercased() : WordShape.capitalised(value.lowercased())
            }.joined()
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
        case .snake:
            let joined = values.map { $0.lowercased() }.joined(separator: "_")
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
        case .kebab:
            let joined = values.map { $0.lowercased() }.joined(separator: "-")
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
        case .hashtag:
            let joined = "#" + values.map { $0.lowercased() }.joined()
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
        case .upper:
            let closingSuffix = cased.closing > 0 ? suffix : ""
            for index in cased.covered {
                let shape = draft.shape(at: live[index])
                let tail = index == cased.covered.upperBound - 1 ? shape.suffix + closingSuffix : shape.suffix
                let upper = shape.prefix + shape.core.uppercased() + tail
                draft.replace(at: live[index], with: upper, by: Self.id)
            }
            for offset in 0..<cased.named { draft.remove(at: live[position + offset], by: Self.id) }
            for index in cased.covered.upperBound..<(last + 1) { draft.remove(at: live[index], by: Self.id) }
        }
    }

    /// Writes one identifier in place of the command and the words it covers.
    private func write(_ text: String, over range: Range<Int>, in live: [Int], to draft: inout Draft) {
        draft.replace(at: live[range.lowerBound], with: text, by: Self.id)
        for index in range.dropFirst() { draft.remove(at: live[index], by: Self.id) }
    }
}

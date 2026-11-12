public import UttrflowCore

/// Writes the words a spoken casing command covers in the style it names, and drops the command.
public struct SpokenCasingPass: PieceCleaningPass {
    public static let id: PassID = .spokenCasing
    public static let laws: Set<PassLaw> = [.idempotent, .keepsDigits, .latinOnly]
    public static let orderIndependentWith: Set<PassID> = [.layoutWords]

    /// Where the words are going, which picks the table rows that apply.
    let destination: Destination
    /// The style the file writes each kind of name in, which completes a naming cue said without a style.
    let naming: NamingConvention

    public init(destination: Destination) {
        self.init(destination: destination, naming: .infer(from: .empty, language: nil))
    }

    init(destination: Destination, naming: NamingConvention) {
        self.destination = destination
        self.naming = naming
    }

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            if let cased = casing(at: position, in: live, of: draft) {
                apply(cased, at: position, in: &live, to: &draft)
            }
            position += 1
        }
        return draft
    }

    private enum Style: String {
        case camel, snake, kebab, upper, hashtag
        case nameValue = "name.value", nameType = "name.type", nameConstant = "name.constant"

        /// The joined style a spoken identifier command writes; the other commands join no words.
        var nameStyle: NameStyle {
            switch self {
            case .snake: .snake
            case .kebab: .kebab
            default: .camel
            }
        }

        /// Whether the command names a joined style itself, which a naming cue said just before it takes.
        var isIdentifierStyle: Bool { self == .camel || self == .snake || self == .kebab }

        /// The kind of name a naming cue asks for, which picks the file's style for it.
        var role: NameRole? {
            switch self {
            case .nameValue: .value
            case .nameType: .type
            case .nameConstant: .constant
            default: nil
            }
        }
    }

    /// One command found: the words it covers, how many trailing words close it, and a naming cue's finished name.
    private struct Cased {
        let style: Style
        let named: Int
        let covered: Range<Int>
        let closing: Int
        var written: String?
    }

    private func casing(at position: Int, in live: [Int], of draft: Draft) -> Cased? {
        for row in SpokenCommands.casings where row.isEnabled(in: destination) {
            guard draft.spells(row.words, at: position, in: live, acrossSentences: row.reach == .clause),
                let style = Style(rawValue: row.text)
            else { continue }
            let start = position + row.words.count
            if MentionGuard.namesCasing(at: position, spanning: row.words.count, in: live, of: draft) {
                return nil
            }
            if let role = style.role {
                return name(role, style: style, at: position, from: start, in: live, of: draft)
            }
            guard let (covered, closing) = Self.reach(of: row, from: start, in: live, of: draft) else {
                return nil
            }
            return Cased(style: style, named: row.words.count, covered: covered, closing: closing)
        }
        return nil
    }

    /// A naming cue: the plain words after it as one name, in a style said right after the cue, else the file's for `role`.
    private func name(
        _ role: NameRole, style: Style, at position: Int, from cueEnd: Int, in live: [Int], of draft: Draft
    ) -> Cased? {
        var start = cueEnd
        let said = SpokenCommands.casings.lazy.compactMap { row -> (NameStyle, Int)? in
            guard row.isEnabled(in: self.destination), let spoken = Style(rawValue: row.text),
                spoken.isIdentifierStyle, draft.spells(row.words, at: cueEnd, in: live)
            else { return nil }
            return (spoken.nameStyle, row.words.count)
        }.first
        start += said?.1 ?? 0
        let end = Self.nameEnd(from: start, in: live, of: draft)
        let words = (start..<end).map { draft.shape(at: live[$0]).core }
        guard let written = naming.name(words, role: role, explicit: said?.0) else { return nil }
        return Cased(style: style, named: start - position, covered: start..<end, closing: 0, written: written)
    }

    /// The end of the plain words from `start` that one name can hold: a mark, a symbol or the clause's end closes it.
    private static func nameEnd(from start: Int, in live: [Int], of draft: Draft) -> Int {
        var end = start
        while end < live.count {
            let shape = draft.shape(at: live[end])
            let plain = !shape.core.isEmpty && shape.core.allSatisfy { $0.isLetter || $0.isNumber }
            if isSpokenClauseWord(shape) || !plain || (end > start && !shape.prefix.isEmpty) { break }
            end += 1
            if !shape.suffix.isEmpty || shape.endsClause { break }
        }
        return end
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
                // The command said again ends this tag and starts the next one.
                if end > start, draft.spells(row.words, at: end, in: live) { break }
                if end > start, let pause = draft.pause(before: live[end]), pause >= tagPause { break }
                // Untimed words give no pause to end on, so the tag ends where a small word resumes the sentence.
                if end > start, draft.pause(before: live[end]) == nil, FunctionWords.holds(shape.core) {
                    break
                }
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

    private func apply(_ cased: Cased, at position: Int, in live: inout [Int], to draft: inout Draft) {
        let values = cased.covered.map { draft.shape(at: live[$0]).core }
        let last = cased.covered.upperBound - 1 + cased.closing
        let suffix = draft.shape(at: live[last]).suffix
        switch cased.style {
        case .camel, .snake, .kebab, .nameValue, .nameType, .nameConstant:
            let joined = cased.written ?? cased.style.nameStyle.write(values)
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
            live.removeSubrange((position + 1)..<(last + 1))
        case .hashtag:
            let joined = "#" + values.map { $0.lowercased() }.joined()
            write(joined + suffix, over: position..<(last + 1), in: live, to: &draft)
            live.removeSubrange((position + 1)..<(last + 1))
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
            live.removeSubrange(cased.covered.upperBound..<(last + 1))
            live.removeSubrange(position..<(position + cased.named))
        }
    }

    /// Writes one identifier in place of the command and the words it covers.
    private func write(_ text: String, over range: Range<Int>, in live: [Int], to draft: inout Draft) {
        draft.replace(at: live[range.lowerBound], with: text, by: Self.id)
        for index in range.dropFirst() { draft.remove(at: live[index], by: Self.id) }
    }
}

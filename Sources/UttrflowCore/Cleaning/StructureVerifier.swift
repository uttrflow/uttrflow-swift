/// Takes out, leaving every word, each break or list mark of a laid-out draft that has no evidence or stands where it cannot; a spoken break is not judged by place.
public enum StructureVerifier {
    /// Which rule took a break out.
    public enum Reason: Sendable, Equatable {
        /// Nothing recorded why the break was written.
        case untagged
        /// The words before it do not make a complete sentence.
        case incompleteSentence
        /// It falls inside a bracket or a quotation.
        case insideSpan
        /// It falls between the digits of one number.
        case insideNumber
        /// It falls between two parts of an address or other technical token.
        case insideAddress
        /// An inferred list has fewer than two items.
        case loneList
        /// An item of an inferred list is not a clause.
        case itemNotClause
        /// The text holds more inferred paragraph breaks than its destination allows.
        case overBudget
    }

    /// One break taken out, by its position in the draft's words.
    public struct Removal: Sendable, Equatable {
        public let index: Int
        public let reason: Reason
    }

    /// The fewest words an inferred list item holds to read as a clause.
    static let clauseWords = 2

    /// The draft with every unjustified break taken out, and what was taken.
    public static func verified(
        _ draft: Draft, breaksPer100Words: Int, by pass: PassID
    ) -> (draft: Draft, removed: [Removal]) {
        var draft = draft
        var removed: [Removal] = []
        func drop(_ index: Int, _ reason: Reason) {
            guard draft.words[index].isPresent else { return }
            draft.remove(at: index, by: pass)
            removed.append(Removal(index: index, reason: reason))
        }
        for index in draft.presentIndices where isMark(draft.words[index]) {
            guard let evidence = draft.words[index].breakEvidence else {
                drop(index, .untagged)
                continue
            }
            if !evidence.isSpoken, !draft.words[index].isListMark,
                let reason = illegal(at: index, in: draft)
            {
                drop(index, reason)
            }
        }
        for (index, reason) in inferredListDrops(in: draft) { drop(index, reason) }
        for index in overBudget(in: draft, perHundred: breaksPer100Words) { drop(index, .overBudget) }
        return (draft, removed)
    }

    private static func isMark(_ word: Draft.Word) -> Bool {
        word.isLayoutMark && !word.isLabelledItemMark
    }

    // MARK: Where a break cannot stand

    /// The rule a paragraph or line break at `index` breaks by its place, or nil when it stands legally.
    private static func illegal(at index: Int, in draft: Draft) -> Reason? {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: index),
            let before = live[..<position].last(where: { !draft.words[$0].isLayoutMark })
        else { return nil }
        if !completesSentence(at: before, in: draft) { return .incompleteSentence }
        if opensSpan(through: before, in: draft, live: live) { return .insideSpan }
        guard position + 1 < live.count, !draft.words[live[position + 1]].isLayoutMark else { return nil }
        let after = live[position + 1]
        let last = draft.shape(at: before)
        let first = draft.shape(at: after)
        if !last.endsSentence, isNumeric(last.core), isNumeric(first.core) { return .insideNumber }
        if !last.endsSentence, MarkLegality.state(of: draft.words[before].text) == .technical,
            MarkLegality.state(of: draft.words[after].text) == .technical
        {
            return .insideAddress
        }
        return nil
    }

    /// Whether the word ends a sentence: a stop it carries, or a word the legality table lets one follow.
    private static func completesSentence(at index: Int, in draft: Draft) -> Bool {
        let text = draft.words[index].text
        if let mark = text.last, ",;:".contains(mark) { return false }
        let state = MarkLegality.state(of: text)
        if draft.shape(at: index).endsSentence { return state != .leadingAbbreviation }
        return MarkLegality.verdict(.stop, after: state) != .illegal
    }

    private static let openers: Set<Character> = ["(", "[", "{", "\u{201C}"]
    private static let closers: Set<Character> = [")", "]", "}", "\u{201D}"]

    /// Whether a bracket or quotation opened in the words up to `index` is still open there.
    private static func opensSpan(through index: Int, in draft: Draft, live: [Int]) -> Bool {
        var depth = 0
        var straight = 0
        for word in live where word <= index && !draft.words[word].isLayoutMark {
            for character in draft.words[word].text {
                if openers.contains(character) { depth += 1 }
                if closers.contains(character) { depth -= 1 }
                if character == "\"" { straight += 1 }
            }
        }
        return depth > 0 || straight % 2 == 1
    }

    private static func isNumeric(_ core: String) -> Bool {
        !core.isEmpty && core.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
    }

    // MARK: Lists

    /// Takes the marks out of an inferred list that has fewer than two items or an item that is not a clause.
    private static func inferredListDrops(in draft: Draft) -> [(Int, Reason)] {
        var drops: [(Int, Reason)] = []
        var run: [Int] = []
        var runs: [[Int]] = []
        for index in draft.presentIndices where isMark(draft.words[index]) {
            if draft.words[index].isListMark {
                run.append(index)
            } else if !run.isEmpty {
                runs.append(run)
                run = []
            }
        }
        if !run.isEmpty { runs.append(run) }
        for items in runs {
            let inferred = items.contains { draft.words[$0].breakEvidence?.isInferred == true }
            guard inferred else { continue }
            var reason: Reason?
            if items.count < 2 {
                reason = .loneList
            } else if items.contains(where: { wordsInItem(at: $0, in: draft) < clauseWords }) {
                reason = .itemNotClause
            }
            guard let reason else { continue }
            for index in items { drops.append((index, reason)) }
            // The blank line that closed the list closed nothing once its items are gone.
            if let last = items.last, let closing = breakEnding(itemAt: last, in: draft),
                draft.words[closing].breakEvidence == .ordinalEnumeration
            {
                drops.append((closing, reason))
            }
        }
        return drops
    }

    /// The words an item holds, up to the next mark of any kind.
    private static func wordsInItem(at index: Int, in draft: Draft) -> Int {
        draft.presentIndices.filter { $0 > index }.prefix { !isMark(draft.words[$0]) }.count
    }

    /// The paragraph break straight after the words of the item opened at `index`, if one follows.
    private static func breakEnding(itemAt index: Int, in draft: Draft) -> Int? {
        draft.presentIndices.filter { $0 > index }.first(where: { isMark(draft.words[$0]) })
            .flatMap { draft.words[$0].isListMark ? nil : $0 }
    }

    // MARK: Budget

    /// Takes out the weakest inferred paragraph breaks until the text holds no more than its destination's budget.
    private static func overBudget(in draft: Draft, perHundred: Int) -> [Int] {
        let live = draft.presentIndices
        let spoken = live.count { !draft.words[$0].isLayoutMark }
        let allowed = perHundred <= 0 ? 0 : max(1, (spoken * perHundred + 99) / 100)
        let inferred = live.filter { index in
            guard isMark(draft.words[index]), !draft.words[index].isListMark else { return false }
            switch draft.words[index].breakEvidence {
            case .longPause, .topicCue: return true
            default: return false
            }
        }
        guard inferred.count > allowed else { return [] }
        // A pause is weaker evidence than a topic cue, a short one weaker than a long one, and a later break loses to an earlier.
        let weakest = inferred.sorted { strength(draft.words[$0], $0) < strength(draft.words[$1], $1) }
        return Array(weakest.prefix(inferred.count - allowed))
    }

    private static func strength(_ word: Draft.Word, _ index: Int) -> (Int, Duration, Int) {
        switch word.breakEvidence {
        case .longPause(let length): (0, length, -index)
        default: (1, .zero, -index)
        }
    }
}

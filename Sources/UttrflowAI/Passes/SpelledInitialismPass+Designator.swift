import UttrflowCore

/// Reads letters beside one number as one code only with evidence: a designator before it, or a known code.
extension SpelledInitialismPass {
    /// A word that names what follows it as a code, and the kind its letters then number are written as.
    static let designators: [String: LetterRun.Kind] = [
        "gate": .code, "seat": .code, "row": .code, "room": .code, "flat": .code, "apartment": .code,
        "suite": .code, "terminal": .code, "plan": .code, "priority": .code, "size": .code,
        "quarter": .code, "flight": .spacedCode,
    ]

    /// Determiners that are never a pronoun or a conjunction, so an "a" after one is a letter: "the a four paper".
    static let articlesBeforeLetter = FunctionWords.determiners.intersection(FunctionWords.prose)
        .subtracting(["a"])

    /// The draft with every evidenced letter and number pair written as one code.
    static func joinDesignatedCodes(in draft: Draft, initialisms: Set<Int>) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let code = designatedCode(at: position, in: live, draft: draft, initialisms: initialisms)
            else {
                position += 1
                continue
            }
            let first = draft.words[live[position]].text
            write(
                LetterRun.written(code.pieces, as: code.kind, first: first),
                over: live[position..<(position + code.count)], in: &draft)
            live.removeSubrange((position + 1)..<(position + code.count))
            position += 1
        }
        return draft
    }

    /// The code starting at `position`, its pieces and kind and how many words it spans, or nil without evidence.
    private static func designatedCode(
        at position: Int, in live: [Int], draft: Draft, initialisms: Set<Int>
    ) -> (pieces: [String], kind: LetterRun.Kind, count: Int)? {
        let previous = position > 0 ? draft.shape(at: live[position - 1]) : nil
        let designated = previous.flatMap { $0.endsClause ? nil : designators[$0.key] }
        let afterArticle = previous.map { !$0.endsClause && articlesBeforeLetter.contains($0.key) } ?? false
        var before: [String] = []
        var end = position
        let joins = { (i: Int) in
            i == position
                || adjoins(live[i - 1], live[i], in: draft) && !draft.shape(at: live[i - 1]).endsClause
                    && !draft.words[live[i]].isLayoutMark
        }
        while end < live.count, joins(end), let letters = codeLetters(at: live[end], in: draft, initialisms) {
            // The article or the pronoun before a number is a word, never a letter, unless it follows an article.
            if end == position, ["a", "i"].contains(draft.shape(at: live[end]).key),
                !(afterArticle && draft.shape(at: live[end]).key == "a")
            {
                return nil
            }
            before.append(letters)
            end += 1
        }
        guard end < live.count, joins(end), let number = number(draft.shape(at: live[end])) else {
            return nil
        }
        end += 1
        var after: [String] = []
        while end < live.count, joins(end),
            let letters = codeLetters(at: live[end], in: draft, initialisms)
        {
            let shape = draft.shape(at: live[end])
            let closes = shape.endsClause || end + 1 == live.count
            // A trailing "a" or "I" is the next phrase's article or pronoun unless the clause ends on it.
            if ["a", "i"].contains(shape.key), !closes { break }
            after.append(letters)
            end += 1
            if closes { break }
        }
        guard !before.isEmpty || !after.isEmpty else { return nil }
        if before.isEmpty, end - position == 1 { return nil }
        let letters = before.joined()
        if let designated {
            return after.isEmpty
                ? ([letters, number], designated, end - position)
                : ([letters, number] + after, .code, end - position)
        }
        let pieces = [letters, number] + after
        let isKnown = LetterRun.knownCodes[pieces.joined().lowercased()] != nil
        guard isKnown, after.isEmpty || before.isEmpty else { return nil }
        return (pieces, .knownCode, end - position)
    }

    /// Whether nothing but words removed by this pass or by the number pass lies between two words.
    private static func adjoins(_ left: Int, _ right: Int, in draft: Draft) -> Bool {
        (left + 1..<right).allSatisfy {
            draft.words[$0].state == .removed(by: id)
                || draft.words[$0].state == .removed(by: NumberFormsPass.id)
        }
    }

    /// The upper-case letters a word adds to a code: one letter name, or an initialism from this pass.
    private static func codeLetters(at index: Int, in draft: Draft, _ initialisms: Set<Int>) -> String? {
        let shape = draft.shape(at: index)
        if initialisms.contains(index) { return shape.core.uppercased() }
        guard shape.key.count == 1, !shape.isCutOff else { return nil }
        return LetterRun.letter(named: shape.key)
    }

    /// A whole number, spoken or in digits, as read by `NumberWords`.
    private static func number(_ shape: WordShape) -> String? {
        if !shape.key.isEmpty, shape.key.allSatisfy({ $0.isASCII && $0.isNumber }) { return shape.key }
        guard let read = NumberWords.cardinal([shape.key][...]), read.count == 1 else { return nil }
        return String(read.value)
    }
}

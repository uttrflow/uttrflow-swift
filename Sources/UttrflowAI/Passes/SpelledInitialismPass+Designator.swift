import UttrflowCore

/// Reads letters beside one number as one code only with evidence: a designator before it, or a known code.
extension SpelledInitialismPass {
    /// A word that names what follows it as a code, and the joiner between its letters and number.
    static let designators: [String: String] = [
        "gate": "", "seat": "", "row": "", "room": "", "flat": "", "apartment": "", "suite": "",
        "terminal": "", "plan": "", "priority": "", "size": "", "quarter": "",
        // An airline code and its flight number take a space: "UA 472".
        "flight": " ",
    ]

    /// Codes that need no designator, keyed by their letters and digits in lower case, with their written form.
    static let knownCodes: [String: String] = [
        "q1": "Q1", "q2": "Q2", "q3": "Q3", "q4": "Q4", "h1": "H1", "h2": "H2",
        "p0": "P0", "p1": "P1", "p2": "P2", "p3": "P3", "p4": "P4",
        "4k": "4K", "3d": "3D", "b12": "B12", "spo2": "SpO2",
    ]

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
            let last = live[position + code.count - 1]
            let closing = draft.shape(at: last).suffix
            draft.replace(
                at: live[position],
                with: closing.isEmpty ? code.text : WordShape.marked(code.text, with: closing),
                by: id)
            for index in live[(position + 1)..<(position + code.count)] { draft.remove(at: index, by: id) }
            live.removeSubrange((position + 1)..<(position + code.count))
            position += 1
        }
        return draft
    }

    /// The code starting at `position` and how many words it spans, or nil without evidence.
    private static func designatedCode(
        at position: Int, in live: [Int], draft: Draft, initialisms: Set<Int>
    ) -> (text: String, count: Int)? {
        let previous = position > 0 ? draft.shape(at: live[position - 1]) : nil
        let joiner = previous.flatMap { $0.endsClause ? nil : designators[$0.key] }
        var before: [String] = []
        var end = position
        let joins = { (i: Int) in
            i == position
                || adjoins(live[i - 1], live[i], in: draft) && !draft.shape(at: live[i - 1]).endsClause
                    && !draft.words[live[i]].isLayoutMark
        }
        while end < live.count, joins(end), let letters = codeLetters(at: live[end], in: draft, initialisms) {
            // The article or the pronoun before a number is a word, never a letter.
            if end == position, ["a", "i"].contains(draft.shape(at: live[end]).key) { return nil }
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
        if let joiner {
            let text = after.isEmpty ? letters + joiner + number : letters + number + after.joined()
            return (text, end - position)
        }
        guard after.isEmpty, let known = knownCodes[(letters + number).lowercased()] else {
            guard before.isEmpty, let known = knownCodes[(number + after.joined()).lowercased()] else {
                return nil
            }
            return (known, end - position)
        }
        return (known, end - position)
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

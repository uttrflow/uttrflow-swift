import UttrflowCore

extension CodeEditorCommandsPass {
    /// The markup row the words at `position` say in `slot`, if any; a tag opens only where the speech spells a whole tag.
    func markupRow(at position: Int, in live: [Int], of draft: Draft, slot: MarkupSlot) -> SpokenCommand? {
        let row = SpokenCommands.markup.first {
            ($0.slots?.contains(slot) ?? false) && $0.isEnabled(for: language)
                && draft.spells($0.words, at: position, in: live, acrossSentences: true)
        }
        guard let row else { return nil }
        guard slot == .text, row.enters == .tag else { return row }
        let spoken = live[position...].map { Self.markupKey(draft.words[$0].text) }
        return NotationEvidence.spellsTag(spoken, at: 0) ? row : nil
    }

    /// Writes a markup row over its spoken name and returns the position of the next word to read.
    func write(_ command: SpokenCommand, at position: Int, in live: [Int], to draft: inout Draft) -> Int {
        let consumed = command.words.count
        let last = position + consumed - 1
        // A stop the recogniser put after the last spoken word does not end a tag, a rule or a declaration.
        let suffix = draft.shape(at: live[last]).suffix.filter { !".?!".contains($0) }
        let after = position + consumed
        let hasNext = after < live.count
        let hasPrevious = position > 0
        if command.bindsQuote, hasPrevious,
            let quoted = quotedValue(from: after, in: live, of: draft)
        {
            let left = draft.words[live[position - 1]].text
            draft.replace(
                at: live[position - 1], with: left + command.text + quoted.value + quoted.suffix, by: Self.id)
            for offset in position..<quoted.end { draft.remove(at: live[offset], by: Self.id) }
            return position
        }
        var placement = command.placement
        if placement == .joining {
            let joins =
                hasPrevious && hasNext && Self.isToken(draft.words[live[position - 1]].text)
                && Self.isToken(draft.words[live[after]].text)
            placement = joins ? .joining : hasNext ? .leading : .standalone
        }
        if placement == .trailing, !hasPrevious { placement = .standalone }
        if placement == .leading, !hasNext { placement = .standalone }
        switch placement {
        case .joining:
            let left = draft.words[live[position - 1]].text
            let right = draft.words[live[after]].text
            draft.replace(at: live[position - 1], with: left + command.text + right, by: Self.id)
            for offset in position...after { draft.remove(at: live[offset], by: Self.id) }
            return position
        case .leading:
            draft.replace(at: live[after], with: command.text + draft.words[live[after]].text, by: Self.id)
            for offset in position..<after { draft.remove(at: live[offset], by: Self.id) }
            return position + 1
        case .trailing:
            let before = draft.words[live[position - 1]].text
            draft.replace(at: live[position - 1], with: before + command.text + suffix, by: Self.id)
            for offset in position...last { draft.remove(at: live[offset], by: Self.id) }
            return position
        default:
            draft.replace(at: live[position], with: command.text + suffix, by: Self.id)
            if consumed > 1 {
                for offset in (position + 1)...last { draft.remove(at: live[offset], by: Self.id) }
            }
            return position + 1
        }
    }

    /// The quotation spoken from `start`, written as one value, and where it ends; `nil` when no quote is opened and closed in reach.
    private func quotedValue(
        from start: Int, in live: [Int], of draft: Draft
    ) -> (value: String, suffix: String, end: Int)? {
        let quotes = SpokenCommands.marks.filter { $0.text == "\"" }
        let opening = quotes.first { $0.placement == .opening && draft.spells($0.words, at: start, in: live) }
        guard let opening else { return nil }
        let first = start + opening.words.count
        let limit = min(live.count, first + Self.maximumValueWords)
        for end in first..<limit {
            guard
                let closing = quotes.first(where: {
                    $0.placement == .closing && draft.spells($0.words, at: end, in: live)
                })
            else { continue }
            let value = Self.valueText(of: (first..<end).map { draft.words[live[$0]].text })
            let suffix = draft.shape(at: live[end + closing.words.count - 1]).suffix.filter {
                !".?!".contains($0)
            }
            return ("\"" + value + "\"", suffix, end + closing.words.count)
        }
        return nil
    }

    /// The most words an attribute's quoted value is said in.
    private static let maximumValueWords = 8

    /// A value's words written as one run, a spoken mark between two words joining them as in a name.
    private static func valueText(of words: [String]) -> String {
        let joins = SpokenCommands.markup.filter { $0.placement == .joining && $0.words.count == 1 }
        var text = ""
        var joined = true
        for word in words {
            if let mark = joins.first(where: { $0.words == [bare(word)] }) {
                text += mark.text
                joined = true
            } else {
                text += (joined ? "" : " ") + word
                joined = false
            }
        }
        return text
    }

    /// A spoken word as a markup row reads it: lower case, with the marks around it removed and its digits kept, as the "1" of "h1" is.
    static func markupKey(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .alphanumerics.inverted)
    }

    /// A word a tag, a selector or an attribute can hold on either side of a joining mark.
    private static func isToken(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: .punctuationCharacters)
        return !core.isEmpty && core.allSatisfy { $0.isLetter || $0.isNumber || "_-.:/#=".contains($0) }
    }
}

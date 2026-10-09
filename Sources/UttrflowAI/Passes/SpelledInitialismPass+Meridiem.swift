import UttrflowCore

/// Writes a meridiem after a clock time in the one house form, "am" or "pm", whatever form it arrived in.
extension SpelledInitialismPass {
    /// The draft with every "AM", "a.m." or "P.M." after a clock time written as a meridiem run.
    static func writingMeridiems(in draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        for position in live.indices.dropFirst() {
            let index = live[position]
            let shape = draft.shape(at: index)
            guard shape.prefix.isEmpty, NumberFormsPass.meridiems.contains(shape.key),
                isClockTime(draft.shape(at: live[position - 1]))
            else { continue }
            let text = draft.words[index].text
            let next = position + 1 < live.count ? draft.words[live[position + 1]].text : nil
            var suffix = shape.suffix
            // A dotted form's stop belongs to the abbreviation unless it also ends the sentence.
            if shape.key.contains("."), suffix.hasPrefix("."),
                next == nil || !Abbreviations.endsSentence(text, followedBy: next)
            {
                suffix.removeFirst()
            }
            let letters = shape.key.filter { $0 != "." }.map(String.init)
            let written = LetterRun.written(letters, as: .meridiem, first: text) + suffix
            if written != text { draft.replace(at: index, with: written, by: id) }
        }
        return draft
    }

    /// An hour, or an hour and minutes, in digits: "5", "10:30".
    static func isClockTime(_ shape: WordShape) -> Bool {
        guard shape.suffix.isEmpty else { return false }
        let parts = shape.core.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts[0].count <= 2, let hour = Int(parts[0]),
            (0...23).contains(hour)
        else { return false }
        guard parts.count == 2 else { return true }
        return parts[1].count == 2 && Int(parts[1]).map { (0...59).contains($0) } == true
    }
}

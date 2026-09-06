// Puts one recorded correction back into a dictation's text and names the dictionary entry to charge.
public import struct Foundation.UUID

/// Undoes one correction on a copy of the record, so no field is forgotten on the way.
extension DictationRecord {
    /// A copy with the change put back and its entry to charge, or `nil`. See Docs/core-history-undo.md.
    public func undoing(_ correction: UUID) -> (record: DictationRecord, entryID: UUID)? {
        guard let changes,
            let target = changes.corrections.firstIndex(where: { $0.id == correction }),
            !changes.corrections[target].isUndone
        else { return nil }

        let reverted = changes.corrections[target]
        var undone = self
        // Read before the flag flips, so this change's words are still located where they were written.
        undone.text = restoring(reverted, among: changes.corrections)
        undone.changes?.corrections[target].isUndone = true
        return (undone, reverted.entryID)
    }

    /// ``text`` with the reverted words put back, or unchanged when they are not where the ranges say.
    private func restoring(
        _ reverted: RecordedCorrection, among corrections: [RecordedCorrection]
    ) -> String {
        let words = text.spokenWordRanges()
        var start = 0
        var length = 0
        var shift = 0

        for correction in corrections.sorted(by: { $0.wordRange.lowerBound < $1.wordRange.lowerBound }) {
            let standing = correction.isUndone ? correction.heard : correction.wrote
            let count = standing.spokenWords().count
            if correction.id == reverted.id {
                start = correction.wordRange.lowerBound + shift
                length = count
                break
            }
            shift += count - correction.wordRange.count
        }

        guard length > 0, start >= 0, start + length <= words.count else { return text }
        let span = words[start].lowerBound..<words[start + length - 1].upperBound
        // Anything but the written words means this text is not the one the range was measured against.
        guard text[span].spokenWords() == reverted.wrote.spokenWords() else { return text }

        var repaired = String(text[text.startIndex..<span.lowerBound])
        repaired += reverted.heard
        repaired += text[span.upperBound...]
        return repaired
    }
}

/// Splits words the way the pipeline counts an utterance, so a correction's range indexes the same words.
extension StringProtocol {
    /// The whitespace-separated words of this text; splitting on letters would put "don't" at two indices.
    fileprivate func spokenWords() -> [SubSequence] {
        split(whereSeparator: \.isWhitespace)
    }
}

/// Word positions for splicing.
extension String {
    /// Where each spoken word of this text begins and ends.
    fileprivate func spokenWordRanges() -> [Range<String.Index>] {
        spokenWords().map { $0.startIndex..<$0.endIndex }
    }
}

public import struct Foundation.UUID

extension DictationRecord {
    /// This dictation with one change put back, and the dictionary entry to blame for it.
    ///
    /// The entry identifier is the point of the whole call. `PersonalDictionaryStore`
    /// counts reverts against the entry that caused them, and a word the user keeps
    /// rejecting retires itself on that count — so an undo that only crossed out a row
    /// would leave the bad word in the dictionary to be applied again tomorrow. Handing
    /// the identifier back is what makes the undo mean something.
    ///
    /// The text is put back too, spliced by character range and never rebuilt by
    /// rejoining words with spaces: everything between the words — newlines,
    /// indentation, the space before a full stop that is not there — is copied across
    /// untouched, which is what stops an undo inside a dictated code block flattening it
    /// onto one line.
    ///
    /// Where the change currently sits is *computed*, not searched for. The correction's
    /// range indexes the words as they were spoken, and everything applied before it may
    /// have changed the word count on the way past — "s q l" became "SQL" — so each
    /// earlier change shifts this one along by what it added or removed. Searching the
    /// finished text for the written word instead would find the wrong one the first
    /// time a word appeared twice.
    ///
    /// The splice happens only if the words at that position really are the ones that
    /// were written. They may not be: the tidying pass and the snippet expansion both
    /// run *after* the dictionary has had its say, so the text kept here is not always
    /// the text these ranges were measured against. When they no longer line up the
    /// words are left exactly as they are rather than overwritten with a guess — but the
    /// change is still marked undone and the entry still answers for it, because the
    /// user's judgement of the change is true whether or not the sentence can be
    /// repaired.
    ///
    /// The record that comes back is *this* record with two things changed in place, and
    /// that is deliberate rather than stylistic. It used to be built by calling
    /// ``DictationRecord/init(id:text:when:applicationName:spokenFor:changes:isFlagged:)``
    /// with the fields this method remembered, which silently dropped ``isFlagged`` —
    /// the memberwise default put `false` where the user's own verdict had been. The
    /// same shape of mistake had already lost `spokenFor` in the app. A constructor call
    /// is a list of what the author remembered and a set of defaults for what they did
    /// not, and nothing warns about the difference; a copy has nothing to forget.
    ///
    /// - Parameter correction: The change to put back.
    /// - Returns: The record to store and the entry to count the revert against, or
    ///   `nil` when this dictation has no such change or has already put it back.
    public func undoing(_ correction: UUID) -> (record: DictationRecord, entryID: UUID)? {
        guard let changes,
            let target = changes.corrections.firstIndex(where: { $0.id == correction }),
            !changes.corrections[target].isUndone
        else { return nil }

        let reverted = changes.corrections[target]
        var undone = self
        // Read from `changes` and not from the copy, so the words are located against
        // the flags as they stand *before* this change is marked: `restoring` asks where
        // each correction's words currently sit, and this one's still sit where they
        // were written.
        undone.text = restoring(reverted, among: changes.corrections)
        undone.changes?.corrections[target].isUndone = true
        return (undone, reverted.entryID)
    }

    /// ``text`` with one correction's words replaced by what was heard.
    ///
    /// - Parameters:
    ///   - reverted: The change being put back.
    ///   - corrections: Every change on this dictation, in any order, each saying
    ///     whether it currently applies — the ones already undone occupy the words they
    ///     were heard as, not the ones they were written as.
    /// - Returns: The repaired text, or the text unchanged when the words are no longer
    ///   where the ranges say they should be.
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
        // The words there must be the ones that were written. Anything else means this
        // text is not the text the range was measured against, and overwriting it would
        // cost the user a sentence to save a word.
        guard text[span].spokenWords() == reverted.wrote.spokenWords() else { return text }

        var repaired = String(text[text.startIndex..<span.lowerBound])
        repaired += reverted.heard
        repaired += text[span.upperBound...]
        return repaired
    }
}

extension StringProtocol {
    /// The whitespace-separated words of this text.
    ///
    /// Whitespace and not runs of letters, because that is how an utterance is counted
    /// into words and a correction's range indexes those. Splitting the other way would
    /// put "don't" at two indices and shift every correction after it onto the wrong
    /// word. Stated again here rather than shared with the pipeline's copy, because this
    /// module may see nothing but `UttrflowCore` — the same cost `DictationCorrection`
    /// pays for the same reason.
    fileprivate func spokenWords() -> [SubSequence] {
        split(whereSeparator: \.isWhitespace)
    }
}

extension String {
    /// Where each spoken word of this text begins and ends.
    fileprivate func spokenWordRanges() -> [Range<String.Index>] {
        spokenWords().map { $0.startIndex..<$0.endIndex }
    }
}

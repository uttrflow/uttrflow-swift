// Tests for reasons, the corrections list, scopes, undo, corrected-word counting and salvage decoding.
import Foundation
import Testing

@testable import UttrflowHistory

// MARK: - Fixtures

/// A fixed instant.
private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// A correction replacing "utter flow" with "Uttrflow" unless a field says otherwise.
private func made(
    id: UUID = UUID(),
    heard: String = "utter flow",
    wrote: String = "Uttrflow",
    range: Range<Int> = 0..<2,
    entry: UUID = UUID(),
    reason: CorrectionReason = .seenOnScreen,
    confidence: Double = 0.31,
    isUndone: Bool = false
) -> RecordedCorrection {
    RecordedCorrection(
        id: id, heard: heard, wrote: wrote, wordRange: range, entryID: entry, reason: reason,
        heardConfidence: confidence, isUndone: isUndone)
}

/// A dictation `daysAgo` before `epoch`, into Slack unless said otherwise.
private func said(
    _ text: String = "Uttrflow is late",
    id: UUID = UUID(),
    daysAgo: Double = 0,
    app: String? = "Slack",
    changes: RecordedChanges? = nil
) -> DictationRecord {
    DictationRecord(
        id: id, text: text, when: epoch.addingTimeInterval(-daysAgo * 86_400), applicationName: app,
        changes: changes)
}

// MARK: - The reason

/// The vocabulary of reasons and its join to the engine's raw values.
@Suite("The reason a word was changed")
struct CorrectionReasonTests {
    /// The join to `UttrflowAI.CorrectionReason`, which this module cannot see; a drifted spelling fails.
    @Test("the raw values are the correction engine's own, letter for letter")
    func rawValuesMatchTheEngine() {
        #expect(
            CorrectionReason.allCases.map(\.rawValue) == [
                "seenOnScreen", "saidClearlyElsewhere", "heardAsStrayLetters", "heardAsSeveralWords",
            ])
    }

    @Test("every reason has words the user can read")
    func everyReasonIsNamed() {
        #expect(CorrectionReason.seenOnScreen.title == "Seen on screen")
        #expect(CorrectionReason.saidClearlyElsewhere.title == "You said it clearly elsewhere")
        #expect(CorrectionReason.heardAsStrayLetters.title == "Heard as stray letters")
        #expect(CorrectionReason.heardAsSeveralWords.title == "Heard as several words")
    }

    @Test("a reason survives being written down and read back")
    func codable() throws {
        let encoded = try JSONEncoder().encode(CorrectionReason.heardAsStrayLetters)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"heardAsStrayLetters\"")
    }

    /// A change with a reason this build cannot name is refused rather than drawn under a guessed one.
    @Test("a correction is built from the engine's raw reason, or not at all")
    func builtFromTheRawReason() {
        let entry = UUID()
        let correction = RecordedCorrection(
            heard: "a sink p g", wrote: "asyncpg", wordRange: 0..<4, entryID: entry,
            reason: "heardAsStrayLetters", heardConfidence: 0.2)
        #expect(correction?.reason == .heardAsStrayLetters)
        #expect(correction?.entryID == entry)

        #expect(
            RecordedCorrection(
                heard: "um", wrote: "", wordRange: 0..<1, entryID: entry, reason: "filler",
                heardConfidence: 0.2) == nil)
    }
}

// MARK: - Reading the history

/// The list of changes read across records already in hand.
@Suite("Every change across the history")
struct CorrectionHistoryTests {
    @Test("changes are listed newest dictation first, in the order the words were spoken")
    func order() {
        let newer = said(
            changes: RecordedChanges(corrections: [made(wrote: "First"), made(wrote: "Second")]))
        let older = said(daysAgo: 1, changes: RecordedChanges(corrections: [made(wrote: "Third")]))
        #expect(
            CorrectionHistory(of: [newer, older]).corrections.map(\.wrote)
                == ["First", "Second", "Third"])
    }

    @Test("a change carries the dictation it happened in, and when and where that was")
    func join() {
        let record = said(id: UUID(), app: "Mail", changes: RecordedChanges(corrections: [made()]))
        let correction = CorrectionHistory(of: [record]).corrections[0]
        #expect(correction.dictation == record.id)
        #expect(correction.when == record.when)
        #expect(correction.applicationName == "Mail")
        #expect(correction.heard == "utter flow")
        #expect(correction.wrote == "Uttrflow")
        #expect(correction.reason == .seenOnScreen)
        #expect(!correction.isUndone)
    }

    @Test("a dictation nothing was changed in contributes nothing")
    func nothingChanged() {
        #expect(CorrectionHistory(of: [said(changes: RecordedChanges())]).corrections.isEmpty)
    }

    /// A dictation with no record and one that changed nothing are different facts; both contribute nothing.
    @Test("a dictation that kept no record contributes no changes")
    func unmeasured() {
        #expect(CorrectionHistory(of: [said()]).corrections.isEmpty)
        #expect(CorrectionHistory(of: [said(changes: RecordedChanges())]).corrections.isEmpty)
        #expect(
            CorrectionHistory(of: [said(), said(changes: RecordedChanges(corrections: [made()]))])
                .corrections.count == 1)
    }
}

/// Scope titles and narrowing.
@Suite("Narrowing a list of changes")
struct CorrectionsScopeTests {
    /// A change still applied.
    private let kept = Correction(
        dictation: UUID(), heard: "utter flow", wrote: "Kept", reason: .seenOnScreen, when: epoch)
    /// A change the user put back.
    private let reverted = Correction(
        dictation: UUID(), heard: "utter flow", wrote: "Reverted", reason: .seenOnScreen, when: epoch,
        isUndone: true)

    @Test("each scope is named")
    func titles() {
        #expect(CorrectionsScope.all.title == "All changes")
        #expect(CorrectionsScope.applied.title == "Still applied")
        #expect(CorrectionsScope.undone.title == "Undone")
    }

    @Test("each scope lists what it says it lists")
    func matching() {
        let both = [kept, reverted]
        #expect(CorrectionsScope.all.matching(both).map(\.wrote) == ["Kept", "Reverted"])
        #expect(CorrectionsScope.applied.matching(both).map(\.wrote) == ["Kept"])
        #expect(CorrectionsScope.undone.matching(both).map(\.wrote) == ["Reverted"])
    }
}

// MARK: - Putting one back

/// Putting one change back: the words, the entry, the flag and the refusals.
@Suite("Undoing one change")
struct CorrectionUndoTests {
    @Test("the words that were heard go back into the text")
    func restoresTheWords() throws {
        let correction = made()
        let record = said("Uttrflow is late", changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.text == "utter flow is late")
    }

    /// Without the entry a bad word stays in the dictionary and the undo is only cosmetic.
    @Test("the dictionary entry to blame comes back with it")
    func namesTheEntry() throws {
        let entry = UUID()
        let correction = made(entry: entry)
        let record = said(changes: RecordedChanges(corrections: [correction]))
        #expect(try #require(record.undoing(correction.id)).entryID == entry)
    }

    @Test("the change is marked undone rather than forgotten")
    func marksItUndone() throws {
        let correction = made()
        let record = said(changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.changes?.corrections.map(\.isUndone) == [true])
        #expect(undone.record.changes?.corrections.map(\.heard) == ["utter flow"])
    }

    /// Splicing by character range keeps a dictated code block from arriving on one line.
    @Test("everything between the words is left exactly as it was")
    func keepsTheWhitespace() throws {
        let correction = made(heard: "s q l", wrote: "SQL", range: 1..<4)
        let record = said(
            "print SQL\n    print again", changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.text == "print s q l\n    print again")
    }

    /// An earlier replacement with a different word count shifts a later change from its spoken position.
    @Test("a change shifted along by an earlier one is still found")
    func shiftedByAnEarlierChange() throws {
        let first = made(heard: "s q l", wrote: "SQL", range: 0..<3)
        let second = made(heard: "fast", wrote: "quick", range: 4..<5)
        let record = said(
            "SQL is quick", changes: RecordedChanges(corrections: [second, first]))

        let once = try #require(record.undoing(second.id))
        #expect(once.record.text == "SQL is fast")

        // And again from the result, past a neighbour already restored to its heard words.
        #expect(try #require(once.record.undoing(first.id)).record.text == "s q l is fast")
    }

    /// Compares whole values, so a field added to ``DictationRecord`` tomorrow is covered with no checklist.
    @Test("the undone record is this record with one change put back, and nothing else")
    func changesOnlyWhatItSays() throws {
        let correction = made()
        var record = DictationRecord(
            text: "Uttrflow is late", when: epoch, applicationName: "Mail", spokenFor: .seconds(4),
            changes: RecordedChanges(
                corrections: [correction],
                snippets: [RecordedSnippet(snippetID: UUID(), matched: "brb", expansion: "back")],
                spokenWords: 4),
            isFlagged: true)

        let undone = try #require(record.undoing(correction.id)).record

        record.text = "utter flow is late"
        record.changes?.corrections[0].isUndone = true
        #expect(undone == record)
    }

    /// Named apart from ``changesOnlyWhatItSays()`` because this is the failure the user feels.
    @Test("undoing a change does not withdraw the user's flag")
    func keepsTheFlag() throws {
        let correction = made(heard: "s q l", wrote: "SQL", range: 1..<4)
        let record = DictationRecord(
            text: "print SQL", when: epoch,
            changes: RecordedChanges(corrections: [correction]), isFlagged: true)

        let undone = try #require(record.undoing(correction.id))

        #expect(undone.record.text == "print s q l")
        #expect(undone.record.isFlagged, "the user flagged this dictation; an undo must not unflag it")
    }

    @Test("a dictation that never held the change has nothing to put back")
    func unknownChange() {
        #expect(said(changes: RecordedChanges(corrections: [made()])).undoing(UUID()) == nil)
        #expect(said().undoing(UUID()) == nil)
    }

    /// Undoing twice must not count twice against the dictionary entry.
    @Test("a change already put back cannot be put back again")
    func alreadyUndone() {
        let correction = made(isUndone: true)
        #expect(said(changes: RecordedChanges(corrections: [correction])).undoing(correction.id) == nil)
    }

    /// Tidying and snippets run after the dictionary, so the text may not match; the verdict still counts.
    @Test("words that are no longer where the range says are left alone, and still counted")
    func textNoLongerMatches() throws {
        let entry = UUID()
        let correction = made(range: 0..<1, entry: entry)
        let record = said(
            "Something else entirely", changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.text == "Something else entirely")
        #expect(undone.record.changes?.corrections.map(\.isUndone) == [true])
        #expect(undone.entryID == entry)
    }

    @Test(
        "a range that does not fit the text is refused rather than trusted",
        arguments: [
            "past the end": made(range: 9..<10),
            "nothing was written": made(wrote: "", range: 0..<2),
        ])
    func impossibleRange(_ named: String, _ correction: RecordedCorrection) throws {
        let record = said("Uttrflow is late", changes: RecordedChanges(corrections: [correction]))
        #expect(try #require(record.undoing(correction.id)).record.text == "Uttrflow is late")
    }
}

// MARK: - How much of the utterance is still the user's

/// The count behind the accuracy figure. See Docs/core-history-accuracy.md.
@Suite("Counting the words a dictation changed")
struct CorrectedWordsTests {
    @Test("the spoken words a standing change covers are counted, in the utterance's terms")
    func countsSpokenPositions() {
        let changes = RecordedChanges(
            corrections: [made(range: 1..<4)], spokenWords: 5)
        // Three words of the five heard were rewritten, however many words replaced them.
        #expect(changes.correctedWords == 3)
    }

    /// The user put those words back, so they read as they were said.
    @Test("a change the user put back does not count against them")
    func ignoresUndone() {
        let changes = RecordedChanges(
            corrections: [made(range: 0..<2, isUndone: true), made(range: 3..<4)],
            spokenWords: 5)
        #expect(changes.correctedWords == 1)
    }

    /// Only a hand-edited file can overlap two changes; a word rewritten twice is still one word.
    @Test("a word two changes both claim is one word, not two")
    func overlapsCountOnce() {
        let changes = RecordedChanges(
            corrections: [made(range: 0..<3), made(range: 2..<4)], spokenWords: 6)
        #expect(changes.correctedWords == 4)
    }

    /// Positions are counted within the utterance, so the count cannot exceed it and needs no clamp.
    @Test("a change reaching past the end of the utterance is counted only as far as it reaches")
    func rangesPastTheEnd() {
        let changes = RecordedChanges(corrections: [made(range: 0..<9)], spokenWords: 2)
        #expect(changes.correctedWords == 2)
        #expect(RecordedChanges(corrections: [made(range: 4..<6)], spokenWords: 2).correctedWords == 0)
    }

    /// With no utterance counted there is nothing for these to be positions in.
    @Test("changes recorded before the utterance was counted count nothing")
    func withoutAnUtterance() {
        #expect(RecordedChanges(corrections: [made(range: 0..<2)]).correctedWords == 0)
    }
}

// MARK: - What a stored change survives

/// Loses only the part it cannot read and keeps the user's words. See Docs/core-history-decoding.md.
@Suite("Reading a stored change written by a build we are not")
struct RecordedChangesDecodingTests {
    /// A fixed correction identifier.
    private static let stray = "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"
    /// A fixed dictionary-entry identifier.
    private static let entry = "6BA7B811-9DAD-11D1-80B4-00C04FD430C8"

    /// One well-formed change, as today's build writes it.
    private static func stored(
        id: String = stray, reason: String = "seenOnScreen", extra: String = ""
    ) -> String {
        """
        {"id":"\(id)","heard":"utter flow","wrote":"Uttrflow","wordRange":[0,2],\
        "entryID":"\(entry)","reason":"\(reason)","heardConfidence":0.3,"isUndone":false\(extra)}
        """
    }

    /// Decodes `json` as a ``RecordedChanges``.
    private func changes(_ json: String) throws -> RecordedChanges {
        try JSONDecoder().decode(RecordedChanges.self, from: Data(json.utf8))
    }

    /// The case a fifth ``CorrectionReason`` creates for every user who runs an older build again.
    @Test("a change named with a reason this build does not know costs that change")
    func unknownReason() throws {
        let decoded = try changes(
            """
            {"corrections":[\(Self.stored(reason: "heardInAnotherLanguage")),\
            \(Self.stored())],"snippets":[]}
            """)
        #expect(decoded.corrections.map(\.wrote) == ["Uttrflow"])
    }

    /// The same containment for a field one build requires and another does not write.
    @Test("a change missing something this build requires costs that change")
    func missingRequiredField() throws {
        let decoded = try changes(
            """
            {"corrections":[{"id":"\(Self.stray)","heard":"utter flow","wrote":"Uttrflow"},\
            \(Self.stored())]}
            """)
        #expect(decoded.corrections.map(\.wrote) == ["Uttrflow"])
    }

    /// Dropped only with no honest answer; "not put back" is one, as for ``DictationRecord/isFlagged``.
    @Test("a change from before undoing was recorded reads as one nobody undid")
    func missingIsUndone() throws {
        let decoded = try changes(
            """
            {"corrections":[{"id":"\(Self.stray)","heard":"utter flow","wrote":"Uttrflow",\
            "wordRange":[0,2],"entryID":"\(Self.entry)","reason":"seenOnScreen",\
            "heardConfidence":0.3}]}
            """)
        #expect(decoded.corrections.map(\.isUndone) == [false])
    }

    @Test("a snippet firing this build cannot read costs that firing and nothing else")
    func unreadableSnippet() throws {
        let decoded = try changes(
            """
            {"corrections":[\(Self.stored())],"snippets":[{"matched":"brb"},\
            {"snippetID":"\(Self.entry)","matched":"brb","expansion":"back shortly"}]}
            """)
        #expect(decoded.snippets.map(\.expansion) == ["back shortly"])
        #expect(decoded.corrections.count == 1)
    }

    /// Absent, not zero: an uncounted utterance retires the accuracy figure rather than claiming silence.
    @Test("changes written before the utterance was counted decode with no count")
    func missingSpokenWords() throws {
        #expect(try changes("{\"corrections\":[],\"snippets\":[]}").spokenWords == nil)
        #expect(try changes("{}").corrections.isEmpty)
    }

    @Test("the utterance's length survives being written down and read back")
    func roundTripsTheCount() throws {
        let changes = RecordedChanges(corrections: [made()], spokenWords: 12)
        let decoded = try JSONDecoder().decode(
            RecordedChanges.self, from: JSONEncoder().encode(changes))
        #expect(decoded == changes)
        #expect(decoded.spokenWords == 12)
    }
}

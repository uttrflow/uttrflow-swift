import Foundation
import Testing

@testable import UttrflowHistory

// MARK: - Fixtures

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

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

@Suite("The reason a word was changed")
struct CorrectionReasonTests {
    /// The one thing the build cannot check for itself. `UttrflowAI.CorrectionReason` is
    /// the authority on these spellings and `DictationCorrection.reason` carries them
    /// across as a bare `String`, but nothing in the package graph lets this module see
    /// that one — so the join is these five literals. Rename a case there and this fails
    /// here, which is the point: a raw value that drifted would turn every stored
    /// correction into one this build cannot name.
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

    /// "A change with no nameable reason is a change that should never have been made" —
    /// so one that arrives with a reason this build cannot name is refused at the door
    /// rather than drawn under a reason somebody guessed for it.
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

    /// A dictation that recorded nothing contributes nothing, rather than being read as
    /// one that changed nothing. Which of the two it was is the difference between a
    /// measurement and a number.
    @Test("a dictation that kept no record contributes no changes")
    func unmeasured() {
        #expect(CorrectionHistory(of: [said()]).corrections.isEmpty)
        #expect(CorrectionHistory(of: [said(changes: RecordedChanges())]).corrections.isEmpty)
        #expect(
            CorrectionHistory(of: [said(), said(changes: RecordedChanges(corrections: [made()]))])
                .corrections.count == 1)
    }
}

@Suite("Narrowing a list of changes")
struct CorrectionsScopeTests {
    private let kept = Correction(
        dictation: UUID(), heard: "utter flow", wrote: "Kept", reason: .seenOnScreen, when: epoch)
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

@Suite("Undoing one change")
struct CorrectionUndoTests {
    @Test("the words that were heard go back into the text")
    func restoresTheWords() throws {
        let correction = made()
        let record = said("Uttrflow is late", changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.text == "utter flow is late")
    }

    /// The entry is the whole point. Without it a bad word stays in the dictionary and
    /// is applied again tomorrow, and the undo was only cosmetic.
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

    /// The whitespace between the words is the reason this splices by character range
    /// instead of rejoining the words with spaces — a dictated code block put back
    /// together the other way arrives on one line.
    @Test("everything between the words is left exactly as it was")
    func keepsTheWhitespace() throws {
        let correction = made(heard: "s q l", wrote: "SQL", range: 1..<4)
        let record = said(
            "print SQL\n    print again", changes: RecordedChanges(corrections: [correction]))
        let undone = try #require(record.undoing(correction.id))
        #expect(undone.record.text == "print s q l\n    print again")
    }

    /// A replacement can be a different number of words from what it replaced, so a
    /// later change no longer sits where it was spoken. Searching the text for the
    /// written word instead would find the wrong one the moment a word appeared twice.
    @Test("a change shifted along by an earlier one is still found")
    func shiftedByAnEarlierChange() throws {
        let first = made(heard: "s q l", wrote: "SQL", range: 0..<3)
        let second = made(heard: "fast", wrote: "quick", range: 4..<5)
        let record = said(
            "SQL is quick", changes: RecordedChanges(corrections: [second, first]))

        let once = try #require(record.undoing(second.id))
        #expect(once.record.text == "SQL is fast")

        // And again from the result, where the first change now has to be found past a
        // neighbour that is already back to the words it was heard as.
        #expect(try #require(once.record.undoing(first.id)).record.text == "s q l is fast")
    }

    /// The one test here that cannot go stale as the record grows, and the reason the
    /// list of fields it replaced was worth deleting.
    ///
    /// `undoing` changes exactly two things, so the expected answer is built the same
    /// way the method builds it — a copy of the record with those two things changed —
    /// and whole values are compared. Naming the fields that ought to have survived is
    /// what let ``DictationRecord/isFlagged`` be dropped for as long as it was: the
    /// checklist was written from the same memory as the code, and both forgot the same
    /// field. `==` over the struct forgets nothing, and a field added to
    /// ``DictationRecord`` tomorrow is covered by this without anybody remembering to
    /// come back and add it.
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

    /// Named separately from ``changesOnlyWhatItSays()`` even though that would catch it,
    /// because this is the one the user feels and a whole-value mismatch does not say so.
    /// ``DictationRecord/isFlagged`` is the only judgement in the record that Uttrflow did
    /// not make, and putting a change back is not the user withdrawing it.
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

    /// Tidying and snippet expansion both run after the dictionary has had its say, so
    /// the text kept here is not always the text these ranges were measured against.
    /// Overwriting it would cost the user a sentence to save a word — but their verdict
    /// on the change is true either way, so the row and the dictionary still hear it.
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

    /// The pipeline cannot write two changes over the same word — the applier refuses an
    /// overlap — but a hand-edited file can, and one word rewritten twice is still one
    /// word the user did not get back.
    @Test("a word two changes both claim is one word, not two")
    func overlapsCountOnce() {
        let changes = RecordedChanges(
            corrections: [made(range: 0..<3), made(range: 2..<4)], spokenWords: 6)
        #expect(changes.correctedWords == 4)
    }

    /// The guarantee the accuracy figure rests on, and the reason it needs no clamp:
    /// what is counted are positions *within* the utterance, so the count cannot exceed
    /// it whatever a file claims.
    @Test("a change reaching past the end of the utterance is counted only as far as it reaches")
    func rangesPastTheEnd() {
        let changes = RecordedChanges(corrections: [made(range: 0..<9)], spokenWords: 2)
        #expect(changes.correctedWords == 2)
        #expect(RecordedChanges(corrections: [made(range: 4..<6)], spokenWords: 2).correctedWords == 0)
    }

    /// Nobody counted the utterance, so there is nothing for these to be positions in.
    /// The accuracy figure has already retired itself for such a dictation.
    @Test("changes recorded before the utterance was counted count nothing")
    func withoutAnUtterance() {
        #expect(RecordedChanges(corrections: [made(range: 0..<2)]).correctedWords == 0)
    }
}

// MARK: - What a stored change survives

/// ``DictationHistoryStore`` reads its file all-or-nothing: one throwing field discards
/// the whole history, and the next write deletes it. So these are not tests about a
/// field or two. They are tests that a build meeting a file it does not entirely
/// understand loses the part it cannot read and keeps the user's words.
@Suite("Reading a stored change written by a build we are not")
struct RecordedChangesDecodingTests {
    private static let stray = "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"
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

    private func changes(_ json: String) throws -> RecordedChanges {
        try JSONDecoder().decode(RecordedChanges.self, from: Data(json.utf8))
    }

    /// The case a fifth ``CorrectionReason`` creates for every user who runs an older
    /// build again. The write path already drops a change it cannot name; this is the
    /// same answer on the way back out, instead of the history file being discarded.
    @Test("a change named with a reason this build does not know costs that change")
    func unknownReason() throws {
        let decoded = try changes(
            """
            {"corrections":[\(Self.stored(reason: "heardInAnotherLanguage")),\
            \(Self.stored())],"snippets":[]}
            """)
        #expect(decoded.corrections.map(\.wrote) == ["Uttrflow"])
    }

    /// The same containment for the other way this type grows: a field added to it that
    /// an older build requires and a newer file does not write, or the reverse.
    @Test("a change missing something this build requires costs that change")
    func missingRequiredField() throws {
        let decoded = try changes(
            """
            {"corrections":[{"id":"\(Self.stray)","heard":"utter flow","wrote":"Uttrflow"},\
            \(Self.stored())]}
            """)
        #expect(decoded.corrections.map(\.wrote) == ["Uttrflow"])
    }

    /// Dropped only when there is no honest answer. "The user has not put it back" is an
    /// honest answer, so a change from before undoing was recorded is kept rather than
    /// lost — the same call ``DictationRecord/isFlagged`` makes.
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

    /// Absent, not zero. A dictation nobody counted the words of must retire the accuracy
    /// figure rather than claim the user said nothing.
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

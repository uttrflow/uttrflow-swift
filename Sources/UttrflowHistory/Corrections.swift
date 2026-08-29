public import struct Foundation.UUID

/// Why Uttrflow changed a word.
///
/// A closed set, and that is the point of the Corrections page. Uttrflow only changes a
/// word when it has a reason it can name; a reason it cannot name is a change it must
/// not make. Adding a case here is the moment somebody has to write down, in one line,
/// what they are giving the app permission to rewrite.
///
/// **These are the correction engine's own cases.** There used to be a second list of
/// reasons in `UttrflowUX` — `dictionary`, `filler`, `punctuation`, `grammar` and the
/// rest — invented for the artboard before the engine existed, whose cases did not line
/// up with anything the engine could actually establish. Two lists means a mapping, and
/// a mapping is where a reason stops being what happened and becomes what somebody
/// thought would read well. So the UX list is gone and this one, spelled exactly as
/// `UttrflowAI.CorrectionReason` spells it, is what the page draws.
///
/// The raw values are the join. `DictationCorrection.reason` carries the engine's raw
/// value across the pipeline as a `String` — deliberately, so the pipeline cannot
/// reinterpret it — and ``RecordedCorrection/init(heard:wrote:wordRange:entryID:reason:heardConfidence:)``
/// turns it back into a case here. That makes the two enumerations one vocabulary
/// rather than two, but nothing in the build graph lets either module see the other, so
/// the raw values are held in step by a test in `CorrectionsTests` that spells them out.
public enum CorrectionReason: String, Sendable, Equatable, CaseIterable, Codable {
    /// The replacement is written on the screen being dictated into.
    case seenOnScreen
    /// The same word appears elsewhere in this dictation, where it was heard clearly.
    case saidClearlyElsewhere
    /// What was heard was loose letters and the replacement is a word.
    case heardAsStrayLetters
    /// What was heard was a run of words and the replacement is one written word.
    case heardAsSeveralWords

    /// The label the Corrections page shows beside the change.
    ///
    /// Named `title` and not `summary` because that is what the page already asks for,
    /// and worded as the UX list worded it wherever the two lists agreed on a case —
    /// which, in the end, was only "Seen on screen".
    public var title: String {
        switch self {
        case .seenOnScreen: "Seen on screen"
        case .saidClearlyElsewhere: "You said it clearly elsewhere"
        case .heardAsStrayLetters: "Heard as stray letters"
        case .heardAsSeveralWords: "Heard as several words"
        }
    }
}

/// One word Uttrflow replaced, kept with the dictation it happened in.
///
/// Everything an undo needs is here — the words that were there, where they were, and
/// which entry to blame — because an undo that had to find any of that again in the
/// finished text would be guessing, and would guess wrong the first time a word
/// appeared twice.
///
/// There is deliberately no audio and no path to any, for the reason ``DictationRecord``
/// gives: a correction is a claim about the user's own words, and the same rule applies
/// to it as to the words themselves.
public struct RecordedCorrection: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// What was written in its place.
    public let wrote: String
    /// Which spoken words this covered, as indices into the transcript's words.
    public let wordRange: Range<Int>
    /// The dictionary entry that won.
    ///
    /// `PersonalDictionaryStore.recordRevert(of:)` takes exactly this, which is what
    /// lets a word the user keeps rejecting retire itself. ``DictationRecord/undoing(_:)``
    /// hands it back for that reason and no other.
    public let entryID: UUID
    public let reason: CorrectionReason
    /// What the recogniser scored the words being replaced. Kept so a sceptical user can
    /// be shown that the engine only ever moved on a guess.
    public let heardConfidence: Double
    /// Whether the user has already put it back.
    ///
    /// A flag rather than a deletion, so the page can show that a change was undone and
    /// Uttrflow can count how often that happens.
    public var isUndone: Bool

    public init(
        id: UUID = UUID(), heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID,
        reason: CorrectionReason, heardConfidence: Double, isUndone: Bool = false
    ) {
        self.id = id
        self.heard = heard
        self.wrote = wrote
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
        self.isUndone = isUndone
    }

    /// The same, built from the raw reason the pipeline carried across.
    ///
    /// Failable rather than defaulting, because "a change with no nameable reason is a
    /// change that should never have been made" is the rule the Corrections page is
    /// built on, and a stored change this build cannot explain must not be drawn under
    /// a reason somebody guessed for it. Keeping the refusal here, in a module a test
    /// can reach, is what stops it being written again at each call site.
    ///
    /// The reason is `UttrflowAI.CorrectionReason`'s raw value, exactly as
    /// `DictationCorrection.reason` carries it across the pipeline.
    public init?(
        id: UUID = UUID(), heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID,
        reason: String, heardConfidence: Double, isUndone: Bool = false
    ) {
        guard let named = CorrectionReason(rawValue: reason) else { return nil }
        self.init(
            id: id, heard: heard, wrote: wrote, wordRange: wordRange, entryID: entryID,
            reason: named, heardConfidence: heardConfidence, isUndone: isUndone)
    }

    /// Written by hand for the reason ``DictationRecord``'s is, and it is a sharper
    /// reason here than it looks.
    ///
    /// Swift's generated `init(from:)` throws on any absent non-optional key, and
    /// ``DictationHistoryStore`` reads its file all-or-nothing: one throw discards the
    /// *entire* history, and the next dictation writes the survivors — none — over it.
    /// So a field added to this type without a default would not cost a correction on a
    /// downgrade. It would cost every word the user has ever dictated.
    ///
    /// The rule that follows: **anything added here is read with `decodeIfPresent` and
    /// given an honest default, or it is not added.** Only fields with an honest default
    /// get one. ``heardConfidence`` deliberately has none — a missing score read as zero
    /// would claim the recogniser was certain about words it never scored — so it stays
    /// required, and a file missing it costs this one change rather than the history,
    /// because ``RecordedChanges`` salvages what it cannot read.
    ///
    /// ``reason`` stays required for the reason the failable initialiser above gives: a
    /// change this build cannot name must not be drawn under a name somebody guessed
    /// for it. That is the case a fifth ``CorrectionReason`` would create, and it is
    /// contained one level up rather than defaulted away here.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        heard = try values.decode(String.self, forKey: .heard)
        wrote = try values.decode(String.self, forKey: .wrote)
        wordRange = try values.decode(Range<Int>.self, forKey: .wordRange)
        entryID = try values.decode(UUID.self, forKey: .entryID)
        reason = try values.decode(CorrectionReason.self, forKey: .reason)
        heardConfidence = try values.decode(Double.self, forKey: .heardConfidence)
        // The user has not put it back. A file from before the flag existed and a change
        // nobody undid are the same fact, exactly as with ``DictationRecord/isFlagged``.
        isUndone = try values.decodeIfPresent(Bool.self, forKey: .isUndone) ?? false
    }
}

/// One snippet firing once.
public struct RecordedSnippet: Sendable, Equatable, Codable {
    /// Which snippet fired. Not the snippet itself: by the time this is read the store
    /// may have been edited, and a stale copy of the text would be worse than a lookup.
    public let snippetID: UUID
    /// The words in the transcript that were replaced, exactly as they appeared there.
    public let matched: String
    /// What replaced them.
    public let expansion: String

    public init(snippetID: UUID, matched: String, expansion: String) {
        self.snippetID = snippetID
        self.matched = matched
        self.expansion = expansion
    }
}

/// Everything Uttrflow changed about one dictation.
///
/// One value rather than two lists on the record, because the pipeline reports them
/// together and a record that had only half of them would be a record that could not
/// say whether the other half was empty or unknown.
///
/// Present and empty is the commonest case and means "nothing was changed". That is not
/// the same as ``DictationRecord/changes`` being absent, which means "this dictation
/// predates the keeping of changes" — and telling those two apart is the whole reason
/// the accuracy figure can be drawn without inventing a denominator.
public struct RecordedChanges: Sendable, Equatable, Codable {
    /// In the order the words were spoken.
    public var corrections: [RecordedCorrection]
    /// In the order they appear. A snippet that fired twice appears twice, which is why
    /// this is a list of firings and not a set of snippets.
    public let snippets: [RecordedSnippet]
    /// How many words the user actually said.
    ///
    /// The utterance ``RecordedCorrection/wordRange`` indexes into, and the only honest
    /// denominator for "how much of what I said came out as I said it". It lives here
    /// rather than on ``DictationRecord`` precisely so that it cannot drift from those
    /// ranges: the positions and the count they are positions within are one value, read
    /// together or not at all.
    ///
    /// It has to be kept because it cannot be recovered. ``DictationRecord/text`` is what
    /// was *written*, and three passes stand between the two — the dictionary can write
    /// one word over three, a snippet can write twelve over two, and the tidier then
    /// drops fillers from whatever is left. Counting the finished text and calling it the
    /// utterance is exactly the mistake the accuracy figure used to make, and it reported
    /// 0% to users whose dictionary was working perfectly.
    ///
    /// Optional because a history written before it was kept has no answer, and inventing
    /// one would put a fiction under a percentage. `nil` retires the accuracy figure for
    /// that dictation, the same way an absent ``DictationRecord/changes`` does.
    public let spokenWords: Int?

    public init(
        corrections: [RecordedCorrection] = [], snippets: [RecordedSnippet] = [],
        spokenWords: Int? = nil
    ) {
        self.corrections = corrections
        self.snippets = snippets
        self.spokenWords = spokenWords
    }

    /// How many of the spoken words are not the user's own words any more.
    ///
    /// Counted as distinct positions in the utterance rather than as a sum of range
    /// lengths, and out-of-range positions dropped. Both matter: it makes the answer at
    /// most ``spokenWords`` *by construction*, which is what lets the accuracy figure be
    /// a plain subtraction rather than a subtraction with a `max(_:0)` under it quietly
    /// absorbing a disagreement. The pipeline cannot produce overlapping or oversized
    /// ranges — `DictationCorrection.applying(_:to:)` refuses both — but a hand-edited
    /// history file can, and the figure should then be merely wrong about one dictation
    /// rather than negative.
    ///
    /// Undone changes do not count. The user put those words back, so they read as they
    /// were said.
    ///
    /// Snippets do not count either, and that is not an oversight. A snippet fires
    /// because the user said its trigger and meant it; the words were heard correctly.
    /// Counting an expansion as a correction would charge the user's own shorthand
    /// against the recogniser's accuracy.
    ///
    /// Zero when nobody counted the utterance, because there is then no utterance for
    /// these to be positions in — and ``spokenWords`` being `nil` already retires the
    /// figure, so the value is never read in that case.
    public var correctedWords: Int {
        guard let spokenWords else { return 0 }
        let said = 0..<spokenWords
        return Set(
            corrections.lazy
                .filter { !$0.isUndone }
                .flatMap(\.wordRange)
                .filter { said.contains($0) }
        ).count
    }

    /// Written by hand so that one unreadable change costs one change.
    ///
    /// ``DictationHistoryStore`` discards a history file it cannot decode, and the next
    /// write deletes what is left of it. That makes the blast radius of a single
    /// throwing field every word the user has ever dictated — so the two lists are read
    /// entry by entry, and an entry this build cannot read is left out instead of
    /// thrown.
    ///
    /// It is the same answer the write path already gives. `AppDelegate` builds each
    /// ``RecordedCorrection`` through the failable initialiser and `compactMap`s away
    /// any whose reason it cannot name, so "a change I cannot explain is a change I do
    /// not show" is settled policy going in; this is that policy coming back out,
    /// instead of a crash. Nothing on disk today can trigger it. A fifth
    /// ``CorrectionReason`` — which that enumeration's own documentation invites — would
    /// trigger it for every user who ever ran an older build again.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        corrections =
            try values.decodeIfPresent([Salvaged<RecordedCorrection>].self, forKey: .corrections)?
            .compactMap(\.value) ?? []
        snippets =
            try values.decodeIfPresent([Salvaged<RecordedSnippet>].self, forKey: .snippets)?
            .compactMap(\.value) ?? []
        spokenWords = try values.decodeIfPresent(Int.self, forKey: .spokenWords)
    }
}

/// One `Value`, or nothing when this build cannot read it.
///
/// A `Decodable` that never throws, so an array of them is an array that never throws.
/// The `try?` is the entire point rather than a swallowed error: the alternative on this
/// path is not a logged failure, it is the user's whole history being deleted. Which
/// entries were dropped is visible to the user in the only way that matters — the
/// changes they cannot see are the ones they cannot undo — and a build that cannot read
/// a change has nothing true to say about it anyway.
private struct Salvaged<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

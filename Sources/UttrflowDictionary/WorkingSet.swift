public import UttrflowCore
public import struct Foundation.Date

/// The words worth putting in front of the recogniser before it decodes anything.
///
/// Distinct from ``PhoneticIndex/candidates(for:limit:)`` and answering a different
/// question. The index is consulted *after* a guess exists, and asks "could this have
/// been one of the user's words?". This is consulted *before* any audio is decoded,
/// when there is nothing to match against yet, and asks "what is this person likely to
/// say at all?". A decoder conditioned on a few dozen of the right words gets them
/// right first time instead of being corrected afterwards.
///
/// It returns spellings and stops there. Turning them into a `DecodingOptions`
/// conditioning prompt is the speech layer's job, and importing a recogniser here to do
/// it would tie the dictionary to whichever engine won this month's bake-off.
public enum WorkingSet {
    /// How many words fit a conditioning prompt.
    ///
    /// A recogniser's prompt is a few hundred tokens shared with everything else that
    /// wants to condition the decoder, and a technical word is rarely one token.
    /// Ninety-six leaves room for the rest.
    public static let defaultLimit = 96

    /// The age at which a word is worth half what it was worth new.
    ///
    /// Thirty days: long enough that a project's vocabulary survives a fortnight's
    /// holiday, short enough that last year's client stops crowding out this year's.
    static let recencyHalfLifeInDays = 30.0

    /// What the frontmost app agreeing with an entry is worth.
    ///
    /// One — the most that frequency alone can ever contribute. Being in
    /// `PaymentSheet.swift` is strong evidence for the word `PaymentSheet`, but it
    /// should not bury a word the user says every single day.
    static let affinityWeight = 1.0

    /// The highest-value words within a budget, best first.
    ///
    /// Scored on three things, each deliberately kept inside zero to one so that no
    /// single term can swamp the other two.
    ///
    /// *Frequency* — uses the user did not undo, saturating rather than growing without
    /// bound, so the difference between one use and five matters and the difference
    /// between five hundred and a thousand does not. *Recency* — decaying by half every
    /// ``recencyHalfLifeInDays``. And *affinity* with what is on screen: the name of the
    /// app, the document and anything selected, matched through the same phonetics as
    /// everything else, so a window titled "Nikhel Sharma" still favours the entry spelt
    /// "Nikhil".
    ///
    /// Recency is measured from ``DictionaryEntry/firstSeen``, because that is the only
    /// clock an entry carries. It is a proxy for "last used" and a weaker one: a
    /// `lastUsed` on the entry is the single change that would most improve this
    /// ranking. `now` is a parameter for the reason `Retention` gives about its own —
    /// a store that reads the clock itself is a store no test can pin down.
    ///
    /// Entries that have retired themselves are excluded outright. Conditioning a
    /// decoder towards a word the user keeps undoing would be teaching it the mistake.
    ///
    /// Unlike the candidate lookup, this reads every entry: a ranking of the whole
    /// dictionary cannot be got at through a hash. That is affordable because it happens
    /// once when a dictation begins rather than once per spoken word, and because what
    /// it *returns* is bounded by `limit` — the prompt still does not grow.
    public static func words(
        from entries: [DictionaryEntry],
        limit: Int = WorkingSet.defaultLimit,
        now: Date,
        favouring context: AppContext = .unknown
    ) -> [String] {
        guard limit > 0 else { return [] }
        let wanted = soundsOnScreen(in: context)
        let ranked =
            entries
            .filter(\.isTrustworthy)
            .map { (entry: $0, value: value(of: $0, now: now, wanted: wanted)) }
            .sorted { first, second in
                if first.value != second.value { return first.value > second.value }
                // Ties broken the same way buckets are, so the working set and the
                // candidate list never disagree about which of two words matters more.
                return PhoneticIndex.isMoreUseful(first.entry, second.entry)
            }
        return ranked.prefix(limit).map(\.entry.word)
    }

    /// The most words read off the screen.
    ///
    /// A selection can be an entire document, and this runs at the start of every
    /// dictation. Sixty-four is more than enough for an app name, a window title and a
    /// highlighted phrase, and turns an unbounded read into a bounded one.
    static let maximumWordsOnScreen = 64

    /// The sounds of everything the frontmost app is showing.
    ///
    /// Split on anything that is not a letter, so that a window titled
    /// `PaymentSheet.swift` offers `PaymentSheet` rather than one long word that matches
    /// nothing. Runs of words are then taken through the same machinery an utterance
    /// goes through — a document called "Payment Sheet" has to favour the entry spelt
    /// `PaymentSheet` for exactly the reason speech does.
    static func soundsOnScreen(in context: AppContext) -> Set<String> {
        let onScreen = [context.applicationName, context.documentName, context.selectedText]
            .compactMap { $0 }
            .joined(separator: " ")
        let visible = Utterance(
            words: LearnableWords.words(in: onScreen, atMost: maximumWordsOnScreen)
                .map { SpokenWord(text: $0, confidence: 1) })
        return visible.sounds(upTo: PhoneticIndex.maximumWordsPerEntry)
    }

    /// What one prompt slot spent on this entry is worth.
    static func value(of entry: DictionaryEntry, now: Date, wanted: Set<String>) -> Double {
        let kept = Double(max(0, entry.timesUsed - entry.timesReverted))
        let frequency = kept / (1 + kept)
        // Clamped at zero so that an entry stamped in the future by a machine whose
        // clock has slipped scores as brand new rather than as impossibly valuable.
        let ageInDays = max(0, now.timeIntervalSince(entry.firstSeen)) / 86_400
        let recency = recencyHalfLifeInDays / (recencyHalfLifeInDays + ageInDays)
        let onScreen = DoubleMetaphone.code(for: entry.soundsLike).sounds(likeAnyOf: wanted)
        return frequency + recency + (onScreen ? affinityWeight : 0)
    }
}

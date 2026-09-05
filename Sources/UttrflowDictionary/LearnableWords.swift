import UttrflowCore

/// What one finished dictation is entitled to teach the dictionary.
///
/// Pure rules and no storage, for the reason ``WorkingSet`` gives about ranking: what
/// counts as evidence is the part worth arguing about, and it must be arguable in a test
/// without a disk anywhere near it.
///
/// **The default is to learn nothing.** A dictionary that learns is a dictionary that
/// can learn the wrong thing, and a mis-heard name reinforced three times is worse than
/// one never learnt — so every rule below is written to refuse, and a word gets in only
/// by defeating all of them. Both paths are insured by the same two things: an entry
/// that keeps being undone retires itself through ``DictionaryEntry/isTrustworthy``, and
/// every word either path adds is thrown away by
/// ``PersonalDictionaryStore/removeLearned()``, which is the promise this whole feature
/// is sold under.
enum LearnableWords {
    /// How many separate dictations a term must be both on screen and spoken in before
    /// it is worth keeping.
    ///
    /// Three. One sighting is a coincidence — the word was in a window title and the
    /// sentence happened to rhyme with it. Two is a coincidence twice, which is not much
    /// rarer, because the second dictation is usually about the same thing as the first
    /// and sees the same title. Three separate dictations is the first count that means
    /// the user keeps coming back to this word, and it is deliberately the same number
    /// as ``DictionaryEntry/isTrustworthy``'s grace period: three is what this codebase
    /// already calls "enough to stop being an accident".
    ///
    /// Higher would be safer and is the wrong trade past this point. The evidence here
    /// is weak by nature — nobody asked for it — so it is corroborated three times; the
    /// cost of asking for five is that a fortnight's project ends before its vocabulary
    /// is learnt, which is the feature not existing.
    static let sightingsBeforeLearning = 3

    /// The most words either side of a correction may have.
    ///
    /// Three, the same as ``PhoneticIndex/maximumWordsPerEntry``, and for the same
    /// reason: three words is the longest thing this dictionary can hold as one entry,
    /// so a longer selection cannot be a word being re-spelt. It is also the line
    /// between a correction and a rewrite — somebody who selects a sentence and dictates
    /// another sentence is editing their prose, not reporting a mis-hearing, and reading
    /// it as one would learn a phrase they will never say again.
    static let maximumWordsInACorrection = PhoneticIndex.maximumWordsPerEntry

    // MARK: - Seen on screen

    /// The terms that were in front of the user *and* came out of their mouth.
    ///
    /// One dictation's worth of evidence, which on its own is worth nothing: the caller
    /// counts these across dictations and only the ones that keep coming back are kept.
    ///
    /// Read from the window or document title alone. Not from the application name,
    /// which is on screen for every dictation the user makes in that app and would
    /// therefore be "corroborated" within three sentences of opening it — the name of
    /// every app they dictate in is not a personal vocabulary. And deliberately not from
    /// the selected text, which is the sharper point: **the selection is not context, it
    /// is the text this dictation is about to replace.** Both insertion routes write over
    /// the selection, so every word in it is a word the user is deleting, and a
    /// dictionary that learnt from it would learn precisely what they were getting rid
    /// of. The selection has one honest use, and it is the correction below.
    ///
    /// "Spoken" is judged by sound and not by spelling, through the same phonetics as
    /// everything else here. That is the whole value of the path: a title saying
    /// `PaymentSheet.swift` and a speaker saying "payment sheet" is the case worth
    /// learning, and a literal match would miss every one of them — if the recogniser
    /// had already spelt it the way the screen does, the dictionary would have nothing
    /// to fix.
    static func seenAndSaid(heard: String, seeing context: AppContext) -> [String] {
        guard let title = context.documentName else { return [] }
        let said = Utterance(heard: heard, confidence: 1)
            .sounds(upTo: PhoneticIndex.maximumWordsPerEntry)
        guard !said.isEmpty else { return [] }

        var found: [String] = []
        var already: Set<String> = []
        for term in words(in: title, atMost: WorkingSet.maximumWordsOnScreen)
        where GeneralVocabulary.isWorthLearning(term) && already.insert(term.lowercased()).inserted {
            guard DoubleMetaphone.code(for: term).sounds(likeAnyOf: said) else { continue }
            found.append(term)
        }
        return found
    }

    // MARK: - Corrected by the user

    /// The spelling a dictation over a selection was correcting, if it was correcting one.
    ///
    /// The strongest signal in the product, and the only one where the user is telling
    /// Uttrflow it got a word wrong rather than Uttrflow inferring it. They highlighted
    /// "utter flow", said it again, and let "Uttrflow" stand in its place: two spellings of
    /// one sound, one of which they have just rejected by hand.
    ///
    /// Four conditions, and all of them are refusals.
    ///
    /// 1. *Both sides are short* — at most ``maximumWordsInACorrection`` words. A long
    ///    selection being rewritten is editing, not correcting.
    /// 2. *They are spelt differently* — where the spaces fall being part of the
    ///    spelling, because "payment sheet" written as `PaymentSheet` is the commonest
    ///    correction there is. Re-dictating a phrase and getting the same words back is
    ///    not a correction; nothing was wrong and nothing was fixed. Capitals alone do
    ///    not count either: a recogniser that heard the word is not a recogniser that
    ///    got it wrong.
    /// 3. *They sound the same* — the whole phrase against the whole phrase, matched the
    ///    way the index matches everything else. Whole-phrase and not word-by-word is
    ///    what stops two sentences that merely share a word being read as a correction.
    /// 4. *Every word of the replacement is one a general model would not know.* Without
    ///    this the path learns "their" the first time somebody re-dictates "there", and
    ///    puts a homophone of an ordinary English word into the index — which is the one
    ///    way this feature could make a correct sentence wrong.
    ///
    /// What is learnt is the replacement, because that is the spelling the user chose to
    /// keep. It is stored without a pronunciation: the two spellings sound identical —
    /// that is what condition three established — so the entry's own spelling is already
    /// a fair guide to it, and writing the rejected one into the pronunciation field
    /// would index the word under a sound it is already filed under.
    static func corrected(over selection: String?, wrote: String) -> String? {
        guard let selection else { return nil }
        // One word past the limit is all that needs counting: anything longer is refused
        // by the same guard, and a 512-character selection should not be split in full
        // to discover that.
        let before = words(in: selection, atMost: maximumWordsInACorrection + 1)
        let after = words(in: wrote, atMost: maximumWordsInACorrection + 1)
        guard (1...maximumWordsInACorrection).contains(before.count),
            (1...maximumWordsInACorrection).contains(after.count),
            before.joined(separator: " ").lowercased() != after.joined(separator: " ").lowercased()
        else { return nil }

        let replacement = after.joined(separator: " ")
        let sound = DoubleMetaphone.code(for: replacement)
        guard !sound.isSilent,
            sound.sounds(like: DoubleMetaphone.code(for: before.joined(separator: " ")))
        else { return nil }
        guard after.allSatisfy(GeneralVocabulary.isWorthLearning) else { return nil }
        return replacement
    }

    // MARK: - Reading words out of a screen

    /// The words in a piece of text, as this module counts words.
    ///
    /// Split on anything that is not a letter, exactly as ``WorkingSet/soundsOnScreen``
    /// splits: a title reading `PaymentSheet.swift — Uttrflow` offers `PaymentSheet`,
    /// `swift` and `Uttrflow` rather than one run that matches nothing. Digits separate
    /// rather than join, which costs nothing — ``DoubleMetaphone`` makes no sound for
    /// them, so a word containing one is filed under the letters either side anyway.
    ///
    /// Bounded by the caller because both callers can be handed something unbounded: a
    /// window title is whatever an app chose to put there.
    static func words(in text: String, atMost limit: Int) -> [String] {
        text.split { !$0.isLetter }.prefix(limit).map(String.init)
    }
}

/// How often each term Uttrflow has noticed but not yet learnt has turned up.
///
/// In memory and never on disk, which is a privacy decision before it is a design one.
/// The words in here came off the user's screen and most of them will never become
/// entries; writing them to a file would mean Uttrflow kept a record of what somebody had
/// open, in a file no page in the app shows and no button clears. Keeping the tally in
/// memory means the only thing that ever reaches the disk is a word that earned its
/// place — a word, not a title, not a sentence, not a path.
///
/// The cost of that is honest and small: three dictations that would have learnt a word
/// have to happen while the app is running, and quitting forgets a term that was two
/// thirds of the way there. Both are the right side of the trade, and the second is
/// arguably a feature — evidence that has aged past a restart is evidence about a
/// different day's work.
struct SightingLedger: Sendable {
    /// The most terms kept waiting at once.
    ///
    /// A hundred and twenty-eight. The tally is bounded for the same reason the phonetic
    /// index's buckets are: a structure that grows with everything the user has ever
    /// glanced at is a leak, and here it would be a leak made of their window titles.
    /// Well above the vocabulary of a day's work, so pruning cannot realistically cost a
    /// word that was about to be learnt.
    static let maximumPending = 128

    private struct Sighting: Sendable {
        /// The spelling first seen, kept rather than replaced so that a term counted
        /// three times cannot come out spelt whichever way the last dictation happened
        /// to see it.
        let word: String
        var count: Int
    }

    private var sightings: [String: Sighting] = [:]
    /// Words the user has deleted since Uttrflow started.
    ///
    /// A deletion is a judgement, and a word that reappears three dictations after being
    /// deleted is the app arguing with the person using it — the precise thing "learn
    /// without being aggressive" rules out. Refusing them is what stops the argument.
    ///
    /// Not spellings kept on disk, deliberately: a permanent record of words somebody
    /// rejected is a new thing to keep about them, and this is bounded by the run rather
    /// than by their history. That does mean a deleted term can be learnt again in a
    /// later session — recorded as a known limit rather than settled here, because
    /// whether a deletion should outlive a quit is a product decision and not a
    /// correctness one.
    private var refused: Set<String> = []

    /// Stops counting a word, and stops it being counted again.
    ///
    /// What a deletion reaches. Clearing the tally alone would not be enough: the term is
    /// still in the window title and still being said, so it would simply be counted back
    /// up to the threshold.
    mutating func refuse(_ word: String) {
        let key = word.lowercased()
        sightings[key] = nil
        refused.insert(key)
    }

    /// Counts one dictation's sightings, answering with the terms that have now been
    /// seen and said often enough to keep.
    ///
    /// A term that reaches the threshold leaves the tally as it is returned: it is about
    /// to become an entry, and an entry that is also still being counted here would be
    /// learnt twice.
    mutating func record(_ terms: [String]) -> [String] {
        var learnt: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard !refused.contains(key) else { continue }
            var sighting = sightings[key] ?? Sighting(word: term, count: 0)
            sighting.count += 1
            if sighting.count >= LearnableWords.sightingsBeforeLearning {
                sightings[key] = nil
                learnt.append(sighting.word)
            } else {
                sightings[key] = sighting
            }
        }
        prune()
        return learnt
    }

    /// Throws the tally away.
    ///
    /// Called by the reset, and that is not tidiness. Half-counted evidence is still the
    /// app's inference about the user, and a reset that left it behind would let a word
    /// appear one dictation after somebody asked Uttrflow to forget what it had worked
    /// out — which is the one thing that reset must never do.
    ///
    /// The refusals go too. A reset is the user asking to start again, and starting again
    /// includes being allowed to learn a word they once deleted.
    mutating func forgetEverything() {
        sightings.removeAll()
        refused.removeAll()
    }

    /// Drops the weakest evidence when the tally outgrows its bound.
    ///
    /// Best-corroborated first, then alphabetically, so that a machine under memory
    /// pressure and a machine under none learn the same words in the same order.
    private mutating func prune() {
        guard sightings.count > Self.maximumPending else { return }
        let kept = sightings.sorted {
            $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key
        }
        sightings = Dictionary(
            uniqueKeysWithValues: kept.prefix(Self.maximumPending).map { ($0.key, $0.value) })
    }
}

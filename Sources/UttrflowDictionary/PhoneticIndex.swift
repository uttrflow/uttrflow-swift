private import struct Foundation.UUID

/// The dictionary arranged by how its words sound, so that "clawed", "cloud" and
/// "Claude" land in one place on purpose.
///
/// A hash of sound to entries, built once and read many times. Every lookup is a
/// dictionary probe against a bucket of bounded size, so answering takes the same time
/// with fifty thousand entries as with ten — and that, rather than the phonetics, is
/// the property the rest of the product is built on. A scan would work perfectly well
/// at the sizes we have today and would quietly become the slowest thing in a dictation
/// at the sizes we are aiming for.
///
/// A value type, not an actor. It is immutable once built, so it is safe to hand across
/// isolation without ceremony; the mutable half of the world lives in
/// ``PersonalDictionaryStore``, which rebuilds one of these whenever it writes.
public struct PhoneticIndex: Sendable, Equatable {
    /// The most entries kept for any one sound.
    ///
    /// This is what makes the lookup genuinely constant-time rather than
    /// constant-on-average: without it, a sound that thousands of entries share would
    /// turn one probe into a scan of thousands. The cap costs nothing real, because a
    /// bucket of five hundred homophones is not a shortlist a recogniser could use
    /// anyway — the entries dropped are the ones the ranking below already judged least
    /// useful.
    public static let maximumPerSound = 8

    /// How many candidates one utterance may produce.
    ///
    /// A ceiling on the shortlist, not on the dictionary. Chosen so that the words fit
    /// comfortably inside a conditioning prompt alongside the utterance itself.
    public static let defaultCandidateLimit = 24

    /// The longest run of spoken words that can be one entry.
    ///
    /// Three, because `setUserPrefs` is said as three words and is the shape of thing
    /// this dictionary is full of. Four would double the lookups for a class of entry
    /// nobody has yet asked for.
    public static let maximumWordsPerEntry = 3

    private let buckets: [String: [DictionaryEntry]]

    /// Files every entry under every sound it could be heard as.
    ///
    /// Entries that have retired themselves are left out here rather than filtered at
    /// lookup: a retired word must stop being offered, and doing it once at build time
    /// keeps the hot path free of the decision. Nothing is lost by it — the store still
    /// holds the entry, and ``DictionaryEntry/isTrustworthy`` still says why it went, so
    /// the user can be shown both.
    public init(entries: [DictionaryEntry]) {
        var buckets: [String: [DictionaryEntry]] = [:]
        for entry in entries where entry.isTrustworthy {
            for key in DoubleMetaphone.code(for: entry.soundsLike).keys {
                buckets[key, default: []].append(entry)
            }
        }
        self.buckets = buckets.mapValues {
            Array($0.sorted(by: PhoneticIndex.isMoreUseful).prefix(PhoneticIndex.maximumPerSound))
        }
    }

    /// Everything that could be what the speaker actually said.
    ///
    /// One hash probe per code — at most two — and then a bounded bucket. The size of
    /// the dictionary does not appear anywhere in that sentence, which is the point.
    public func candidates(soundingLike word: String) -> [DictionaryEntry] {
        var seen: Set<UUID> = []
        var found: [DictionaryEntry] = []
        for key in DoubleMetaphone.code(for: word).keys {
            for entry in buckets[key] ?? [] where seen.insert(entry.id).inserted {
                found.append(entry)
            }
        }
        return found
    }

    /// **The guarantee.** The candidates worth showing a recogniser for one utterance,
    /// and never more than a handful.
    ///
    /// The size of what comes back is a function of the utterance and the limit alone.
    /// It cannot grow with the dictionary, because the dictionary is only ever reached
    /// through a hash probe on a sound the speaker actually made, and because every
    /// bucket behind those probes is capped. A user with fifty thousand words gets the
    /// same prompt as a user with ten, and pays the same for it.
    ///
    /// This is the rule the whole design rests on, so it is asserted mechanically in the
    /// tests rather than described here and hoped for.
    public func candidates(
        for utterance: Utterance, limit: Int = PhoneticIndex.defaultCandidateLimit
    ) -> [DictionaryEntry] {
        guard limit > 0 else { return [] }
        var seen: Set<UUID> = []
        var found: [DictionaryEntry] = []
        for span in utterance.spans(upTo: PhoneticIndex.maximumWordsPerEntry) {
            for entry in candidates(soundingLike: span.text) where seen.insert(entry.id).inserted {
                found.append(entry)
                if found.count == limit { return found }
            }
        }
        return found
    }

    /// Which of two entries sharing a sound deserves the bucket slot.
    ///
    /// A total order, right down to the identifier. Anything less would let two runs of
    /// the same build return different shortlists for the same words, and a guarantee
    /// nobody can reproduce is not one.
    static func isMoreUseful(_ first: DictionaryEntry, _ second: DictionaryEntry) -> Bool {
        // Uses the user did not undo. Raw uses would rank a word that is applied
        // constantly and reverted almost as often above one that quietly works.
        let firstNet = first.timesUsed - first.timesReverted
        let secondNet = second.timesUsed - second.timesReverted
        if firstNet != secondNet { return firstNet > secondNet }
        if first.firstSeen != second.firstSeen { return first.firstSeen > second.firstSeen }
        if first.word != second.word { return first.word < second.word }
        return first.id.uuidString < second.id.uuidString
    }
}

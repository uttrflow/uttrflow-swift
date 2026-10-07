// The dictionary arranged by sound.

private import struct Foundation.UUID
public import UttrflowCore

/// The dictionary arranged by sound, so a lookup costs the same with fifty thousand entries as with ten.
public struct PhoneticIndex: Sendable, Equatable {
    /// The most entries kept for any one sound, which is what makes a lookup constant-time.
    public static let maximumPerSound = 8

    /// How many candidates one utterance may produce: a ceiling on the shortlist, not on the dictionary.
    public static let defaultCandidateLimit = 24

    /// The longest run of spoken words that can be one entry; `setUserPrefs` is said as three.
    public static let maximumWordsPerEntry = 3

    /// The longest spelling in UTF-8 bytes; a byte-level tokeniser keeps it inside the 111-token recogniser prompt.
    public static let maximumBytesPerEntry = 80

    /// Whether both editor fields fit the spans the lookup can produce and the recogniser prompt.
    public static func supports(word: String, pronunciation: String?) -> Bool {
        refusal(word: word, pronunciation: pronunciation) == nil
    }

    /// Why an entry cannot be kept, or `nil` when it fits; the one check the store, editor and import share.
    public static func refusal(word: String, pronunciation: String?) -> DictionaryStoreError? {
        guard
            wordCount(in: word) <= maximumWordsPerEntry,
            pronunciation.map({ wordCount(in: $0) <= maximumWordsPerEntry }) ?? true
        else { return .entryHasTooManyWords(maximum: maximumWordsPerEntry) }
        guard word.utf8.count <= maximumBytesPerEntry else {
            return .entryIsTooLong(maximum: maximumBytesPerEntry)
        }
        return nil
    }

    /// Why a whole entry cannot be kept: its spelling against each pronunciation in turn, or `nil` when all fit.
    public static func refusal(for entry: DictionaryEntry) -> DictionaryStoreError? {
        let sounds: [String?] = entry.pronunciations.isEmpty ? [nil] : entry.pronunciations
        return sounds.lazy.compactMap { refusal(word: entry.word, pronunciation: $0) }.first
    }

    /// The words separated by whitespace, which is how recogniser utterances are split.
    public static func wordCount(in text: String) -> Int {
        Utterance(heard: text, confidence: 1).words.count
    }

    /// Counts every entry a lookup reads, so a test can show the cost does not follow the dictionary's size.
    @TaskLocal package static var entriesRead: WorkTally?

    private let buckets: Buckets

    /// Every trustworthy entry under its spelling with case folded, so a case-only difference is one probe.
    private let byFoldedSpelling: [String: [DictionaryEntry]]

    /// Entries no coder could address, which nothing can ever look up; empty unless a spelling is all punctuation.
    public let unaddressable: [DictionaryEntry]

    /// A digest of every trustworthy entry and its counts, equal for equal contents across launches.
    public let revision: UInt64

    /// Each filed entry's Double Metaphone code, keyed by what it sounds like, so a ranking never encodes it again.
    private let codes: [String: PhoneticCode]

    /// Files every trustworthy entry under every sound it could be heard as, and names any it could not file.
    public init(entries: [DictionaryEntry]) {
        var buckets: [String: [DictionaryEntry]] = [:]
        var unfiled: [DictionaryEntry] = []
        var spelt: [String: [DictionaryEntry]] = [:]
        var codes: [String: PhoneticCode] = [:]
        for entry in entries where entry.isTrustworthy {
            spelt[entry.word.lowercased(), default: []].append(entry)
            var keys: Set<String> = []
            for reading in entry.readings {
                let code = codes[reading] ?? DoubleMetaphone.code(for: reading)
                codes[reading] = code
                keys.formUnion(PronunciationCoder.keys(for: reading, sounding: code))
            }
            guard !keys.isEmpty else {
                unfiled.append(entry)
                continue
            }
            for key in keys {
                buckets[key, default: []].append(entry)
            }
        }
        self.unaddressable = unfiled
        self.revision = Self.digest(of: entries.filter(\.isTrustworthy))
        self.byFoldedSpelling = spelt.mapValues { $0.sorted(by: PhoneticIndex.isMoreUseful) }
        self.codes = codes
        self.buckets = Buckets(
            buckets.mapValues {
                Array($0.sorted(by: PhoneticIndex.isMoreUseful).prefix(PhoneticIndex.maximumPerSound))
            })
    }

    /// FNV-1a over each entry's identity, spelling, sound and counts, in identifier order.
    private static func digest(of entries: [DictionaryEntry]) -> UInt64 {
        let fields = entries.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            [
                $0.id.uuidString, $0.word, $0.pronunciations.joined(separator: "\u{1D}"), "\($0.origin)",
                "\($0.timesUsed)",
                "\($0.timesReverted)",
            ]
            .joined(separator: "\u{1F}")
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in fields.joined(separator: "\u{1E}").utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The code the index already made for an entry sounding like `soundsLike`; nil when no filed entry does.
    public func code(soundingLike soundsLike: String) -> PhoneticCode? {
        codes[soundsLike]
    }

    /// Everything that could be what the speaker said: one hash probe per code, then a bounded bucket.
    public func candidates(soundingLike word: String) -> [DictionaryEntry] {
        var seen: Set<UUID> = []
        var found: [DictionaryEntry] = []
        for key in PronunciationCoder.keys(for: word) {
            for entry in buckets[key] where seen.insert(entry.id).inserted {
                found.append(entry)
            }
        }
        return found
    }

    /// The entries spelt with exactly these letters once case is folded, most useful first; never a near spelling.
    public func entries(speltAs text: String) -> [DictionaryEntry] {
        byFoldedSpelling[text.lowercased()] ?? []
    }

    /// The guarantee: the candidates for one utterance, a function of the utterance and the limit alone.
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

    /// Which of two entries sharing a sound deserves the bucket slot; a total order, down to the identifier.
    static func isMoreUseful(_ first: DictionaryEntry, _ second: DictionaryEntry) -> Bool {
        // Uses the user did not undo, so a constantly reverted word does not outrank one that works.
        if first.netUses != second.netUses { return first.netUses > second.netUses }
        if first.firstSeen != second.firstSeen { return first.firstSeen > second.firstSeen }
        if first.word != second.word { return first.word < second.word }
        return first.id.uuidString < second.id.uuidString
    }
}

extension PhoneticIndex {
    /// The entries filed by sound, reachable only through accessors that count what they hand out.
    private struct Buckets: Sendable, Equatable, Sequence {
        private let storage: [String: [DictionaryEntry]]

        init(_ storage: [String: [DictionaryEntry]]) {
            self.storage = storage
        }

        /// The entries filed under one sound, counted as read.
        subscript(key: String) -> [DictionaryEntry] {
            let bucket = storage[key] ?? []
            PhoneticIndex.entriesRead?.record(bucket.count)
            return bucket
        }

        /// Every bucket in turn, each counted as read when it is reached.
        func makeIterator()
            -> LazyMapSequence<[String: [DictionaryEntry]], (key: String, entries: [DictionaryEntry])>
            .Iterator
        {
            storage.lazy.map { key, entries in
                PhoneticIndex.entriesRead?.record(entries.count)
                return (key, entries)
            }.makeIterator()
        }
    }
}

// The words worth conditioning the recogniser with.

public import UttrflowCore
public import struct Foundation.Date

/// The words worth putting in front of the recogniser before it decodes anything, and why the rest are not.
public enum WorkingSet {
    /// How many dictionary words usually fit beside everything else that conditions the decoder.
    public static let defaultLimit = 28

    /// The age at which a word's value halves: thirty days.
    static let recencyHalfLifeInDays = 30.0

    /// What the frontmost app agreeing with an entry is worth: one, the most frequency alone can give.
    static let affinityWeight = 1.0

    /// How long a manually added word keeps priority over older dictionary entries.
    static let newAdditionPriorityDays = 7.0

    /// Unused inferred words stop occupying prompt slots after this many days.
    public static let unusedInferredLifetimeDays = 30.0

    /// Where one entry stands against the recogniser prompt, and why when it is left out.
    public enum Standing: Sendable, Equatable {
        /// Offered to the recogniser at this rank, best first from one.
        case inPrompt(rank: Int)
        /// Ranked here, past the limit of words offered.
        case belowLimit(rank: Int, limit: Int)
        /// Left out because this better-ranked word already holds its sound.
        case sharesSound(with: String)
        /// Undone more often than kept, so it conditions nothing.
        case retired
        /// Inferred, never kept, and older than the unused lifetime.
        case unusedInferred
        /// Ranked in, but the last packed prompt had no room for its tokens.
        case tooLong(rank: Int)

        /// Whether the ranking offers this word to the prompt packer.
        public var isOffered: Bool {
            switch self {
            case .inPrompt, .tooLong: true
            case .belowLimit, .sharesSound, .retired, .unusedInferred: false
            }
        }
    }

    /// The highest-value words within `limit`, best first, scored on frequency, recency and screen affinity.
    public static func words(
        from entries: [DictionaryEntry],
        coded index: PhoneticIndex? = nil,
        limit: Int = WorkingSet.defaultLimit,
        now: Date,
        favouring context: AppContext = .unknown
    ) -> [String] {
        ranking(of: entries, coded: index, limit: limit, now: now, favouring: context, packed: nil)
            .filter { $0.standing.isOffered }
            .map(\.entry.word)
    }

    /// Every entry's standing, keyed by id; `packed` is the last prompt's words, when one has been packed.
    public static func explain(
        entries: [DictionaryEntry],
        limit: Int = WorkingSet.defaultLimit,
        now: Date,
        favouring context: AppContext = .unknown,
        packed: [String]? = nil
    ) -> [DictionaryEntry.ID: Standing] {
        Dictionary(
            ranking(of: entries, coded: nil, limit: limit, now: now, favouring: context, packed: packed)
                .map { ($0.entry.id, $0.standing) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The one ranking: offered entries best first, then every other entry with its reason; `index` supplies codes already made.
    static func ranking(
        of entries: [DictionaryEntry],
        coded index: PhoneticIndex?,
        limit: Int,
        now: Date,
        favouring context: AppContext,
        packed: [String]?
    ) -> [(entry: DictionaryEntry, standing: Standing)] {
        var excluded: [(entry: DictionaryEntry, standing: Standing)] = []
        let wanted = soundsOnScreen(in: context)
        let eligible = entries.filter { entry in
            guard entry.isTrustworthy else {
                excluded.append((entry, .retired))
                return false
            }
            guard entry.origin == .learned || entry.origin == .observed else { return true }
            let kept =
                entry.netUses > 0
                || now.timeIntervalSince(entry.firstSeen) <= unusedInferredLifetimeDays * 86_400
            if !kept { excluded.append((entry, .unusedInferred)) }
            return kept
        }
        let ranked =
            eligible
            .map { entry in
                let code =
                    index?.code(soundingLike: entry.soundsLike) ?? DoubleMetaphone.code(for: entry.soundsLike)
                return (
                    entry: entry, code: code,
                    value: value(of: entry, sounding: code, now: now, wanted: wanted)
                )
            }
            .sorted { first, second in
                let firstIsNew = isNewAddition(first.entry, now: now)
                let secondIsNew = isNewAddition(second.entry, now: now)
                if firstIsNew != secondIsNew { return firstIsNew }
                if firstIsNew, first.entry.firstSeen != second.entry.firstSeen {
                    return first.entry.firstSeen > second.entry.firstSeen
                }
                if first.value != second.value { return first.value > second.value }
                // Ties broken the same way buckets are, so the two lists never disagree.
                return PhoneticIndex.isMoreUseful(first.entry, second.entry)
            }
        let fitted = packed.map(Set.init)
        var holders: [String: String] = [:]
        var placed: [(entry: DictionaryEntry, standing: Standing)] = []
        var rank = 0
        for candidate in ranked {
            let keys = candidate.code.keys
            if let holder = keys.lazy.compactMap({ holders[$0] }).first {
                placed.append((candidate.entry, .sharesSound(with: holder)))
                continue
            }
            for key in keys { holders[key] = candidate.entry.word }
            rank += 1
            let standing: Standing
            if rank > limit {
                standing = .belowLimit(rank: rank, limit: limit)
            } else if let fitted, !fitted.contains(candidate.entry.word) {
                standing = .tooLong(rank: rank)
            } else {
                standing = .inPrompt(rank: rank)
            }
            placed.append((candidate.entry, standing))
        }
        return placed + excluded
    }

    /// Whether the entry was manually added within the priority window.
    static func isNewAddition(_ entry: DictionaryEntry, now: Date) -> Bool {
        entry.origin == .added
            && now.timeIntervalSince(entry.firstSeen) >= 0
            && now.timeIntervalSince(entry.firstSeen) <= newAdditionPriorityDays * 86_400
    }

    /// The most words read off the screen, so a selected document is a bounded read.
    static let maximumWordsOnScreen = 64

    /// The sounds of everything the frontmost app is showing, split on anything that is not a letter.
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
    static func value(
        of entry: DictionaryEntry, sounding code: PhoneticCode, now: Date, wanted: Set<String>
    ) -> Double {
        let kept = Double(max(0, entry.netUses))
        let frequency = kept / (1 + kept)
        // Clamped at zero, so a future-stamped entry scores as brand new, not impossibly valuable.
        let ageInDays = max(0, now.timeIntervalSince(entry.firstSeen)) / 86_400
        let recency = recencyHalfLifeInDays / (recencyHalfLifeInDays + ageInDays)
        let onScreen = code.sounds(likeAnyOf: wanted)
        return frequency + recency + (onScreen ? affinityWeight : 0)
    }
}

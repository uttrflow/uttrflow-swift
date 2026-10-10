// A user's choice between two spellings of one listed word, kept as evidence rows and projected on read.

public import UttrflowCore

/// Which spelling of a listed word the user prefers, projected from evidence rows. See `Docs/learned-state.md`.
public enum SpellingPreferences {
    /// Separate days an edit must be seen on before it is a preference, so a lone edit is inert.
    public static let daysBeforePreferring = 3

    /// The rows one edit inside dictated text adds: one per word pair that are two spellings of one listed word.
    public static func rows(
        replacing old: [String], with new: [String], day: Int, provenance: EvidenceRow.Provenance = .dictation
    ) -> [EvidenceRow] {
        // A changed word count is a rewrite, not a respelling, and teaches nothing.
        guard old.count == new.count else { return [] }
        return zip(old, new).compactMap { heard, meant in
            guard GeneralVocabulary.isHindiSpellingPreference(meant, over: heard) else { return nil }
            return EvidenceRow(
                kind: .spellingPreference, subject: subject(heard: heard, meant: meant), day: day,
                provenance: provenance)
        }
    }

    /// The row the user writes by deleting a preference: every earlier row about the word is ignored.
    public static func clearing(heard: String, meant: String, day: Int) -> [EvidenceRow] {
        [subject(heard: heard, meant: meant), subject(heard: meant, meant: heard)].map {
            EvidenceRow(kind: .spellingPreferenceCleared, subject: $0, day: day, provenance: .user)
        }
    }

    /// The preferred spelling for each heard spelling, lowercased; an edit back the other way counts against.
    public static func project(_ rows: [EvidenceRow]) -> [String: String] {
        var cleared: [String: Int] = [:]
        for row in rows where row.kind == .spellingPreferenceCleared {
            cleared[row.subject] = max(cleared[row.subject] ?? .min, row.day)
        }
        var net: [String: Int] = [:]
        var days: [String: Set<Int>] = [:]
        for row in rows where row.kind == .spellingPreference && row.day > (cleared[row.subject] ?? .min) {
            net[row.subject, default: 0] += row.weight
            if row.weight > 0 { days[row.subject, default: []].insert(row.day) }
        }
        var preferred: [String: String] = [:]
        for (key, weight) in net {
            guard let pair = pair(in: key),
                GeneralVocabulary.isHindiSpellingPreference(pair.meant, over: pair.heard),
                weight > net[subject(heard: pair.meant, meant: pair.heard), default: 0],
                (days[key]?.count ?? 0) >= daysBeforePreferring
            else { continue }
            preferred[pair.heard] = pair.meant
        }
        return preferred
    }

    /// The spelling each heard spelling is written in: a dictionary entry's for its listed Hindi word, else `learnt`.
    public static func preferred(
        filed entries: [DictionaryEntry], learnt: [String: String]
    ) -> [String: String] {
        // An entry the user typed outranks one an edit taught, and a newer entry an older one.
        let ranked = entries.sorted { first, second in
            first.origin == .added && second.origin != .added
                || (first.origin == .added) == (second.origin == .added) && first.firstSeen > second.firstSeen
        }
        var filed: [String: String] = [:]
        for entry in ranked {
            for word in entry.word.split(separator: " ").map(String.init)
            where !GeneralVocabulary.otherSpellings(of: word).isEmpty {
                let key = Romaniser.soundKey(word)
                if filed[key] == nil { filed[key] = word }
            }
        }
        // The dictionary decides every spelling of a word it holds, so nothing learnt overrides an entry.
        var preferred = learnt.filter { filed[Romaniser.soundKey($0.key)] == nil }
        for word in filed.values {
            // A spelling that is also English ("main") may mean that word, so it is never respelt.
            for spelling in GeneralVocabulary.otherSpellings(of: word)
            where !LexicalClass.isKnownEnglishWord(spelling) {
                preferred[spelling] = word
            }
        }
        return preferred
    }

    /// The row subject for one pair: both spellings lowercased, which are listed vocabulary and never user text.
    static func subject(heard: String, meant: String) -> String {
        heard.lowercased() + String(separator) + meant.lowercased()
    }

    private static func pair(in subject: String) -> (heard: String, meant: String)? {
        let sides = subject.split(separator: separator, omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        return (String(sides[0]), String(sides[1]))
    }

    private static let separator: Character = ">"
}

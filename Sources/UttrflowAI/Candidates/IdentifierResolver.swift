internal import UttrflowCore
internal import UttrflowDictionary

/// The identifiers the screen shows: names joined by case or underscores, read from the text the screen candidates read.
struct ScreenVocabulary: Sendable, Equatable {
    /// Each identifier once, in the order the screen shows them.
    let identifiers: [String]

    /// Keeps only the words shaped like identifiers, so prose on screen never binds a spoken run.
    init(identifiers: [String]) {
        var seen: Set<String> = []
        self.identifiers = identifiers.filter { Self.isIdentifier($0) && seen.insert($0).inserted }
    }

    /// The identifiers in the window title, the selection and the text either side of the caret, secrets dropped.
    init(_ situation: Situation) {
        let words = ScreenCandidates.shownText(on: situation)
            .split { !($0.isLetter || $0.isNumber || $0 == "_") }
            .prefix(ScreenCandidates.maximumWordsOnScreen)
        self.init(identifiers: words.map { $0.trimmingUnderscores })
    }

    /// A screen that shows no identifier.
    static let empty = ScreenVocabulary(identifiers: [])

    /// Letters, digits and inner underscores, joined by an underscore or a lower-case letter before a capital.
    static func isIdentifier(_ word: String) -> Bool {
        guard word.count >= ScreenCandidates.shortestWorthOffering, word.first?.isLetter == true,
            word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return false }
        if word.contains("_") { return true }
        return zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
    }
}

extension Substring {
    /// The word without the underscores that open or close it, which mark privacy rather than join words.
    fileprivate var trimmingUnderscores: String {
        String(drop { $0 == "_" }.reversed().drop { $0 == "_" }.reversed())
    }
}

/// The one answer to which identifier on screen a spoken run names, asked by the rules and offered to the model.
enum IdentifierResolver {
    /// What a spoken run binds to.
    enum Binding: Sendable, Equatable {
        /// Exactly one identifier on screen spells or sounds like the run.
        case bound(String)
        /// Two or more tie, so the words stay as spoken.
        case ambiguous([String])
        /// None matches, so the words stay as spoken.
        case none
    }

    /// The identifier the spoken words name: one spelt alike wins, else one sounding alike; a tie or nothing binds none.
    static func bind(spokenWords: [String], vocabulary: ScreenVocabulary) -> Binding {
        guard !spokenWords.isEmpty, !vocabulary.identifiers.isEmpty else { return .none }
        let heard = ReadingKey(spokenWords.joined(separator: " "))
        let found = matches(for: heard, among: vocabulary.identifiers.map(ReadingKey.init))
        for tier in [found.spelled, found.sounded] where !tier.isEmpty {
            return tier.count == 1 ? .bound(tier[0]) : .ambiguous(tier)
        }
        return .none
    }

    /// The shown words that spell the run with its spaces closed up, then those that sound and open like it.
    static func matches(
        for heard: ReadingKey, among shown: [ReadingKey]
    ) -> (spelled: [String], sounded: [String]) {
        var spelled: [String] = []
        var sounded: [String] = []
        for screen in shown {
            if screen.closed == heard.closed {
                spelled.append(screen.word)
            } else if ReadingRestraint.isWorthOffering(screen, for: heard) {
                sounded.append(screen.word)
            }
        }
        return (spelled, sounded)
    }
}

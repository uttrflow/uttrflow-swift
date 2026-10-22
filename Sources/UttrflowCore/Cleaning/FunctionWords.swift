/// The small words a phrase is built from, which carry structure rather than what was said.
public enum FunctionWords {
    /// Whether the word is one of the small words, apostrophes and case aside.
    public static func holds(_ word: String) -> Bool {
        all.contains(word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
    }

    /// Whether the word carries meaning, so a restatement may be anchored on it or replace it.
    public static func isContent(_ word: String) -> Bool { !word.isEmpty && !holds(word) }

    /// Whether a sentence cannot end on the word, since it leads into what follows ("the", "and", "is", "let's").
    public static func leadsOn(_ word: String) -> Bool {
        let key = word.lowercased()
        return leadingOn.contains(key) || Restatement.contractedSubjects.contains(key)
    }

    /// Whether a full stop the recogniser wrote after the word stands: "is" ends "Yes, it is." and a stopped "for" or "with" ends a relative clause
    package static func closesWhenStopped(_ word: String) -> Bool {
        closing.contains(word.lowercased())
    }

    /// Whether the word joins two alternatives or additions ("and", "or", "but", "nor"), so a sound-alike in its place says something else.
    package static func isCoordinator(_ word: String) -> Bool { coordinators.contains(word.lowercased()) }

    /// Whether the small word carries meaning the rewrite must keep: who acts, whether it is possible or required, or where it goes.
    public static func isMeaningBearing(_ word: String) -> Bool {
        let key = word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        return meaningBearing.contains(key)
    }

    /// Whether a capital on this small word can name something, as "I", the month "May" and the name "Will" do, so the capital is the speaker's.
    package static func isCaseSensitive(_ word: String) -> Bool {
        caseSensitive.contains(word.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
    }

    /// Small words a capital turns into a name or the pronoun "I".
    static let caseSensitive = words(in: .caseSensitive)

    /// Pronouns, modals, copula and perfect aux, and prepositions that set a direction; their removal or substitution changes what was said.
    public static let meaningBearing = words(in: .meaningBearing)

    /// Articles, demonstratives and possessives, which mark the noun after them as a common noun ("my", "the").
    public static let determiners = words(in: .determiner)

    /// Articles and plural demonstratives code is never dictated with, so any of them marks an utterance as prose.
    public static let prose = words(in: .prose)

    /// Articles, possessives, conjunctions, prepositions that take an object, and the copula.
    static let leadingOn = words(in: .leadsOn)

    /// The copulas and prepositions a written stop after them is kept, since they end an elliptical answer or a relative clause.
    static let closing = words(in: .closesWhenStopped)

    /// Question words and quantity words a relative clause's object gap refers back to: "what we asked for", "all we spoke of".
    static let objectGapHeads = words(in: .objectGapHead)

    /// The words after "which is" that make the clause carry on the speaker's thought.
    static let relativeWhichTails = words(in: .relativeWhichTail)

    /// Auxiliaries and modals, which a following "not" negates ("is not", "can not").
    package static let auxiliaries = words(in: .auxiliary)

    /// Conjunctions that open a clause which cannot stand as a sentence by itself ("if", "unless", "whereas").
    static let subordinators = words(in: .subordinator)

    /// Conjunctions that join two alternatives or additions of equal rank.
    static let coordinators = words(in: .coordinator)

    /// English words that ask for agreement when they close a Hindi sentence ("right", "okay", "no").
    static let closingTags = words(in: .closingTag)

    /// Articles, determiners, prepositions, conjunctions, auxiliaries and pronouns, English and romanised Hindi; dialect stays content.
    public static let all = english.union(HindiWords.functionWords)

    /// The English small words alone.
    package static let english = words(in: .function)

    /// Determiners a sentence-boundary check reads as opening a noun phrase.
    static let boundaryDeterminers = words(in: .boundaryDeterminer)

    /// Words that cannot close a sentence, whatever the tagger reads them as ("of", "with", "because").
    static let neverLast = words(in: .neverLast)

    /// Words that cannot open a sentence, so a stop before them is a stop inside a phrase ("to", "toward").
    static let neverFronted = words(in: .neverFronted)

    /// Object pronouns an imperative takes straight after its verb ("let it", "give them").
    package static let imperativeObjects = words(in: .imperativeObject)

    /// Words a bare verb follows inside one clause, beyond the inverting verbs ("do", "must", "let").
    static let bareVerbLeaders = words(in: .bareVerbLeader)

    /// Modal verbs, which need a verb after them.
    static let modals = words(in: .modal)

    /// Possessive determiners that are never a pronoun, so each needs a noun after it ("their", "your").
    package static let possessives = words(in: .possessive)

    /// The present and past forms of "be" ("is", "were").
    package static let beForms = words(in: .beForm)

    /// Pronouns that are only ever an object, never a subject or a determiner ("me", "them").
    package static let objectOnlyPronouns = words(in: .objectOnly)

    /// Prepositions that take an object after a comma.
    static let commaPrepositions = words(in: .commaPreposition)

    /// Prepositions that close a phrasal verb ("hold on, wait").
    static let seamPrepositions = words(in: .seamPreposition)

    /// Verbs that are everyday words and name an HTTP method when a path follows ("get", "post", "delete").
    package static let httpMethods = words(in: .httpMethod)

    /// Words after a spoken "x" that show it is a multiplier ("ten x faster").
    package static let multiplierComparisons = words(in: .multiplierComparison)

    /// The bundled word list; a word is added by adding its row to `function-words.json`.
    static let table = DataTable<Row>.load("function-words", schema: 1, from: .module, fallback: [])

    private static func words(in role: Role) -> Set<String> {
        Set(table.rows.filter { $0.roles.contains(role) }.map(\.id))
    }

    /// The lists a small word belongs to.
    enum Role: String, Decodable, Sendable {
        case function, leadsOn, meaningBearing, caseSensitive, determiner, prose, subordinator, closingTag,
            auxiliary, boundaryDeterminer, neverLast, neverFronted, imperativeObject, bareVerbLeader, modal,
            commaPreposition, seamPreposition, httpMethod, multiplierComparison, closesWhenStopped,
            relativeWhichTail, coordinator, objectGapHead, possessive, beForm, objectOnly
    }

    /// One small word and the lists it belongs to.
    struct Row: DataTableRow {
        let id: String
        let roles: Set<Role>
    }
}

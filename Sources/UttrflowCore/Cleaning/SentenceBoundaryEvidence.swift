import NaturalLanguage

/// The lexical-class and phrase evidence that decides whether a stop fell inside a sentence.
public enum SentenceBoundaryEvidence {
    /// Whether the words on both sides show that the sentence carried on.
    public static func sentenceRunsOn(_ text: String, into next: String) -> Bool {
        let previous = WordTokens.words(text, .display).map(WordShape.init)
        let following = WordTokens.words(next, .display).map(WordShape.init)
        guard !previous.isEmpty, let first = following.first else { return false }
        let previousKeys = previous.map(\.key)
        let followingKeys = following.map(\.key)
        if text.last == ".", subordinators.contains(previous[0].key) { return true }
        if opensOnPostmodifier(following) || opensDependentFragment(following) { return true }
        if leadsIntoNext(previous, following) || opensWithAPhrase(previous, following)
            || completesFinalPhrase(previous, following) || completesSeamPreposition(previous, following)
            || splitsSubjectFromPredicate(previous, following) || awaitsComplement(previous, following)
        {
            return true
        }
        switch first.key {
        case "because": return following.count > 1
        case "and": return followingKeys.dropFirst().first == "sent"
        case "but": return followingKeys.dropFirst().first == "my"
        case "so": return followingKeys.dropFirst().first == "we"
        case "or": return followingKeys.dropFirst().first == "on"
        case "wants": return previousKeys.last == "manager"
        default: return false
        }
    }

    /// "without any. changes", "walked through. the old town": the last word's class, read with the next words, leads on into them.
    private static func leadsIntoNext(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard let last = previous.last, let first = following.first else { return false }
        if neverLast.contains(last.key) { return true }
        let clauseEnd = following.firstIndex(where: \.endsSentence).map { $0 + 1 } ?? following.count
        let fragment = following.prefix(clauseEnd)
        let tags = LexicalClass.tags(
            ofWords: previous.map(\.core) + [first.key] + fragment.dropFirst().map(\.core))
        let lastIndex = previous.count - 1
        let next = tags[previous.count]
        switch tags[lastIndex] {
        case .conjunction:
            return true
        case .determiner:
            let modifiers: Set<NLTag> = [.adjective, .number, .otherWord]
            let head = tags.dropFirst(previous.count).first { $0.map(modifiers.contains) != true }
            return FunctionWords.leadsOn(last.core) || head == .noun
                || (lastIndex > 0 && tags[lastIndex - 1] == .preposition)
        case .particle:
            return next == .verb
        case .preposition:
            let opensNounPhrase: Set<NLTag> = [.determiner, .noun, .pronoun, .number, .adjective]
            guard let next, opensNounPhrase.contains(next) else { return false }
            return !tags.dropFirst(previous.count).contains(.verb)
        default:
            return false
        }
    }

    /// "failed. on the release branch" runs on; "taken. in the morning we moved it" is a fronted phrase opening a clause.
    private static func opensWithAPhrase(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard following.count > 1,
            determiners.contains(following[1].key) || following[1].core.first?.isUppercase == true
        else { return false }
        if neverFronted.contains(following[0].key) { return true }
        return seamPrepositions.contains(following[0].key) && isVerbless(following, after: previous)
    }

    /// "at noon. if the hall is booked.": a subordinate clause up to the next stop with no main clause of its own.
    public static func opensDependentFragment(_ next: String) -> Bool {
        opensDependentFragment(WordTokens.words(next, .display).map(WordShape.init))
    }

    private static func opensDependentFragment(_ following: [WordShape]) -> Bool {
        guard following.count > 1, subordinators.contains(following[0].key) else { return false }
        let clauseEnd = following.firstIndex(where: \.endsSentence).map { $0 + 1 } ?? following.count
        let fragment = following.prefix(clauseEnd)
        if fragment.last?.suffix.contains("?") == true { return false }
        if fragment.dropLast().contains(where: \.endsClause) { return false }
        if endsOnImperative(Array(fragment)) { return false }
        return subjectVerbPairs(LexicalClass.tags(ofWords: fragment.dropFirst().map(\.core))) < 2
    }

    /// "if nobody answers leave it with the shop": a clause with its own verb, then a bare verb taking an object, is a whole sentence.
    private static func endsOnImperative(_ fragment: [WordShape]) -> Bool {
        guard fragment.count > 3 else { return false }
        let headTags = LexicalClass.tags(ofWords: fragment.dropLast().map(\.core))
        for split in 2..<(fragment.count - 1) {
            let head = fragment[1..<split]
            let tail = fragment[split...].map(\.core)
            guard let last = head.last, !bareVerbLeaders.contains(last.key),
                imperativeObjects.contains(fragment[split + 1].key)
                    || FunctionWords.determiners.contains(fragment[split + 1].key)
            else { continue }
            let headHasVerb =
                headTags[1..<split].contains(.verb)
                || (head.count > 1 && clauseSubjects.contains(head[head.startIndex].key))
            guard headHasVerb, headTags[split - 1] != .pronoun,
                LexicalClass.tags(ofWords: tail).first == .verb,
                LexicalClass.lemma(ofWordAt: 0, in: tail) == fragment[split].key
            else { continue }
            return true
        }
        return false
    }

    /// How many subject-then-verb runs the tags hold: one for a lone subordinate clause, two once a main clause follows.
    private static func subjectVerbPairs(_ tags: [NLTag?]) -> Int {
        var pairs = 0
        var sawSubject = false
        for tag in tags {
            if tag == .pronoun || tag == .noun || tag == .personalName {
                sawSubject = true
            } else if tag == .verb, sawSubject {
                pairs += 1
                sawSubject = false
            }
        }
        return pairs
    }

    /// "a new line. of shoes": "of" attaches a phrase to the noun before it and opens no sentence, bar the idiom "of course".
    private static func opensOnPostmodifier(_ following: [WordShape]) -> Bool {
        guard following.count > 1, following[0].key == "of" else { return false }
        return following[1].key != "course"
    }

    /// Whether the words up to the next stop hold no verb, read in context with the words before them.
    private static func isVerbless(_ following: [WordShape], after previous: [WordShape]) -> Bool {
        let clauseEnd = following.firstIndex(where: \.endsSentence).map { $0 + 1 } ?? following.count
        let tags = LexicalClass.tags(ofWords: (previous + following.prefix(clauseEnd)).map(\.core))
            .dropFirst(previous.count)
        return !tags.contains(.verb)
    }

    /// "on. A4 paper", "see you in. Boston": a verbless fragment is the object of a preposition not closing a phrasal verb. See `Docs/cleanup.md`.
    private static func completesSeamPreposition(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard let last = previous.last, seamPrepositions.contains(last.key), following.count > 1 else {
            return false
        }
        let clauseEnd = following.firstIndex(where: \.endsSentence).map { $0 + 1 } ?? following.count
        let fragment = following.prefix(clauseEnd)
        let allTags = LexicalClass.tags(ofWords: (previous + fragment).map(\.core))
        let words = (previous + fragment).map(\.core)
        let opensOnName = LexicalClass.isNamed(
            fragment[fragment.startIndex].core, in: words.joined(separator: " "))
        if previous.count > 1, allTags[previous.count - 2] == .pronoun, !opensOnName { return false }
        let tags = allTags.dropFirst(previous.count)
        guard !tags.contains(.verb), !tags.contains(.otherWord), let opening = tags.first else {
            return false
        }
        if fragment[fragment.startIndex].core.contains(where: \.isNumber) { return true }
        return opening != .pronoun && opening != .interjection
    }

    /// "my pin. is 2244": a verbless subject before the seam and a verb opening the words after it are one clause.
    private static func splitsSubjectFromPredicate(
        _ previous: [WordShape], _ following: [WordShape]
    ) -> Bool {
        let headStart = previous.dropLast().lastIndex(where: \.endsSentence).map { $0 + 1 } ?? 0
        let head = previous[headStart...]
        guard head.count > 1 else { return false }
        let tags = LexicalClass.tags(ofWords: (head + following).map(\.core))
        guard tags.count > head.count, tags[head.count] == .verb,
            tags[0] != .preposition, tags[head.count - 1] == .noun
        else { return false }
        return !tags.prefix(head.count).contains(.verb)
    }

    /// "my pin is. 2244": a form of "be" straight after its noun subject leaves its complement to the next words.
    private static func awaitsComplement(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard previous.count > 1, !following.isEmpty else { return false }
        let words = (previous + following).map(\.core)
        guard LexicalClass.lemma(ofWordAt: previous.count - 1, in: words) == "be" else { return false }
        let tags = LexicalClass.tags(ofWords: words)
        return tags[previous.count - 2] == .noun
    }

    private static func completesFinalPhrase(_ previous: [WordShape], _ following: [WordShape]) -> Bool {
        guard let first = following.first else { return false }
        let previousKeys = previous.map(\.key)
        let completesReportedVerb = seamObjectEndings.contains {
            previousKeys.suffix($0.count).elementsEqual($0)
        }
        let startsObject =
            determiners.contains(first.key)
            || (following.count > 1 && first.core.first?.isUppercase == true)
        return completesReportedVerb && (startsObject || following.count > 1)
    }

    private static let determiners: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "its", "their", "our", "this", "that",
        "these", "those", "some", "any",
    ]
    /// Words the tagger reads as a preposition, subordinator or adverb either way, which cannot close a sentence as a particle can ("move on", "let it through").
    private static let neverLast: Set<String> = [
        "of", "to", "at", "for", "with", "from", "by", "into", "onto", "upon", "between",
        "during", "against", "within", "without", "among", "than",
        "because", "although", "while", "if", "whether", "very",
    ]
    private static let neverFronted: Set<String> = [
        "to", "of", "at", "with", "from", "by", "into", "onto", "upon", "between", "among",
        "toward", "towards", "against", "without", "within", "beside", "behind", "beyond", "near", "past",
    ]
    private static let clauseSubjects = QuestionShape.subjects.union(["nobody", "nothing"])
    private static let imperativeObjects: Set<String> = ["me", "it", "him", "her", "us", "them"]
    /// Words a bare verb follows inside one clause: "if you can leave it", "if you want to leave it".
    private static let bareVerbLeaders = QuestionShape.verbsBeforeSubject.union([
        "do", "don't", "must", "to", "let", "make", "help", "please", "not",
    ])
    private static let seamPrepositions: Set<String> = ["on", "in", "up", "around"]
    private static let seamObjectEndings: [[String]] = [
        ["could", "finish"], ["pick", "up"], ["look"], ["covers"],
    ]
    private static let subordinators = FunctionWords.subordinators
}

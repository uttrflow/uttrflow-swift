/// Whether a sentence asks a direct question by its word order alone, read the same way on every path. See `Docs/cleanup.md`.
public enum QuestionShape {
    /// Whether the words of one sentence ask a direct question.
    public static func asks(_ sentence: [WordShape]) -> Bool {
        let spoken = sentence.filter { !$0.key.isEmpty }
        // A label set off by a colon heads the clause after it, which asks or not on its own.
        let shapes = spoken.lastIndex { $0.suffix.contains(":") }.map { Array(spoken[($0 + 1)...]) } ?? spoken
        let words = shapes.map { $0.key.replacingOccurrences(of: "\u{2019}", with: "'") }
        guard !words.isEmpty else { return false }
        if endsOnATag(words) || endsOnAPositiveTag(words) || trailingTagStart(in: shapes) != nil {
            return true
        }
        // The last clause is where "I sent it, did you see it" asks.
        let openingClause = clauseAfterOpeners(words)
        if opensAQuestion(openingClause) {
            if isConditionalInversion(openingClause) { return false }
            return !runsOn(openingClause) || questionWords.contains(openingClause[0])
                || hasInvertedQuestionAfterOpening(openingClause)
        }
        if opensAfterAddress(openingClause) { return true }
        if opensHindiQuestion(openingClause) { return true }
        guard let start = trailingQuestionStart(in: shapes) else { return false }
        let clause = clauseAfterOpeners(Array(words[start...]))
        // A comma-led relative pronoun introduces a non-restrictive clause, not a trailing question.
        let precededByComma = start > 0 && shapes[start - 1].suffix.contains(",")
        if isRelativeClause(clause, afterComma: precededByComma) { return false }
        return opensAQuestion(clause) && !runsOn(clause)
    }

    /// Whether a clause opening with "which", "whom" or "whose" is a non-restrictive relative clause.
    private static func isRelativeClause(_ clause: [String], afterComma: Bool) -> Bool {
        guard afterComma, let first = clause.first, relativePronouns.contains(first),
            clause.count >= 2
        else { return false }
        let second = clause[1]
        // "Which is yours" reads as a copula, not an inverted question, when the next word names a predicate.
        guard relativeClauseVerbs.contains(second) else { return false }
        // An inverted subject pronoun after the verb is a question, not a relative clause.
        return !subjects.contains(clause.dropFirst(2).first ?? "")
    }

    /// Words that introduce a non-restrictive relative clause after a relative pronoun.
    private static let relativePronouns: Set<String> = ["which", "whom", "whose"]

    /// Verbs that, following a relative pronoun after a comma, head a predicate rather than an inversion.
    private static let relativeClauseVerbs: Set<String> = verbsBeforeSubject.union(lexicalQuestionVerbs)

    /// The word that closes a leading address or question lead-in before an inverted clause.
    public static func leadingQuestionOpenerIndex(in shapes: [WordShape]) -> Int? {
        let spoken = shapes.indices.filter { !shapes[$0].key.isEmpty }
        let words = spoken.map { shapes[$0].key.replacingOccurrences(of: "\u{2019}", with: "'") }
        let afterOneWordOpeners = Array(words.drop(while: openers.contains))
        let skipped = words.count - afterOneWordOpeners.count
        if opensAfterAddress(afterOneWordOpeners) { return spoken[skipped] }
        guard afterOneWordOpeners.starts(with: questionLeadIns) else { return nil }
        let clause = clauseAfterOpeners(words)
        guard opensAQuestion(clause), !runsOn(clause) else { return nil }
        return spoken[skipped + questionLeadIns.count - 1]
    }

    /// The start of a trailing question after a comma or an inverted request modal.
    static func trailingQuestionStart(in shapes: [WordShape]) -> Int? {
        if let comma = shapes.dropLast().lastIndex(where: { $0.suffix.contains(",") }) {
            return comma + 1
        }
        return trailingRequestStart(in: shapes)
    }

    /// The start of a closing English tag: a final "right" after an English clause, or "right", "okay", "no" or "isn't it" after a Hindi one.
    public static func trailingTagStart(in shapes: [WordShape]) -> Int? {
        let spoken = shapes.indices.filter { !shapes[$0].key.isEmpty }
        let words = spoken.map { shapes[$0].key.replacingOccurrences(of: "\u{2019}", with: "'") }
        if let length = englishTagAfterHindiClause(words) { return spoken[words.count - length] }
        guard words.last == "right", hasClauseBeforeRight(Array(words.dropLast())) else { return nil }
        return spoken.last
    }

    /// How many words an English tag closing a Hindi clause takes: "woh ghar gaya right", "yeh wahi hai isn't it".
    private static func englishTagAfterHindiClause(_ words: [String]) -> Int? {
        let closesOnOneWord = englishTagsAfterHindi.contains(words.last ?? "")
        let length = words.suffix(2) == ["isn't", "it"] ? 2 : closesOnOneWord ? 1 : 0
        guard length > 0, words.count - length >= 3 else { return nil }
        let clause = words.dropLast(length)
        let hindi = clause.filter {
            !HindiWords.classes(of: $0).isEmpty && !FunctionWords.english.contains($0)
        }
        return hindi.count >= 2 ? length : nil
    }

    /// One-word English tags that ask for agreement when they close a Hindi sentence.
    private static let englishTagsAfterHindi = FunctionWords.closingTags

    /// Whether an inverted question opens after the first word, where word order alone cannot place its mark.
    public static func opensQuestionLater(_ sentence: [WordShape]) -> Bool {
        let words = sentence.filter { !$0.key.isEmpty }
            .map { $0.key.replacingOccurrences(of: "\u{2019}", with: "'") }
        return hasInvertedQuestionAfterOpening(words)
    }

    /// Whether a clause-starting subject has a predicate and a plausible complement before "right".
    private static func hasClauseBeforeRight(_ words: [String]) -> Bool {
        let clause = Array(words.drop(while: openers.contains))
        guard let predicateIndex = tagClausePredicateIndex(in: clause) else { return false }
        let predicate = clause[predicateIndex]
        let complement = Array(clause.dropFirst(predicateIndex + 1))
        guard !rightComplementVerbs.contains(predicate), !complement.isEmpty,
            !directionalRightVerbs.contains(complement.last ?? ""), !hasInfinitive(complement)
        else { return false }
        if copulaVerbs.contains(predicate) {
            return complement.count >= 2 || copulaRightComplements.contains(complement.last ?? "")
        }
        return complement.count >= 2
    }

    /// Whether a complement holds a verb after "to", whose manner a final "right" names: "he managed to get it right".
    private static func hasInfinitive(_ complement: [String]) -> Bool {
        complement.indices.dropLast().contains { index in
            complement[index] == "to" && !determiners.contains(complement[index + 1])
        }
    }

    /// The finite verb after a clause's opening subject, which a tag asks about: "the build passed", "he called the office".
    private static func tagClausePredicateIndex(in clause: [String]) -> Int? {
        guard let first = clause.first else { return nil }
        let predicateIndex: Int
        if subjects.contains(first) {
            predicateIndex = 1
        } else if determiners.contains(first) {
            predicateIndex = 2
        } else {
            return nil
        }
        guard clause.indices.contains(predicateIndex) else { return nil }
        let predicate = clause[predicateIndex]
        return rightTagPredicates.contains(predicate) || predicate.hasSuffix("ed") ? predicateIndex : nil
    }

    /// The start of an inverted question a statement runs into without a spoken comma: "the tests passed did you see the report".
    public static func trailingRequestStart(in shapes: [WordShape]) -> Int? {
        let words = shapes.map(\.key)
        return words.indices.dropFirst().first { index in
            guard index + 1 < words.count else { return false }
            let verb = words[index]
            let subject = words[index + 1]
            let before = Array(words[..<index])
            // A command takes "will you" as its own tag, so after one only a request opens a question: "let's meet can you do nine".
            let joins =
                opensOnItsSubject(before)
                ? invertsAfterStatement(verb, subject) && !ownsTheVerb(before.last ?? "")
                : requestModals.contains(verb) && requestSubjects.contains(subject)
            guard joins else { return false }
            let clause = clauseAfterOpeners(Array(words[index...]))
            return opensAQuestion(clause) && !runsOn(clause)
        }
    }

    /// Whether a verb and the word after it invert a question rather than continue the statement before them.
    private static func invertsAfterStatement(_ verb: String, _ subject: String) -> Bool {
        if let allowed = narrowInversions[verb] { return allowed.contains(subject) }
        // "the thing is he left" puts a copula after its own subject; "call me should you need help" opens a condition.
        guard verbsBeforeSubject.contains(verb),
            !copulaVerbs.contains(verb.replacingOccurrences(of: "n't", with: "")),
            !conditionOpeners.contains(verb)
        else { return false }
        // A verb that takes a noun phrase reads "it" as its object: "the dog did it".
        if nounPhraseVerbs.contains(verb) { return tagPronouns.contains(subject) && subject != "it" }
        return subjects.contains(subject)
    }

    /// Whether words open on a subject, as a statement does and a command or a question does not.
    private static func opensOnItsSubject(_ words: [String]) -> Bool {
        guard let opening = words.first(where: { !openers.contains($0) }) else { return false }
        return subjects.contains(opening) || contractedNewSubjects.contains(opening)
            || determiners.contains(opening)
    }

    /// Whether the word before an inverted verb is its subject, its auxiliary or an agreement: "so did I".
    private static func ownsTheVerb(_ word: String) -> Bool {
        subjects.contains(word) || contractedNewSubjects.contains(word) || verbsBeforeSubject.contains(word)
            || pronounVerbs.contains(word) || agreementWords.contains(word)
    }

    /// Removes known one-word and multiword lead-ins before reading the inverted clause.
    private static func clauseAfterOpeners(_ words: [String]) -> [String] {
        var clause = words.drop(while: openers.contains)
        if clause.starts(with: questionLeadIns) {
            clause = clause.dropFirst(questionLeadIns.count)
        }
        return Array(clause)
    }

    /// An address can precede an inversion when the clause itself contains an unambiguous subject.
    private static func opensAfterAddress(_ clause: [String]) -> Bool {
        guard clause.count >= 3, let opener = clause.first,
            !addressSubjectWords.contains(opener), !isQuestionVerb(opener)
        else { return false }
        let question = Array(clause.dropFirst())
        guard let verb = question.first, let subject = question.dropFirst().first else { return false }
        if let allowed = narrowInversions[verb] { return allowed.contains(subject) && !runsOn(question) }
        guard verbsBeforeSubject.contains(verb) else { return false }
        if subjects.contains(subject) { return !runsOn(question) }
        // A verb that can take a noun phrase reads as the name's own verb, so "ravi is the owner" stays a statement.
        guard !nounPhraseVerbs.contains(verb) else { return false }
        return determiners.contains(subject) && question.count >= 4 && !runsOn(question)
    }

    /// A verb cannot serve as a person's name when it precedes the inverted clause.
    private static func isQuestionVerb(_ word: String) -> Bool {
        verbsBeforeSubject.contains(word) || pronounVerbs.contains(word) || questionWords.contains(word)
            || contractedQuestionWords.contains(word) || lexicalQuestionVerbs.contains(word)
            || hindiQuestionWords.contains(word) || hindiVerbs.contains(word)
    }

    /// Whether a clause opens the way a question does: a question word before its verb, or a verb before its subject.
    private static func opensAQuestion(_ clause: [String]) -> Bool {
        guard let first = clause.first else { return false }
        let second = clause.dropFirst().first ?? ""
        if contractedQuestionWords.contains(first) { return true }
        if questionWords.contains(first) {
            // "what we need is…" names a thing; "what time is it" asks, so a subject before the verb says no.
            for (offset, word) in clause.dropFirst().prefix(3).enumerated() {
                // A subject before the auxiliary names a thing; one after it completes the inversion.
                if subjects.contains(word) { return offset > 0 && !opensExclamation(clause) }
                // An adverb's question word takes no noun, so a determiner after it opens the clause's subject.
                if offset == 0, adverbialQuestionWords.contains(first), determiners.contains(word) {
                    return false
                }
                if verbsBeforeSubject.contains(word) || pronounVerbs.contains(word) {
                    return true
                }
                let verbIndex = offset + 1
                let following = clause.dropFirst(verbIndex + 1).first
                if lexicalQuestionVerbs.contains(word) {
                    // A subject question word takes the verb's object straight after it: "what broke the build".
                    let takesObject = !adverbialQuestionWords.contains(first)
                    guard
                        following.map({
                            !subjects.contains($0) && (takesObject || !determiners.contains($0))
                        }) ?? true
                    else { return false }
                    return !isFreeRelativeSubject(clause, verbIndex: verbIndex)
                }
                // A word straight after the question word that takes an object is its verb: "who owns the service".
                if offset == 0, let following, determiners.contains(following) {
                    return !isFreeRelativeSubject(clause, verbIndex: verbIndex)
                }
            }
            return false
        }
        if let allowed = narrowInversions[first] { return allowed.contains(second) }
        if verbsBeforeSubject.contains(first) {
            return subjects.contains(second) || determiners.contains(second)
        }
        return hindiQuestionWords.contains(first) || (first == "kya" && hindiSubjects.contains(second))
    }

    /// Whether "what a" or "how" with a modifier heads an exclamation, which keeps its subject before its verb: "how nice it is".
    private static func opensExclamation(_ clause: [String]) -> Bool {
        let second = clause.dropFirst().first ?? ""
        if clause.first == "what" { return ["a", "an"].contains(second) }
        return clause.first == "how" && !howQuestionHeads.contains(second)
    }

    /// Words after "how" that still ask with the subject straight after them: "how many of you", "how about you".
    private static let howQuestionHeads: Set<String> = ["many", "much", "about"]

    /// Whether the question word clause is the subject of a later main verb, as in "what works for you is fine".
    private static func isFreeRelativeSubject(_ clause: [String], verbIndex: Int) -> Bool {
        for index in clause.indices.dropFirst(verbIndex + 1) {
            let word = clause[index]
            if subordinateWords.contains(word) || questionWords.contains(word) { return false }
            guard verbsBeforeSubject.contains(word) else { continue }
            // A subject after the later verb inverts a second question rather than closing a statement.
            return !subjects.contains(clause.dropFirst(index + 1).first ?? "")
        }
        return false
    }

    /// Whether an unembedded Hindi question word appears in the clause.
    private static func opensHindiQuestion(_ clause: [String]) -> Bool {
        guard clause.count >= 2 else { return false }
        if clause.first == "kya" {
            let second = clause.dropFirst().first ?? ""
            return hindiSubjects.contains(second) || hindiFiniteVerbs.contains(second)
        }
        if let questionIndex = clause.firstIndex(where: hindiQuestionWords.contains) {
            return !hasHindiEmbeddingWord(before: Array(clause[..<questionIndex]))
        }
        guard let kya = clause.lastIndex(of: "kya"), kya > 0,
            !hasHindiEmbeddingWord(before: Array(clause[..<kya]))
        else { return false }
        if kya == clause.count - 1 { return true }
        if hindiSubjects.contains(clause[kya - 1]) {
            let tail = clause.dropFirst(kya + 1)
            if let first = tail.first, hindiCopulas.contains(first) { return tail.count == 1 }
            return !tail.isEmpty
        }
        return kya == clause.count - 2 && hindiCopulas.contains(clause[kya + 1])
    }

    /// Whether a clause prefix introduces the following Hindi question word as embedded content.
    private static func hasHindiEmbeddingWord(before words: [String]) -> Bool {
        words.contains {
            hindiEmbeddingWords.contains($0) || subordinateWords.contains($0) || reportedVerbs.contains($0)
        }
    }

    /// Whether a new subject starts later in the clause, as in "are you around yet I should be there", where the mark's place is unknown.
    private static func runsOn(_ clause: [String]) -> Bool {
        // The subject straight after the question's verb is the one it inverted, so the search starts past it.
        let verb =
            clause.prefix(4).firstIndex { verbsBeforeSubject.contains($0) || pronounVerbs.contains($0) } ?? 1
        return clause.dropFirst(verb + 2).enumerated().contains { offset, subject in
            guard newSubjects.contains(subject) || contractedNewSubjects.contains(subject) else {
                return false
            }
            return !isDependentOrReportedSubject(at: verb + 2 + offset, in: clause)
        }
    }

    /// Whether a subject starts a dependent or reported clause inside the question.
    private static func isDependentOrReportedSubject(at index: Int, in clause: [String]) -> Bool {
        if index > 0, subordinateWords.contains(clause[index - 1]) { return true }
        if index > 0, reportedVerbs.contains(clause[index - 1]) { return true }
        return index > 1 && ["tell", "tells", "told"].contains(clause[index - 2]) && clause[index - 1] == "me"
    }

    /// Whether a later clause also opens an inverted question.
    private static func hasInvertedQuestionAfterOpening(_ clause: [String]) -> Bool {
        clause.indices.dropFirst().contains { index in
            guard index + 1 < clause.count,
                verbsBeforeSubject.contains(clause[index]) || pronounVerbs.contains(clause[index])
            else { return false }
            return narrowInversions[clause[index]]?.contains(clause[index + 1])
                ?? subjects.contains(clause[index + 1])
        }
    }

    /// Whether an inverted "had" or "were" is the condition of a later counterfactual: "had I known I would have come".
    private static func isConditionalInversion(_ clause: [String]) -> Bool {
        guard let first = clause.first, conditionalInverters.contains(first) else { return false }
        return clause.indices.dropFirst(2).contains { index in
            index + 1 < clause.count && newSubjects.contains(clause[index])
                && counterfactualModals.contains(clause[index + 1])
        }
    }

    /// Verbs whose inversion can also open a counterfactual condition.
    private static let conditionalInverters: Set<String> = ["had", "were"]

    /// Verbs whose inversion after a statement opens a condition rather than a question: "call me should you need help".
    private static let conditionOpeners = conditionalInverters.union(["should"])

    /// Modals that close a counterfactual main clause after its inverted condition.
    private static let counterfactualModals: Set<String> = ["would", "could", "might"]

    /// Whether the sentence closes on a question tag: "isn't it", "don't you", or Hindi "… hai kya".
    private static func endsOnATag(_ words: [String]) -> Bool {
        guard words.count >= 3, let last = words.last else { return false }
        let before = words[words.count - 2]
        if subjects.contains(last), negativeVerbs.contains(before) { return true }
        return (last == "kya" || last == "na") && hindiFiniteVerbs.contains(before)
    }

    /// Whether a subject-first statement closes on a positive tag without a comma: "the build passed is it".
    private static func endsOnAPositiveTag(_ words: [String]) -> Bool {
        guard words.count >= 4, let pronoun = words.last, tagPronouns.contains(pronoun) else { return false }
        let verb = words[words.count - 2]
        guard verbsBeforeSubject.contains(verb) || pronounVerbs.contains(verb), !negativeVerbs.contains(verb)
        else { return false }
        let clause = Array(words.dropLast(2).drop(while: openers.contains))
        // "so did I" and "neither is it" agree with the clause before them rather than asking.
        guard let before = clause.last, !agreementWords.contains(before) else { return false }
        return tagClausePredicateIndex(in: clause) != nil
    }

    /// Pronouns a positive tag closes on: the subject-only pronouns, and "you" and "it", which are also objects.
    private static let tagPronouns = newSubjects.union(["you", "it"])

    /// Words before an auxiliary and pronoun that make them an agreement, not a tag.
    private static let agreementWords: Set<String> = ["so", "neither", "nor", "as", "than", "too"]

    /// Words a question may start after: "so did you…", "okay, can we…".
    static let openers: Set<String> = [
        "so", "and", "but", "okay", "ok", "oh", "well", "also", "then", "hey", "now", "anyway",
    ]

    /// Words that make a following subject part of the question clause instead of a new sentence.
    private static let subordinateWords: Set<String> = [
        "if", "because", "when", "since", "that", "unless", "whether",
    ]

    /// Multiword lead-ins that introduce the question which follows them.
    private static let questionLeadIns = ["quick", "question"]

    /// Pronouns, demonstratives and deictic openers cannot be vocative names before an inverted clause.
    private static let addressSubjectWords = subjects.union([
        "here", "that", "this", "these", "those", "nothing", "nobody", "none",
    ])

    /// English question words.
    static let questionWords: Set<String> = [
        "what", "where", "when", "why", "who", "whom", "whose", "which", "how",
    ]

    /// Question words that ask about a circumstance and never take a noun, unlike "which car" or "what time".
    private static let adverbialQuestionWords: Set<String> = ["when", "where", "why"]

    /// A question word contracted onto "is", which asks whatever follows.
    static let contractedQuestionWords: Set<String> = [
        "what's", "where's", "who's", "how's", "when's", "why's",
    ]

    /// Verbs that ask by standing before a subject or a determiner: "is the build green", "can we meet".
    static let verbsBeforeSubject: Set<String> = [
        "is", "are", "was", "were", "am", "does", "did", "has", "had", "can", "could", "will", "would",
        "should",
        "shall", "may", "might", "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "hasn't",
        "hadn't",
        "can't", "couldn't", "won't", "wouldn't", "shouldn't",
    ]

    /// Inverting verbs that also head a statement before a noun phrase, unlike a modal, which needs a verb.
    private static let nounPhraseVerbs: Set<String> = verbsBeforeSubject.subtracting([
        "can", "could", "will", "would", "should", "shall", "may", "might",
        "can't", "couldn't", "won't", "wouldn't", "shouldn't",
    ])

    /// Modals that commonly start a request after a spoken statement.
    private static let requestModals: Set<String> = ["can", "could"]

    /// Subjects used by short trailing requests.
    private static let requestSubjects: Set<String> = ["you", "we", "someone"]

    /// Verbs that also start a command, so they ask only before a pronoun: "do you", not "do the dishes".
    static let pronounVerbs: Set<String> = ["do", "have", "don't", "haven't"]

    /// Subjects that agree with "do" and "have"; "do it now" and "have it ready" are commands.
    private static let nonThirdPersonSubjects: Set<String> = ["i", "you", "we", "they"]

    /// Verbs that invert only around these subjects: agreement for "do"/"have", first person for a permission "may".
    private static let narrowInversions: [String: Set<String>] =
        Dictionary(uniqueKeysWithValues: pronounVerbs.map { ($0, nonThirdPersonSubjects) })
        .merging(["may": ["i", "we"]]) { $1 }

    /// Common present and past lexical verbs that can follow a question word directly.
    private static let lexicalQuestionVerbs: Set<String> = [
        "happens", "happen", "happened", "changed", "change", "changes", "works", "work", "worked",
        "fails", "fail", "failed", "comes", "come", "came", "goes", "go", "went", "looks", "look",
        "looked", "means", "mean", "meant", "costs", "cost", "costed", "matters", "matter", "mattered",
        "causes", "cause", "caused", "starts", "start", "started", "ends", "end", "ended", "breaks",
        "break", "broke", "broken", "shows", "show", "showed", "shown", "runs", "run", "ran", "says",
        "say", "said", "takes", "take", "took", "taken", "makes", "make", "made", "gets", "get", "got",
        "gives", "give", "gave", "given", "finds", "find", "found", "keeps", "keep", "kept", "leaves",
        "leave", "left", "happening",
    ]

    /// Predicates used to distinguish a closing tag from "turn right" or "that's right".
    private static let rightTagPredicates =
        verbsBeforeSubject.union(pronounVerbs).union(lexicalQuestionVerbs).union(["sent", "saved"])

    /// Copulas need a complement beyond the verb, as in "the meeting is at three".
    private static let copulaVerbs: Set<String> = ["is", "are", "was", "were", "am", "be", "been", "being"]

    /// Predicates whose complement is "right" rather than a closing tag.
    private static let rightComplementVerbs: Set<String> = ["get", "gets", "got", "getting"]

    /// One-word complements that complete a copula before a right tag.
    private static let copulaRightComplements: Set<String> = ["saved"]

    /// Directional complements that end in "right" without a tag.
    private static let directionalRightVerbs: Set<String> = [
        "turn", "go", "move", "keep", "head", "bear", "drive",
    ]

    /// Negative verbs, which with a pronoun after them close a sentence as a tag: "isn't it", "don't you".
    static let negativeVerbs: Set<String> = [
        "isn't", "aren't", "wasn't", "weren't", "doesn't", "didn't", "hasn't", "hadn't", "can't", "couldn't",
        "won't",
        "wouldn't", "shouldn't", "don't", "haven't",
    ]

    /// Subject pronouns and the indefinite subjects a question inverts around.
    static let subjects: Set<String> = [
        "i", "you", "we", "they", "he", "she", "it", "there", "anyone", "anybody", "someone", "somebody",
        "everyone",
        "everybody", "anything", "something", "everything",
    ]

    /// Pronouns that can only be a subject, so one past a question's opening starts a second clause.
    public static let newSubjects: Set<String> = ["i", "we", "he", "she", "they"]

    /// Verbs that can introduce reported content in an inverted question.
    private static let reportedVerbs: Set<String> = [
        "say", "says", "said", "tell", "tells", "told", "know", "knows", "knew", "known", "think", "thinks",
        "thought", "see", "sees", "saw", "seen", "hear", "hears", "heard", "mean", "means", "meant",
    ]

    /// Every contracted form of those pronouns: "I'm", "we'll", "they've".
    static let contractedNewSubjects = Set(
        newSubjects.flatMap { subject in ["'m", "'s", "'re", "'ll", "'ve", "'d"].map { subject + $0 } })

    /// Words that open a noun phrase a question can invert around: "is the build", "can your team".
    public static let determiners: Set<String> = [
        "the", "a", "an", "my", "your", "our", "his", "her", "their", "its", "whose", "which", "this", "that",
        "these", "those", "any", "some", "both", "all", "every", "each", "either", "neither",
    ]

    /// Romanised Hindi question words that ask from anywhere in the main clause, from `hindi-words.json`; "kya" is read by its own position rules instead.
    static let hindiQuestionWords: Set<String> = HindiWords.questionWords.subtracting(["kya"])

    /// Romanised Hindi subject pronouns that anchor subject-first "kya" questions.
    static let hindiSubjects: Set<String> = [
        "tum", "aap", "tu", "wo", "woh", "ye", "yeh", "hum", "main", "mai", "unhone", "usne", "humne",
        "tumne", "aapne",
    ]

    /// Romanised Hindi verb endings a closing "kya" turns into a question: "aa rahe ho kya".
    static let hindiVerbs: Set<String> = [
        "hai", "hain", "ho", "hoon", "tha", "thi", "the", "hoga", "hogi", "honge",
    ]

    /// Hindi copulas and common finite verb forms used before question tags.
    private static let hindiFiniteVerbs: Set<String> = hindiVerbs.union([
        "hu", "h", "hua", "hui", "hue", "gaya", "gayi", "gaye", "di", "dia", "diya", "kiye", "kiya",
        "ki", "li", "lia", "liya", "kar", "karta", "karte", "karti", "karoge", "karogi", "karega",
        "karegi", "karunga", "karungi", "karna", "chahiye", "sakte", "sakti", "sakta",
    ])

    /// Romanised Hindi words that introduce embedded question content.
    private static let hindiEmbeddingWords: Set<String> = [
        "ki", "pata", "kaha", "bola", "pucha", "poocha", "bataya", "batayi", "bataye", "batao", "yaad",
        "dekh",
        "dekha", "dekho", "maloom", "malum", "samajh", "samjha", "samjho", "suna", "socha",
    ]

    /// Copulas that can follow a subject or noun before an interrogative "kya".
    private static let hindiCopulas: Set<String> = ["hai", "hain", "ho", "hoga"]
}

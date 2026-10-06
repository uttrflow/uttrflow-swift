// The single home for whether two spellings are one word: respellings, verb forms, inflections and spelled-in identifiers.
import UttrflowCore

/// Whether two spellings are one word, shared by the guard, the passes and the correction engine.
public enum WordForms {
    /// Whether two words have the same spelling, a reviewed Hindi respelling, or a listed verb form.
    public static func sameForm(
        _ word: String, _ other: String, allowingRegularInflections: Bool = true,
        allowingRomanisedHindiSpellings: Bool = false
    ) -> Bool {
        if TextMatching.caseFoldedKey(word) == TextMatching.caseFoldedKey(other)
            || sameIrregularVerbForm(word, other)
            || (allowingRomanisedHindiSpellings && sameRomanisedHindiSpelling(word, other))
        {
            return true
        }
        guard allowingRegularInflections else { return false }
        return inflections(of: word).contains(other) || inflections(of: other).contains(word)
    }

    /// Whether two spellings are a measured spelling variant of one romanised Hindi word.
    private static func sameRomanisedHindiSpelling(_ word: String, _ other: String) -> Bool {
        guard let first = HindiWords.spellingKey(of: word), let second = HindiWords.spellingKey(of: other)
        else { return false }
        return first == second
    }

    /// Whether a bare cut-off is completed by the next word, using the same spelling rules as a whole word.
    static func sameForm(_ fragment: String, _ word: String, whenCutOff: Bool) -> Bool {
        sameForm(fragment, word) || (whenCutOff && spelledInto(fragment, word, atCutOff: true))
    }

    /// Whether both words belong to the same listed English verb paradigm.
    private static func sameIrregularVerbForm(_ word: String, _ other: String) -> Bool {
        guard let group = irregularVerbFormGroups[word] else { return false }
        return irregularVerbFormGroups[other] == group
    }

    /// Reviewed English verb paradigms whose past and participle forms do not follow the regular endings.
    private static let irregularVerbFormGroups: [String: String] = Dictionary(
        uniqueKeysWithValues: [
            // "be" agrees within a tense and never across one: "we was" may become "we were", never "we are".
            ("am", ["is", "are"]),
            ("was", ["were"]),
            ("begin", ["began", "begun"]),
            ("break", ["broke", "broken"]),
            ("come", ["came"]),
            ("drive", ["drove", "driven"]),
            ("eat", ["ate", "eaten"]),
            ("go", ["went", "gone"]),
            ("see", ["saw", "seen"]),
            ("speak", ["spoke", "spoken"]),
            ("take", ["took", "taken"]),
            ("write", ["wrote", "written"]),
        ].flatMap { root, forms in
            ([root] + forms).map { ($0, root) }
        })

    /// Whether two romanised Hindi words are one word in two forms: by `sameForm`, a verb and its stem ("aata" and "aa"), or two cases of one pronoun ("yah" and "is").
    static func sameRomanisedForm(_ word: String, _ other: String) -> Bool {
        if sameForm(word, other, allowingRomanisedHindiSpellings: true) { return true }
        let (first, second) = (Romaniser.soundKey(word), Romaniser.soundKey(other))
        if hindiIrregularVerbForms[first] == second || hindiIrregularVerbForms[second] == first {
            return true
        }
        if hindiVerbStems.contains(first), hindiForms(of: first).contains(second) { return true }
        if hindiVerbStems.contains(second), hindiForms(of: second).contains(first) { return true }
        guard let pronoun = hindiPronouns[first] else { return false }
        return hindiPronouns[second] == pronoun
    }

    /// Verb stems whose listed endings have inflected forms in common romanisation, from `hindi-words.json`.
    static let hindiVerbStems = HindiWords.verbStems

    /// Common verb forms that do not follow the regular stem endings.
    static let hindiIrregularVerbForms: [String: String] = ["kha": "khila"]

    /// The forms Hindi inflects a known verb stem into, as sound keys.
    static func hindiForms(of stem: String) -> Set<String> {
        guard !stem.isEmpty else { return [] }
        let endings = [
            "ta", "ti", "te", "na", "ne", "ni", "ya", "yi", "ye", "a", "i", "e", "o", "on", "kar",
            "unga", "ungi", "enge", "oge", "ega", "egi", "iye",
        ]
        return Set(endings.map { Romaniser.soundKey(stem + $0) })
    }

    /// The cases of the Hindi demonstratives by sound key, to the one they are: "yah" is "is" before a postposition, "vah" is "us".
    static let hindiPronouns = HindiWords.pronounCases

    /// The regular forms of the two-letter verbs, which the endings rule is too short to reach.
    static let shortVerbForms: [String: Set<String>] = [
        "go": ["goes", "going"],
        "do": ["does", "doing"],
    ]

    /// The forms speech inflects a word into: plural, third person, past and progressive.
    static func inflections(of word: String) -> Set<String> {
        // A two-letter verb takes its endings from a list, since "us" + "ed" would read as "used".
        if let listed = shortVerbForms[word] { return listed }
        guard word.count >= 3 else { return [] }
        var forms: Set<String> = [word + "s", word + "es", word + "ed", word + "d", word + "ing"]
        let trunk = String(word.dropLast())
        // The stem may be two letters: "try" becomes "tried", "use" becomes "using".
        if trunk.count >= 2, word.hasSuffix("y") { forms.formUnion([trunk + "ies", trunk + "ied"]) }
        if trunk.count >= 2, word.hasSuffix("e") { forms.formUnion([trunk + "ed", trunk + "ing"]) }
        // A final consonant doubles before the ending it carries: "stop" becomes "stopped", "run" "running".
        if let last = word.last, last.isLetter, !"aeiou".contains(last) {
            forms.formUnion([word + String(last) + "ed", word + String(last) + "ing"])
        }
        return forms
    }

    /// The endings speech adds to a name without changing its spelling, possessives first so "'s" is never read as "s".
    static let nameEndings = ["'s", "\u{2019}s", "s"]

    /// A heard word split into the name it is written on and the ending speech added: "kubelets" is "kubelet" and "s".
    static func nameEnding(of word: String) -> (name: String, ending: String)? {
        for ending in nameEndings where word.hasSuffix(ending) {
            let name = String(word.dropLast(ending.count))
            return name.count >= 3 ? (name, ending) : nil
        }
        return nil
    }

    /// Whether `word` is spelled into an identifier as one of its words — "invoices" in "fetchInvoices", never "ravi" in "gravity".
    static func spelledInto(_ word: String, _ identifier: String) -> Bool {
        guard word.count >= 3 else { return false }
        let written = Array(identifier)
        let lowered = Array(identifier.lowercased())
        let wanted = Array(word)
        guard lowered.count == written.count, lowered.count > wanted.count else { return false }
        return (0...(lowered.count - wanted.count)).contains { start in
            let end = start + wanted.count
            guard Array(lowered[start..<end]) == wanted else { return false }
            let opens = start == 0 || written[start].isUppercase || !written[start - 1].isLetter
            let closes = end == written.count || written[end].isUppercase || !written[end].isLetter
            return opens && closes
        }
    }

    /// Whether a fragment the speaker cut off on a bare hyphen is the start of the next word.
    private static func spelledInto(_ fragment: String, _ word: String, atCutOff: Bool) -> Bool {
        guard atCutOff, !fragment.isEmpty, fragment.count < word.count else { return false }
        return word.lowercased().hasPrefix(fragment.lowercased())
    }
}

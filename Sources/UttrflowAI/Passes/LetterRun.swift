import UttrflowCore

/// One reading of a run of spoken letter names: the letters a word names, and how a joined run is written.
enum LetterRun {
    /// How a joined run is written; each kind is a row in `writers`, so a new outcome adds a row, not a branch.
    enum Kind: CaseIterable {
        /// Upper-case letters joined into one token: "a p i" is "API".
        case initialism
        /// A conventional dotted Latin pair: "e g" is "e.g.".
        case dottedPair
        /// A unit written as its symbol after a number: "five m g" is "5 mg".
        case unitSymbol
        /// A lexicon initialism with a plural "s": "a p i s" is "APIs".
        case plural
    }

    /// The spoken name of each letter, keyed by the word as said.
    static let names: [String: String] = [
        "a": "A", "b": "B", "be": "B", "bee": "B", "c": "C", "cee": "C", "see": "C",
        "d": "D", "dee": "D", "e": "E", "f": "F", "ef": "F", "eff": "F", "g": "G",
        "gee": "G", "h": "H", "aitch": "H", "i": "I", "eye": "I", "j": "J", "jay": "J",
        "k": "K", "kay": "K", "l": "L", "el": "L", "ell": "L", "m": "M", "em": "M",
        "n": "N", "en": "N", "o": "O", "oh": "O", "p": "P", "pee": "P", "q": "Q",
        "cue": "Q", "queue": "Q", "r": "R", "ar": "R", "are": "R", "s": "S", "ess": "S",
        "t": "T", "tee": "T", "u": "U", "you": "U", "v": "V", "vee": "V", "w": "W",
        "doubleu": "W", "x": "X", "ex": "X", "y": "Y", "why": "Y", "z": "Z", "zee": "Z",
        "zed": "Z",
    ]

    /// Letter names that are also common English words, admitted only between single-letter names.
    static let ambiguousNames: Set<String> = ["are", "you", "why", "oh", "be", "see"]

    /// Joined letters written as a dotted pair rather than an initialism.
    static let dottedPairs: Set<String> = ["eg", "ie"]

    /// The lexicon's acronyms as written, keyed by their lower-cased letters.
    static let acronyms: [String: String] = Dictionary(
        TechnicalLexicon.terms.filter { $0.category == .acronym }.map { ($0.id.lowercased(), $0.id) },
        uniquingKeysWith: { first, _ in first })

    /// The written stem when the run is a lexicon acronym plus a plural "s" and the whole run is not one itself.
    static func pluralStem(of letters: [String]) -> String? {
        let value = letters.joined().lowercased()
        guard letters.count >= 3, value.hasSuffix("s"), acronyms[value] == nil else { return nil }
        return acronyms[String(value.dropLast())]
    }

    /// The lexicon's fixed forms joined by a spoken "and" or "slash", each with its spoken words: "q and a" is "Q&A".
    static let joinedForms: [(words: [String], written: String)] = TechnicalLexicon.terms
        .filter { $0.category == .joined }
        .flatMap { term in
            term.spoken.map { (words: $0.split(separator: " ").map(String.init), written: term.id) }
        }
        .sorted { $0.words.count > $1.words.count }

    /// The letter `key` names, or nil when it names none.
    static func letter(named key: String) -> String? {
        names[key]
    }

    /// Whether `key` is the spoken name of a letter.
    static func isLetterName(_ key: String) -> Bool {
        names[key] != nil
    }

    /// The kind of a run from its joined letters and whether a number stands directly before it.
    static func kind(of letters: [String], followsNumber: Bool) -> Kind {
        let value = letters.joined()
        if followsNumber, Abbreviations.unitSymbol(spelled: value) != nil { return .unitSymbol }
        if pluralStem(of: letters) != nil { return .plural }
        return dottedPairs.contains(value.lowercased()) ? .dottedPair : .initialism
    }

    /// How each kind is written from its upper-case letters and the first word as said.
    static let writers: [Kind: @Sendable (_ letters: [String], _ first: String) -> String] = [
        .initialism: { letters, first in
            WordShape(first).core.first?.isUppercase == true
                ? WordShape.capitalised(letters.joined()) : letters.joined()
        },
        .dottedPair: { letters, _ in letters.map { $0.lowercased() }.joined(separator: ".") + "." },
        .unitSymbol: { letters, _ in Abbreviations.unitSymbol(spelled: letters.joined()) ?? letters.joined() },
        .plural: { letters, _ in pluralStem(of: letters).map { $0 + "s" } ?? letters.joined() },
    ]

    /// The run written as `kind`.
    static func written(_ letters: [String], as kind: Kind, first: String) -> String {
        writers[kind].map { $0(letters, first) } ?? letters.joined()
    }
}

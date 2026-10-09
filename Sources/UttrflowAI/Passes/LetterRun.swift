import UttrflowCore

/// One reading of a run of spoken letter names: the letters a word names, and how a joined run is written.
enum LetterRun {
    /// How a joined run is written; each kind is a row in `writers`, so a new outcome adds a row, not a branch.
    enum Kind: CaseIterable {
        /// Letters joined into one token, upper case unless the lexicon writes them otherwise: "i o s" is "iOS".
        case initialism
        /// A conventional dotted Latin pair: "e g" is "e.g.".
        case dottedPair
        /// A unit written as its symbol after a number: "five m g" is "5 mg".
        case unitSymbol
        /// A lexicon initialism with a plural "s": "a p i s" is "APIs".
        case plural
        /// A meridiem after a clock time: "5 p m" is "5 pm".
        case meridiem
        /// Letters and digits joined into one code: "e c one a" is "EC1A".
        case code
        /// An airline code and its flight number, a space between: "UA 472".
        case spacedCode
        /// A code that needs no designator, in its own casing: "s p o 2" is "SpO2".
        case knownCode
        /// Hex characters after "zero x": "0xff".
        case hexLiteral
        /// Hex characters after "hash" or "pound": "#fff".
        case hexColour
        /// Hex characters after "hex", "commit" or "sha", with no prefix: "ff00".
        case hexDigits
    }

    /// What stands directly before a run, where its kind depends on it.
    struct Before: OptionSet {
        let rawValue: Int
        /// A number, spoken or in digits, in the same clause.
        static let number = Before(rawValue: 1)
        /// A clock time in digits: "5", "10:30".
        static let clockTime = Before(rawValue: 2)
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

    /// Codes that need no designator, keyed by their letters and digits in lower case, with their written form.
    static let knownCodes: [String: String] = [
        "q1": "Q1", "q2": "Q2", "q3": "Q3", "q4": "Q4", "h1": "H1", "h2": "H2",
        "p0": "P0", "p1": "P1", "p2": "P2", "p3": "P3", "p4": "P4",
        "4k": "4K", "3d": "3D", "b12": "B12", "spo2": "SpO2",
    ]

    /// The lexicon's acronyms as written, keyed by their lower-cased letters.
    static let acronyms: [String: String] = Dictionary(
        TechnicalLexicon.terms.filter { $0.category == .acronym }.map { ($0.id.lowercased(), $0.id) },
        uniquingKeysWith: { first, _ in first })

    /// The lexicon's acronyms said letter by letter, as written, keyed by those letters: "ios" is "iOS".
    static let spelledAcronyms: [String: String] = Dictionary(
        TechnicalLexicon.terms.filter { $0.category == .acronym }.flatMap { term in
            term.spoken.map { $0.split(separator: " ") }.filter { $0.allSatisfy { $0.count == 1 } }
                .map { ($0.joined(), term.id) }
        },
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

    /// The kind of a run from its joined letters and what stands directly before it.
    static func kind(of letters: [String], after before: Before) -> Kind {
        let value = letters.joined()
        if before.contains(.clockTime), NumberFormsPass.meridiems.contains(value.lowercased()) {
            return .meridiem
        }
        if before.contains(.number), Abbreviations.unitSymbol(spelled: value) != nil { return .unitSymbol }
        if pluralStem(of: letters) != nil { return .plural }
        return dottedPairs.contains(value.lowercased()) ? .dottedPair : .initialism
    }

    /// How each kind is written from its pieces as read, letters or digits, and the first word as said.
    static let writers: [Kind: @Sendable (_ letters: [String], _ first: String) -> String] = [
        .initialism: { letters, first in
            if let form = spelledAcronyms[letters.joined().lowercased()] { return form }
            return WordShape(first).core.first?.isUppercase == true
                ? WordShape.capitalised(letters.joined()) : letters.joined()
        },
        .dottedPair: { letters, _ in letters.map { $0.lowercased() }.joined(separator: ".") + "." },
        .unitSymbol: { letters, _ in Abbreviations.unitSymbol(spelled: letters.joined()) ?? letters.joined()
        },
        .plural: { letters, _ in pluralStem(of: letters).map { $0 + "s" } ?? letters.joined() },
        .meridiem: { letters, _ in letters.joined().lowercased() },
        .code: { pieces, _ in pieces.joined() },
        .spacedCode: { pieces, _ in pieces.joined(separator: " ") },
        .knownCode: { pieces, _ in knownCodes[pieces.joined().lowercased()] ?? pieces.joined() },
        .hexLiteral: { characters, _ in "0x" + characters.joined() },
        .hexColour: { characters, _ in "#" + characters.joined() },
        .hexDigits: { characters, _ in characters.joined() },
    ]

    /// The run written as `kind`.
    static func written(_ letters: [String], as kind: Kind, first: String) -> String {
        writers[kind].map { $0(letters, first) } ?? letters.joined()
    }
}

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

    /// Joined letters written as a dotted pair rather than an initialism.
    static let dottedPairs: Set<String> = ["eg", "ie"]

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
    ]

    /// The run written as `kind`.
    static func written(_ letters: [String], as kind: Kind, first: String) -> String {
        writers[kind].map { $0(letters, first) } ?? letters.joined()
    }
}

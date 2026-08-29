/// How a word sounds, as the pair of codes Double Metaphone produces.
///
/// Two codes rather than one because a great many of the words this product exists for
/// have two defensible pronunciations and no way to tell which the speaker meant.
/// "Gemma" and "Gerald" open with the same letter and not the same sound; so do
/// "Chianti" and "chair". A single code has to guess, and guessing wrong is a word the
/// dictionary can never find again. Filing an entry under both, and looking a spoken
/// word up under both, costs one extra hash probe and removes the guess.
public struct PhoneticCode: Sendable, Hashable {
    /// The likelier English reading.
    public let primary: String
    /// The reading a borrowing from another language would give. Equal to ``primary``
    /// when nothing in the word was ambiguous, which is the common case.
    public let alternate: String

    public init(primary: String, alternate: String) {
        self.primary = primary
        self.alternate = alternate
    }

    /// Nothing in the word made a sound — it was empty, or digits and punctuation only.
    public var isSilent: Bool { primary.isEmpty }

    /// The keys this word should be filed and looked up under.
    ///
    /// Empty for a silent word, so a dictionary entry spelt `"2024"` cannot become the
    /// bucket every other silent word lands in.
    public var keys: [String] {
        if isSilent { return [] }
        return alternate == primary ? [primary] : [primary, alternate]
    }
}

extension PhoneticCode {
    /// Whether two spellings could be the same word said aloud.
    ///
    /// Any reading of one matching any reading of the other, which is how the index
    /// answers the same question — an entry is filed under both its codes and a spoken
    /// word is looked up under both of its. Demanding that both readings agree would
    /// reinstate exactly the guess ``alternate`` exists to remove.
    func sounds(like other: PhoneticCode) -> Bool { keys.contains(where: other.keys.contains) }
}

/// Double Metaphone: a word reduced to the sounds in it, so that two spellings a
/// listener could confuse share a key.
///
/// Chosen over Soundex, the other candidate, for three reasons that all bite in this
/// product specifically.
///
/// The first is Soundex's opening letter, which it copies through untouched. "Claude"
/// would key as `C…` and "Klaude" as `K…`, so the two could never meet — and the entire
/// point of this index is that a recogniser which heard the name wrong still finds the
/// entry. Double Metaphone codes the *sound* of the opening, so `C`, `K`, `Ch` and `Q`
/// converge where they should.
///
/// The second is Soundex's four-character truncation, which is right for matching
/// surnames in a census and wrong for `setUserPrefs` and `PaymentSheet`. Every
/// identifier a developer dictates would collapse into a handful of buckets, and a
/// bucket that holds a hundred entries is not a candidate list, it is a scan.
///
/// The third is the alternate code, described on ``PhoneticCode``. Soundex has no
/// equivalent, so a word with two pronunciations has to pick one.
///
/// This is the English rule set. Double Metaphone's published implementation also
/// carries Slavo-Germanic, Spanish, Italian and Greek special cases, keyed off guesses
/// about a word's origin made from its spelling. Those are not implemented here,
/// deliberately: they change a small number of words from one code to two, and the
/// words they change are surnames from a 1990s census rather than the names and
/// technical terms a person dictates into their Mac. Leaving them out only ever merges
/// two keys into one, which costs an occasional extra candidate — the safe direction
/// for an index whose output is a shortlist, not an answer.
public enum DoubleMetaphone {
    /// The sound of one word.
    ///
    /// Case-insensitive, and indifferent to anything that is not a letter: digits,
    /// punctuation and spaces make no sound, so `"payment sheet"` and `"PaymentSheet"`
    /// come back with the same code. That is what lets a spoken phrase find a
    /// camel-cased entry.
    public static func code(for word: String) -> PhoneticCode {
        var encoder = Encoder(word: word)
        return encoder.encode()
    }
}

extension DoubleMetaphone {
    /// One pass over one word.
    ///
    /// A struct with a cursor rather than a chain of pure functions because the rules
    /// genuinely are positional — half of them ask what came before and what comes
    /// next, and several consume more than one letter. Threading an index through free
    /// functions would say the same thing with more punctuation.
    fileprivate struct Encoder {
        private let letters: [Character]
        private var primary = ""
        private var alternate = ""
        private var index = 0

        init(word: String) {
            letters = Array(word.uppercased())
        }

        mutating func encode() -> PhoneticCode {
            skipSilentOpening()
            while index < letters.count {
                step()
            }
            return PhoneticCode(primary: primary, alternate: alternate)
        }

        // MARK: - Looking around the cursor

        private func letter(at offset: Int) -> Character? {
            guard offset >= 0, offset < letters.count else { return nil }
            return letters[offset]
        }

        private func fragment(at offset: Int, length: Int) -> String {
            guard offset >= 0, offset < letters.count else { return "" }
            return String(letters[offset..<min(offset + length, letters.count)])
        }

        private func matches(_ offset: Int, _ candidates: [String]) -> Bool {
            candidates.contains { fragment(at: offset, length: $0.count) == $0 }
        }

        private func matches(_ offset: Int, _ candidates: String...) -> Bool {
            matches(offset, candidates)
        }

        /// `Y` counts, because it behaves like one everywhere the rules care.
        private func isVowel(at offset: Int) -> Bool {
            guard let letter = letter(at: offset) else { return false }
            return "AEIOUY".contains(letter)
        }

        /// A letter that is there and is not a vowel. Distinct from `!isVowel`, which
        /// is also true of the end of the word — and the two want opposite answers:
        /// "match" ends in a `CH` that is still sounded.
        private func isConsonant(at offset: Int) -> Bool {
            letter(at: offset) != nil && !isVowel(at: offset)
        }

        // MARK: - Emitting

        private mutating func emit(_ main: String, or other: String) {
            primary += main
            alternate += other
        }

        private mutating func emit(_ both: String) {
            emit(both, or: both)
        }

        /// Emits a sound and steps over the pair that spells it, when that is how it is
        /// spelt. A doubled letter is one sound, not two.
        private mutating func emit(_ code: String, skipping pairs: String...) {
            emit(code)
            index += matches(index, pairs) ? 2 : 1
        }

        // MARK: - The rules

        /// Openings whose first letter is written but not said.
        private mutating func skipSilentOpening() {
            if matches(0, "GN", "KN", "PN", "WR", "PS") { index = 1 }
            // An opening X is said "z" — Xavier, xylophone — and nowhere else is it.
            if letter(at: 0) == "X" {
                emit("S")
                index = 1
            }
        }

        private mutating func step() {
            if isVowel(at: index) {
                // Only the first vowel is kept. Inside a word the vowels are precisely
                // the part a listener gets wrong, which is what this key discards.
                if index == 0 { emit("A") }
                index += 1
                return
            }
            switch letters[index] {
            case "B": emit("P", skipping: "BB")
            case "C": encodeC()
            case "D": encodeD()
            case "F": emit("F", skipping: "FF")
            case "G": encodeG()
            case "H": encodeH()
            case "J": emit("J", skipping: "JJ")
            case "K": emit("K", skipping: "KK")
            case "L": emit("L", skipping: "LL")
            case "M": emit("M", skipping: "MM")
            case "N": emit("N", skipping: "NN")
            case "P": encodeP()
            case "Q": emit("K", skipping: "QQ")
            case "R": emit("R", skipping: "RR")
            case "S": encodeS()
            case "T": encodeT()
            case "V": emit("F", skipping: "VV")
            case "W": encodeW()
            case "X": emit("KS", skipping: "XC", "XX")
            case "Z": encodeZ()
            // Digits, punctuation, spaces, accented letters: no sound, no key.
            default: index += 1
            }
        }

        private mutating func encodeC() {
            if matches(index, "CH") {
                encodeCH()
                return
            }
            if matches(index, "CIA") {
                // "special", "Garcia".
                emit("X")
                index += 3
                return
            }
            if matches(index, "CC") {
                // "accept" is two sounds where "occur" is one.
                emit(matches(index + 2, "E", "I") ? "KS" : "K")
                index += 2
                return
            }
            if matches(index, "CK", "CG", "CQ") {
                emit("K")
                index += 2
                return
            }
            if matches(index, "CE", "CI", "CY") {
                emit("S")
                index += 2
                return
            }
            emit("K")
            index += 1
        }

        private mutating func encodeCH() {
            // A CH followed by another consonant is hard: "Christmas", "chlorine".
            if isConsonant(at: index + 2) {
                emit("K")
                index += 2
                return
            }
            // Otherwise "sh" — but the Greek and Italian borrowings say "k", and that
            // is exactly the disagreement the alternate code exists to hold.
            emit("X", or: "K")
            index += 2
        }

        private mutating func encodeD() {
            if matches(index, "DGE", "DGI", "DGY") {
                // "edge", "ledger".
                emit("J")
                index += 3
                return
            }
            if matches(index, "DT", "DD") {
                emit("T")
                index += 2
                return
            }
            emit("T")
            index += 1
        }

        private mutating func encodeG() {
            if matches(index, "GH") {
                // "ghost" says it and so does "Pittsburgh"; "night" and "Bagh" do not.
                if index == 0 || isConsonant(at: index - 1) { emit("K") }
                index += 2
                return
            }
            if matches(index, "GN") {
                // "sign" and "signed" drop the G. "magnetic" keeps it.
                let silent = index + 2 == letters.count || matches(index + 2, "ED")
                emit(silent ? "N" : "KN")
                index += 2
                return
            }
            if matches(index, "GG") {
                emit("K")
                index += 2
                return
            }
            if matches(index + 1, "E", "I", "Y") {
                // "gem" and "get" are both ordinary English. Only two codes hold both.
                emit("J", or: "K")
                index += 2
                return
            }
            emit("K")
            index += 1
        }

        private mutating func encodeH() {
            // An H is only sounded when a vowel leans on it from both sides, or from
            // the right at the start of a word. That is what silences the H in
            // "Uttrflow" and in "Nikhil", so both key on their consonants alone.
            if index == 0 || isVowel(at: index - 1), isVowel(at: index + 1) { emit("H") }
            index += 1
        }

        private mutating func encodeP() {
            if matches(index, "PH") {
                emit("F")
                index += 2
                return
            }
            emit("P", skipping: "PP", "PB")
        }

        private mutating func encodeS() {
            if matches(index, "SCH") {
                // German "schedule" against Greek "school". The endings below are the
                // ones that reliably mean the Greek reading.
                if matches(index + 3, "OO", "ER", "EN", "UY", "ED", "EM") {
                    emit("SK")
                } else {
                    emit("X", or: "SK")
                }
                index += 3
                return
            }
            if matches(index, "SH") {
                emit("X")
                index += 2
                return
            }
            if matches(index, "SIA", "SIO") {
                // "vision", "Asia".
                emit("X", or: "S")
                index += 3
                return
            }
            emit("S", skipping: "SS")
        }

        private mutating func encodeT() {
            if matches(index, "TIA", "TIO") {
                // "nation", "partial".
                emit("X")
                index += 3
                return
            }
            if matches(index, "TH") {
                // English has no letter for the sound, so Double Metaphone borrows a
                // digit for it. The alternate keeps "Thomas" reachable from "Tomas".
                emit("0", or: "T")
                index += 2
                return
            }
            if matches(index, "TCH") {
                // The T is swallowed; the CH behind it carries the whole sound.
                index += 1
                return
            }
            emit("T", skipping: "TT", "TD")
        }

        private mutating func encodeW() {
            if matches(index, "WR") {
                emit("R")
                index += 2
                return
            }
            if index == 0, matches(index, "WH") {
                emit("A")
                index += 2
                return
            }
            if index == 0, isVowel(at: index + 1) {
                // An opening W behaves like a vowel, and in the languages that spell it
                // with a V it behaves like an F. Both readings are kept.
                emit("A", or: "F")
                index += 1
                return
            }
            // Everywhere else a W is not a sound of its own — which is the whole reason
            // "clawed" reaches "Claude".
            index += 1
        }

        private mutating func encodeZ() {
            if matches(index, "ZH") {
                emit("J")
                index += 2
                return
            }
            emit("S", skipping: "ZZ")
        }
    }
}

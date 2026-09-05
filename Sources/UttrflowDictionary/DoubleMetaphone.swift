/// How a word sounds, as Double Metaphone's two codes, so an ambiguous opening never has to be guessed.
public struct PhoneticCode: Sendable, Hashable {
    /// The likelier English reading.
    public let primary: String
    /// The reading a borrowing from another language gives; equal to `primary` when nothing is ambiguous.
    public let alternate: String

    public init(primary: String, alternate: String) {
        self.primary = primary
        self.alternate = alternate
    }

    /// Nothing in the word makes a sound: empty, or digits and punctuation only.
    public var isSilent: Bool { primary.isEmpty }

    /// The keys this word is filed and looked up under; empty for a silent word, so `"2024"` has no bucket.
    public var keys: [String] {
        if isSilent { return [] }
        return alternate == primary ? [primary] : [primary, alternate]
    }
}

extension PhoneticCode {
    /// Whether two spellings could be the same word said aloud: any reading of one matching any of the other.
    func sounds(like other: PhoneticCode) -> Bool { keys.contains(where: other.keys.contains) }

    /// Whether any reading of this word is among `sounds`, the keys of everything else that was said or shown.
    func sounds(likeAnyOf sounds: Set<String>) -> Bool { keys.contains(where: sounds.contains) }
}

/// Double Metaphone, English rules only, so confusable spellings share a key. See Docs/app-dictionary.md.
public enum DoubleMetaphone {
    /// The sound of one word; case and anything that is not a letter make no difference.
    public static func code(for word: String) -> PhoneticCode {
        var encoder = Encoder(word: word)
        return encoder.encode()
    }
}

extension DoubleMetaphone {
    /// One pass over one word, with a cursor because half the rules ask what comes before and after.
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

        /// A letter that is there and is not a vowel; `!isVowel` is also true at the end of the word.
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

        /// Emits a sound and steps over a doubled letter that spells it, since a doubled letter is one sound.
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
                // Only the first vowel is kept; inside a word the vowels are what a listener gets wrong.
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
            // Otherwise "sh", with "k" for the Greek and Italian borrowings in the alternate.
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
            // An H is sounded only between vowels, or before one at the start of a word.
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
                // German "schedule" against Greek "school"; these endings mean the Greek reading.
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
                // A digit stands for "th"; the alternate keeps "Thomas" reachable from "Tomas".
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
                // An opening W is a vowel, or an F in the languages that spell it with a V.
                emit("A", or: "F")
                index += 1
                return
            }
            // Elsewhere a W is no sound of its own, which is why "clawed" reaches "Claude".
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

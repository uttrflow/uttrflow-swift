// Devanagari written as romanised Hinglish, the way people type it.
import Foundation

/// Writes Devanagari the way Hinglish is typed: no diacritics, no silent vowels, common words spelled as people spell them. See `Docs/latin-output.md`.
public enum Romaniser {
    /// The text with every Devanagari run romanised and everything else left as it was; a romanised word may open a sentence with a capital.
    public static func romanised(_ text: String, capitalisingSentences: Bool = false) -> String {
        guard containsDevanagari(text) else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if let digit = digits[scalar] {
                output.append(digit)
                index += 1
            } else if stops.contains(scalar) {
                // A stop the recogniser also wrote in Latin is kept once.
                let next = index + 1 < scalars.count ? scalars[index + 1] : nil
                if !(next.map { ".!?".unicodeScalars.contains($0) } ?? false) { output.append(".") }
                index += 1
            } else if isWordScalar(scalar) {
                var end = index
                while end < scalars.count, isWordScalar(scalars[end]) { end += 1 }
                let spelled = word(Array(scalars[index..<end]))
                let opens = capitalisingSentences && opensSentence(String(output))
                output.append(
                    contentsOf: (opens ? spelled.prefix(1).uppercased() + spelled.dropFirst() : spelled)
                        .unicodeScalars)
                index = end
            } else {
                if !isDevanagari(scalar) { output.append(scalar) }
                index += 1
            }
        }
        return String(output)
    }

    /// Whether a word written after `text` begins a sentence: nothing but space before it, or a stop.
    static func opensSentence(_ text: String) -> Bool {
        guard let last = text.last(where: { !$0.isWhitespace || $0.isNewline }) else { return true }
        return ".!?\n".contains(last)
    }

    /// Whether any Devanagari is present.
    public static func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isDevanagari)
    }

    /// A romanised word folded so its common spelling variants meet: "theek" and "thik", "woh" and "wo".
    public static func soundKey(_ word: String) -> String {
        var folded = word.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        for (from, to) in [("ph", "f"), ("w", "v"), ("q", "k"), ("ee", "i"), ("oo", "u"), ("ein", "en")] {
            folded = folded.replacingOccurrences(of: from, with: to)
        }
        var key = ""
        for character in folded where character != key.last { key.append(character) }
        // A final "h" after a vowel is not said: "woh" is "wo", "yeh" is "ye".
        if key.count > 1, key.hasSuffix("h"), let before = key.dropLast().last, "aeiou".contains(before) {
            key.removeLast()
        }
        return key
    }

    // MARK: Words

    /// One Devanagari word romanised: the common spelling when there is one, otherwise by syllable.
    static func word(_ scalars: [Unicode.Scalar]) -> String {
        let normal = normalised(scalars)
        if let common = commonSpellings[String(String.UnicodeScalarView(normal))] { return common }
        var syllables = parse(normal)
        guard !syllables.isEmpty else { return "" }
        dropSilentVowels(&syllables)
        return spell(syllables)
    }

    /// Precomposed nukta letters split into letter and nukta, and chandrabindu written as anusvara, so spelling variants share a form.
    static func normalised(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.flatMap { scalar -> [Unicode.Scalar] in
            if let base = precomposedNukta[scalar] { return [base, nukta] }
            if scalar == candrabindu || scalar == invertedCandrabindu { return [anusvara] }
            return scalar == zeroWidthJoiner || scalar == zeroWidthNonJoiner ? [] : [scalar]
        }
    }

    /// A consonant as written, with whether a nukta changes its sound.
    struct Consonant: Equatable {
        let base: Unicode.Scalar
        let hasNukta: Bool
    }

    /// One written syllable: its consonants, its vowel, and the marks after it.
    struct Syllable: Equatable {
        var consonants: [Consonant]
        /// The vowel's sound; empty once a silent vowel is dropped or a virama ends the syllable.
        var vowel: String
        /// Whether the vowel is the one a consonant carries unwritten.
        let isInherent: Bool
        let isNasal: Bool
        let hasVisarga: Bool
        /// Whether the vowel is written as a letter of its own rather than as a sign on a consonant.
        let isIndependent: Bool
    }

    /// The word's syllables, skipping any sign with no letter to sit on.
    static func parse(_ word: [Unicode.Scalar]) -> [Syllable] {
        var syllables: [Syllable] = []
        var index = 0
        func take(_ scalar: Unicode.Scalar) -> Bool {
            guard index < word.count, word[index] == scalar else { return false }
            index += 1
            return true
        }
        while index < word.count {
            let scalar = word[index]
            if consonants[scalar] != nil {
                var cluster: [Consonant] = []
                while index < word.count, consonants[word[index]] != nil {
                    let base = word[index]
                    index += 1
                    cluster.append(Consonant(base: base, hasNukta: take(nukta)))
                    // A virama joins the next consonant into the cluster.
                    guard index + 1 < word.count, word[index] == virama, consonants[word[index + 1]] != nil
                    else { break }
                    index += 1
                }
                var vowel = "a"
                var isInherent = true
                if take(virama) {
                    vowel = ""
                    isInherent = false
                } else if index < word.count, let sign = vowelSigns[word[index]] {
                    vowel = sign
                    isInherent = false
                    index += 1
                }
                syllables.append(
                    Syllable(
                        consonants: cluster, vowel: vowel, isInherent: isInherent, isNasal: take(anusvara),
                        hasVisarga: take(visarga), isIndependent: false))
            } else if let sound = independentVowels[scalar] {
                index += 1
                syllables.append(
                    Syllable(
                        consonants: [], vowel: sound, isInherent: false, isNasal: take(anusvara),
                        hasVisarga: take(visarga), isIndependent: true))
            } else {
                index += 1
            }
        }
        return syllables
    }

    /// Drops the unwritten vowel at the end of a word and between a vowel and a consonant that carries one: "karana" is "karna".
    static func dropSilentVowels(_ syllables: inout [Syllable]) {
        let count = syllables.count
        // A cluster ending in "y", "r" or "v" keeps it, as in "mitra" and "karya"; "agast" and "dost" do not.
        if count > 1, syllables[count - 1].isInherent,
            let last = syllables[count - 1].consonants.last,
            syllables[count - 1].consonants.count == 1 || !["य", "र", "व"].contains(last.base)
        {
            syllables[count - 1].vowel = ""
        }
        guard count > 2 else { return }
        for index in stride(from: count - 2, through: 1, by: -1) {
            let syllable = syllables[index]
            guard syllable.isInherent, syllable.vowel == "a", !syllable.isNasal,
                syllable.consonants.count == 1
            else { continue }
            let before = syllables[index - 1]
            let after = syllables[index + 1]
            // A conjunct after it keeps the vowel: "ananya", not "annya".
            guard !before.vowel.isEmpty, !after.vowel.isEmpty, after.consonants.count == 1 else { continue }
            syllables[index].vowel = ""
        }
    }

    /// The syllables written out, with long vowels doubled only where people double them.
    static func spell(_ syllables: [Syllable]) -> String {
        var written = ""
        for (index, syllable) in syllables.enumerated() {
            let isFirst = index == 0
            let isLast = index == syllables.count - 1
            let next = isLast ? nil : syllables[index + 1]
            let isClosed = next.map { $0.vowel.isEmpty || $0.consonants.count > 1 } ?? false
            var vowel = syllable.vowel
            let consonants = cluster(syllable.consonants, before: vowel)
            switch vowel {
            case "aa":
                vowel = longA(syllable, isFirst: isFirst, isLast: isLast, isClosed: isClosed, next: next)
            case "ii", "uu":
                let opensLong = isFirst && (next.map { $0.vowel == "a" || $0.vowel == "aa" } ?? false)
                let isLong = !isLast && !syllable.isNasal && (isClosed || opensLong)
                vowel = vowel == "ii" ? (isLong ? "ee" : "i") : (isLong ? "oo" : "u")
            case "e" where syllable.isIndependent && index > 0 && !syllables[index - 1].vowel.isEmpty:
                vowel = "ye"
            default:
                break
            }
            var spelled = consonants + vowel
            // An unwritten vowel before an "h" that closes the syllable is said "e": "pehle", "keh".
            if syllable.isInherent, vowel == "a", let next,
                next.consonants == [Consonant(base: ha, hasNukta: false)],
                next.vowel.isEmpty, index + 2 < syllables.count || syllables.count == 2
            {
                spelled = consonants + "e"
            }
            if syllable.isNasal {
                let beforeNasalConsonant = next?.consonants.first.map { [na, ma].contains($0.base) } ?? false
                if !beforeNasalConsonant { spelled += vowel == "e" && isLast ? "in" : "n" }
            }
            if syllable.hasVisarga { spelled += "h" }
            written += spelled
        }
        return written
    }

    /// The long "a": doubled in a first or closed syllable, single at the end of a word or before another vowel.
    private static func longA(
        _ syllable: Syllable, isFirst: Bool, isLast: Bool, isClosed: Bool, next: Syllable?
    ) -> String {
        if syllable.isIndependent { return "aa" }
        if syllable.isNasal { return isLast ? "a" : "aa" }
        if isLast || (next.map { $0.consonants.isEmpty } ?? false) { return "a" }
        return isFirst || isClosed ? "aa" : "a"
    }

    /// A consonant cluster in Latin letters; `vowel` is the sound after its last consonant.
    static func cluster(_ letters: [Consonant], before vowel: String) -> String {
        var written = ""
        var index = 0
        while index < letters.count {
            let letter = letters[index]
            let following = index + 1 < letters.count ? letters[index + 1] : nil
            if let following, !letter.hasNukta {
                let pair = String(String.UnicodeScalarView([letter.base, following.base]))
                if let joined = joinedPairs[pair] {
                    written += joined
                    index += 2
                    continue
                }
            }
            written += sound(of: letter, before: following == nil ? vowel : "")
            index += 1
        }
        return written
    }

    /// One consonant's sound; "v" is written "w" except before an "i" or an "e", as in "wala" and "vikram".
    static func sound(of letter: Consonant, before vowel: String) -> String {
        if letter.hasNukta, let changed = nuktaSounds[letter.base] { return changed }
        if letter.base == va { return ["i", "ii", "e"].contains(vowel) ? "v" : "w" }
        return consonants[letter.base] ?? ""
    }

    // MARK: Tables

    /// Whether a scalar is in the Devanagari block.
    static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
        (0x0900...0x097F).contains(scalar.value)
    }

    /// Whether a scalar belongs inside a Devanagari word: a letter or sign, or a joiner between them.
    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == zeroWidthJoiner || scalar == zeroWidthNonJoiner { return true }
        return isDevanagari(scalar) && digits[scalar] == nil && !stops.contains(scalar)
            && scalar != avagraha
    }

    static let virama: Unicode.Scalar = "\u{094D}"
    static let anusvara: Unicode.Scalar = "\u{0902}"
    static let candrabindu: Unicode.Scalar = "\u{0901}"
    static let invertedCandrabindu: Unicode.Scalar = "\u{0900}"
    static let visarga: Unicode.Scalar = "\u{0903}"
    static let nukta: Unicode.Scalar = "\u{093C}"
    static let avagraha: Unicode.Scalar = "\u{093D}"
    static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    static let zeroWidthNonJoiner: Unicode.Scalar = "\u{200C}"
    static let ha: Unicode.Scalar = "\u{0939}"
    static let na: Unicode.Scalar = "\u{0928}"
    static let ma: Unicode.Scalar = "\u{092E}"
    static let va: Unicode.Scalar = "\u{0935}"

    /// The danda, the double danda and the abbreviation sign, each written as a full stop.
    static let stops: Set<Unicode.Scalar> = ["\u{0964}", "\u{0965}", "\u{0970}"]

    /// Devanagari digits as Western ones.
    static let digits: [Unicode.Scalar: Unicode.Scalar] = Dictionary(
        uniqueKeysWithValues: (0...9).compactMap { value in
            guard let devanagari = Unicode.Scalar(0x0966 + value), let western = Unicode.Scalar(0x30 + value)
            else { return nil }
            return (devanagari, western)
        })

    static let consonants: [Unicode.Scalar: String] = [
        "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "n",
        "च": "ch", "छ": "chh", "ज": "j", "झ": "jh", "ञ": "n",
        "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n",
        "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
        "प": "p", "फ": "ph", "ब": "b", "भ": "bh", "म": "m",
        "य": "y", "र": "r", "ल": "l", "व": "v", "श": "sh", "ष": "sh", "स": "s", "ह": "h",
        "ळ": "l",
    ]

    /// The sound a nukta gives a consonant: "ज़" is "z", "फ़" is "f".
    static let nuktaSounds: [Unicode.Scalar: String] = [
        "क": "q", "ख": "kh", "ग": "gh", "ज": "z", "ड": "d", "ढ": "dh", "फ": "f", "य": "y", "र": "r",
        "न": "n", "ळ": "l",
    ]

    /// Letters encoded with their nukta built in, and the letter each is written from.
    static let precomposedNukta: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{0929}": "न", "\u{0931}": "र", "\u{0934}": "ळ", "\u{0958}": "क", "\u{0959}": "ख",
        "\u{095A}": "ग", "\u{095B}": "ज", "\u{095C}": "ड", "\u{095D}": "ढ", "\u{095E}": "फ",
        "\u{095F}": "य",
    ]

    /// Vowel signs, long vowels written doubled until `spell` decides how people write them.
    static let vowelSigns: [Unicode.Scalar: String] = [
        "\u{093E}": "aa", "\u{093F}": "i", "\u{0940}": "ii", "\u{0941}": "u", "\u{0942}": "uu",
        "\u{0943}": "ri", "\u{0944}": "ri", "\u{0945}": "e", "\u{0946}": "e", "\u{0947}": "e",
        "\u{0948}": "ai", "\u{094A}": "o", "\u{094B}": "o", "\u{094C}": "au", "\u{0949}": "o",
        "\u{0962}": "li", "\u{0963}": "li", "\u{094E}": "e", "\u{094F}": "aw",
    ]

    static let independentVowels: [Unicode.Scalar: String] = [
        "अ": "a", "आ": "aa", "इ": "i", "ई": "ii", "उ": "u", "ऊ": "uu", "ऋ": "ri", "ॠ": "ri", "ए": "e",
        "ऐ": "ai", "ओ": "o", "औ": "au", "ऑ": "o", "ऍ": "e", "ऌ": "li", "ॡ": "li", "ऎ": "e", "ऒ": "o",
        "ॐ": "om",
    ]

    /// Consonant pairs people write as one sound: a doubled "cch" in "accha", "ksh", "gy" in "gyaan".
    static let joinedPairs: [String: String] = [
        "चछ": "cch", "चच": "cch", "तथ": "tth", "दध": "ddh", "टठ": "tth", "कख": "kkh", "गघ": "ggh",
        "बभ": "bbh", "पफ": "pph", "डढ": "ddh", "कष": "ksh", "जञ": "gy",
    ]

    /// Words whose typed spelling the syllable rules do not reach, written as people type them. See `Docs/latin-output.md`.
    static let commonSpellings: [String: String] = Dictionary(
        uniqueKeysWithValues: commonSpellingList.map { spelling in
            (String(String.UnicodeScalarView(normalised(Array(spelling.0.unicodeScalars)))), spelling.1)
        })

    private static let commonSpellingList: [(String, String)] = [
        ("है", "hai"), ("हैं", "hain"), ("हाँ", "haan"), ("ठीक", "thik"), ("नहीं", "nahi"), ("नही", "nahi"),
        ("मैं", "main"), ("में", "mein"), ("क्या", "kya"), ("क्यों", "kyun"), ("क्यूँ", "kyun"),
        ("हूँ", "hoon"), ("यह", "yeh"), ("ये", "ye"), ("वह", "woh"), ("वो", "wo"), ("और", "aur"),
        ("भी", "bhi"), ("तो", "to"), ("कि", "ki"), ("की", "ki"), ("का", "ka"), ("के", "ke"), ("को", "ko"),
        ("से", "se"), ("पर", "par"), ("लिए", "liye"), ("लिये", "liye"), ("अच्छा", "accha"),
        ("अच्छी", "acchi"), ("अच्छे", "acche"), ("जी", "ji"), ("वाला", "wala"), ("वाली", "wali"),
        ("वाले", "wale"), ("कह", "keh"), ("रह", "reh"), ("कुछ", "kuch"), ("बहुत", "bahut"),
        ("चाहिए", "chahiye"), ("चाहिये", "chahiye"), ("आप", "aap"), ("तुम", "tum"), ("हम", "hum"),
        ("मुझे", "mujhe"), ("इसलिए", "isliye"), ("क्योंकि", "kyunki"), ("लेकिन", "lekin"),
        ("मतलब", "matlab"), ("यार", "yaar"), ("अरे", "arre"), ("धन्यवाद", "dhanyavaad"),
        ("शुक्रिया", "shukriya"), ("नमस्ते", "namaste"), ("कहाँ", "kahan"), ("यहाँ", "yahan"),
        ("वहाँ", "wahan"), ("एक", "ek"), ("दो", "do"), ("तीन", "teen"), ("चार", "chaar"),
        ("पाँच", "paanch"), ("छह", "chhah"), ("सात", "saat"), ("आठ", "aath"), ("नौ", "nau"), ("दस", "das"),
        ("बीस", "bees"), ("सौ", "sau"), ("हज़ार", "hazaar"), ("हजार", "hazaar"), ("लाख", "lakh"),
        ("करोड़", "crore"), ("गया", "gaya"), ("गई", "gayi"), ("गए", "gaye"), ("गयी", "gayi"),
        ("गये", "gaye"), ("दिया", "diya"), ("किया", "kiya"), ("लिया", "liya"), ("हुआ", "hua"),
        ("हुई", "hui"), ("हुए", "hue"), ("सकता", "sakta"), ("सकती", "sakti"), ("सकते", "sakte"),
        ("पता", "pata"), ("मत", "mat"), ("ना", "na"), ("न", "na"), ("ज़रा", "zara"), ("थोड़ा", "thoda"),
        ("थोड़ी", "thodi"), ("थोड़े", "thode"), ("ज़्यादा", "zyada"), ("सिर्फ़", "sirf"), ("सिर्फ", "sirf"),
        ("फिर", "phir"), ("पहले", "pehle"), ("बाद", "baad"), ("साथ", "saath"), ("कैसे", "kaise"),
        ("कैसा", "kaisa"), ("कैसी", "kaisi"), ("ऐसा", "aisa"), ("ऐसे", "aise"), ("जैसे", "jaise"),
        ("वैसे", "waise"), ("अपना", "apna"), ("अपनी", "apni"), ("अपने", "apne"), ("मेरा", "mera"),
        ("मेरी", "meri"), ("मेरे", "mere"), ("तेरा", "tera"), ("तुम्हारा", "tumhara"), ("हमारा", "hamara"),
        ("हमारे", "hamare"), ("हमारी", "hamari"), ("उसका", "uska"), ("उसकी", "uski"), ("उसके", "uske"),
        ("उनका", "unka"), ("इसका", "iska"), ("भाई", "bhai"), ("ऑफिस", "office"), ("ऑफ़िस", "office"),
        ("मीटिंग", "meeting"), ("रिपोर्ट", "report"), ("ओके", "ok"), ("सॉरी", "sorry"), ("प्लीज़", "please"),
        ("प्लीज", "please"), ("थैंक्स", "thanks"), ("हेलो", "hello"), ("हैलो", "hello"), ("बाय", "bye"),
        ("कॉल", "call"), ("मैसेज", "message"), ("ईमेल", "email"), ("फ़ोन", "phone"), ("फोन", "phone"),
        ("टाइम", "time"), ("मिनट", "minute"), ("जाएगा", "jayega"), ("जाएगी", "jayegi"),
        ("जाएंगे", "jayenge"), ("आएगा", "aayega"), ("आएगी", "aayegi"), ("उन्हें", "unhe"),
        ("इन्हें", "inhe"), ("हमें", "hamein"), ("तुम्हें", "tumhe"), ("रहा", "raha"), ("रही", "rahi"),
        ("रहे", "rahe"), ("था", "tha"), ("थी", "thi"), ("थे", "the"), ("अभी", "abhi"), ("कभी", "kabhi"),
        ("सभी", "sabhi"), ("कोई", "koi"), ("बात", "baat"), ("आज", "aaj"), ("कल", "kal"),
    ]
}

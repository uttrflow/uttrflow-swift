import Testing

@testable import UttrflowCore

/// The romaniser audited by sound class, each case against the form people type. See `Docs/latin-output.md`.
@Suite("Romaniser by sound class")
struct RomaniserSoundClassTests {
    /// Each consonant as typed at the start of a syllable.
    static let consonants: [(String, String)] = [
        ("क", "k"), ("ख", "kh"), ("ग", "g"), ("घ", "gh"), ("च", "ch"), ("छ", "chh"), ("ज", "j"), ("झ", "jh"),
        ("ट", "t"), ("ठ", "th"), ("ड", "d"), ("ढ", "dh"), ("ण", "n"), ("त", "t"), ("थ", "th"), ("द", "d"),
        ("ध", "dh"), ("न", "n"), ("प", "p"), ("फ", "ph"), ("ब", "b"), ("भ", "bh"), ("म", "m"), ("य", "y"),
        ("र", "r"), ("ल", "l"), ("श", "sh"), ("ष", "sh"), ("स", "s"), ("ह", "h"),
    ]

    /// Each vowel sign, and how it is typed in a first syllable closed by a consonant.
    static let closedVowels: [(String, String)] = [
        ("", "a"), ("\u{093E}", "aa"), ("\u{093F}", "i"), ("\u{0940}", "ee"), ("\u{0941}", "u"),
        ("\u{0942}", "oo"), ("\u{0943}", "ri"), ("\u{0947}", "e"), ("\u{0948}", "ai"), ("\u{094B}", "o"),
        ("\u{094C}", "au"),
    ]

    /// Words that exercise one sound class each, with the form people type.
    static let classes: [String: [(String, String)]] = [
        "independent vowel": [
            ("अब", "ab"), ("आम", "aam"), ("इधर", "idhar"), ("उधर", "udhar"), ("ऋषि", "rishi"), ("एक", "ek"),
            ("ऐनक", "ainak"), ("ओर", "or"), ("औरत", "aurat"),
        ],
        "conjunct": [
            ("क्षमा", "kshama"), ("लक्ष्य", "lakshya"), ("मित्र", "mitra"), ("पत्र", "patra"), ("ज्ञान", "gyaan"),
            ("विज्ञान", "vigyaan"), ("श्री", "shri"), ("श्रम", "shram"), ("द्वार", "dwaar"), ("स्वाद", "swaad"),
            ("प्रेम", "prem"), ("क्रम", "kram"), ("पत्ता", "patta"), ("बच्चा", "baccha"), ("दिल्ली", "dilli"),
            ("पक्का", "pakka"), ("खट्टा", "khatta"), ("अक्सर", "aksar"),
        ],
        "final halant": [("जगत्", "jagat"), ("विद्युत्", "vidyut"), ("सम्यक्", "samyak")],
        "anusvara before a velar": [("अंक", "ank"), ("गंगा", "ganga"), ("रंग", "rang"), ("शंख", "shankh")],
        "anusvara before a palatal": [("चंचल", "chanchal"), ("मंच", "manch")],
        "anusvara before a retroflex": [("ठंडा", "thanda"), ("घंटा", "ghanta")],
        "anusvara before a dental": [("अंत", "ant"), ("हिंदी", "hindi"), ("संत", "sant"), ("बंद", "band")],
        "anusvara before a labial": [
            ("मुंबई", "mumbai"), ("नंबर", "nambar"), ("कंबल", "kambal"), ("संपर्क", "sampark"),
            ("चंपा", "champa"), ("खंभा", "khambha"),
        ],
        "anusvara before a sibilant or semivowel": [("संसार", "sansaar"), ("हंस", "hans"), ("संयम", "sanyam")],
        "chandrabindu": [
            ("माँ", "maa"), ("मां", "maa"), ("चाँद", "chaand"), ("आँख", "aankh"), ("गाँव", "gaon"),
            ("ऊँचा", "uncha"),
        ],
        "nukta": [
            ("ज़मीन", "zameen"), ("फ़र्क़", "farq"), ("क़लम", "qalam"), ("ख़ुश", "khush"), ("ग़म", "gham"),
            ("पेड़", "ped"), ("पढ़ना", "padhna"), ("सड़क", "sadak"),
        ],
        "visarga": [("दुःख", "duhkh"), ("अतः", "atah"), ("प्रातः", "praatah"), ("नमः", "namah")],
        "digit": [("०१२३४", "01234"), ("५६७८९", "56789")],
    ]

    /// Unwritten-vowel cases, which need a rule rather than a table.
    static let silentVowels: [(String, String)] = [
        ("कमला", "kamla"), ("समझ", "samajh"), ("बदलना", "badalna"), ("नमकीन", "namkeen"), ("कमरा", "kamra"),
        ("मकान", "makaan"), ("सरकार", "sarkaar"), ("गलती", "galti"), ("रखना", "rakhna"), ("दोपहर", "dopahar"),
        ("जनवरी", "janvari"), ("चाय", "chai"), ("हँसना", "hansna"),
        ("दुपहिया", "dupahiya"), ("फ़रवरी", "farvari"),
    ]

    /// Inputs the romaniser writes wrongly today; each is expected to fail until its class is fixed.
    static let knownGaps: Set<String> = [
        "मुंबई", "नंबर", "कंबल", "संपर्क", "चंपा", "खंभा", "माँ", "मां", "अतः", "प्रातः", "नमः",
        "हँसना",
    ]

    /// Checks one case, recording a listed gap as a known issue so a fix shows up as an unexpected pass.
    static func check(_ devanagari: String, _ typed: String) {
        guard knownGaps.contains(devanagari) else {
            #expect(Romaniser.romanised(devanagari) == typed, "\(devanagari)")
            return
        }
        withKnownIssue("\(devanagari) is not yet written \(typed)") {
            #expect(Romaniser.romanised(devanagari) == typed)
        }
    }

    @Test("writes every consonant with every vowel sign as typed, in a closed first syllable")
    func consonantWithEveryVowelSign() {
        for (consonant, consonantTyped) in Self.consonants {
            for (sign, vowelTyped) in Self.closedVowels {
                Self.check(consonant + sign + "ल", consonantTyped + vowelTyped + "l")
            }
        }
    }

    @Test(
        "writes each sound class as typed",
        arguments: classes.keys.sorted())
    func soundClass(name: String) {
        for (devanagari, typed) in Self.classes[name] ?? [] { Self.check(devanagari, typed) }
    }

    @Test("drops the unwritten vowel where people drop it")
    func unwrittenVowel() {
        for (devanagari, typed) in Self.silentVowels { Self.check(devanagari, typed) }
    }

    @Test("lists only gaps that are cases in the audit")
    func gapsAreAudited() {
        let audited = Set(Self.classes.values.flatMap { $0.map(\.0) } + Self.silentVowels.map(\.0))
        #expect(Self.knownGaps.subtracting(audited).isEmpty)
    }
}

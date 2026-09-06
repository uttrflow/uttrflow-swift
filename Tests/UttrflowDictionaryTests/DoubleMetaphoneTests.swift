// Tests for the phonetic codes.

import Testing

@testable import UttrflowDictionary

/// Both codes of a word as one string, so an expectation reads like the sound it asserts.
private func sound(_ word: String) -> String {
    let code = DoubleMetaphone.code(for: word)
    return code.primary == code.alternate ? code.primary : "\(code.primary)|\(code.alternate)"
}

@Suite("How a word sounds")
struct DoubleMetaphoneTests {
    // MARK: The words this product exists for

    /// The headline case: a recogniser writes down an ordinary word, and all three must key the same.
    @Test("hears Claude, clawed and cloud as one sound")
    func theNameThisIsFor() {
        #expect(sound("Claude") == "KLT")
        #expect(sound("clawed") == "KLT")
        #expect(sound("cloud") == "KLT")
    }

    /// A name whose spelling and pronunciation disagree; colliding with "nickel" is correct.
    @Test("hears Nikhil, Nikhel and nickel as one sound")
    func namesSpeltByEar() {
        #expect(sound("Nikhil") == "NKL")
        #expect(sound("Nikhel") == "NKL")
        #expect(sound("nickel") == "NKL")
    }

    /// Five sounds go in and five come out; the product name is where truncation would hurt most.
    @Test("keeps a whole product name")
    func productName() {
        #expect(sound("Uttrflow") == "ATRFL")
        // Written closed, spoken open, and misheard as two words. All the same sounds.
        #expect(sound("utterflow") == "ATRFL")
        #expect(sound("utter flow") == "ATRFL")
    }

    /// Identifiers are written closed and spoken open, and the code must not care about the spaces.
    @Test("hears a camel-cased identifier and the phrase it is spoken as identically")
    func identifiersAreSpokenAsPhrases() {
        #expect(sound("PaymentSheet") == sound("payment sheet"))
        #expect(sound("setUserPrefs") == sound("set user prefs"))
        #expect(sound("PaymentSheet") == "PMNTXT")
        #expect(sound("setUserPrefs") == "STSRPRFS")
    }

    /// Technical terms nobody pronounces as written, and what a recogniser puts on the page instead.
    @Test("hears technical terms as the words they are mistaken for")
    func technicalTerms() {
        #expect(sound("kubectl") == "KPKTL")
        #expect(sound("kubectl") == sound("cube cattle"))
        #expect(sound("PostgreSQL") == "PSTKRSKL")
        #expect(sound("PostgreSQL") == sound("postgres QL"))
    }

    /// Four characters is where Soundex stops, and these two would be one key.
    @Test("keeps two long identifiers apart")
    func longIdentifiersStayDistinct() {
        #expect(sound("setUserPrefs") != sound("setUserPrompts"))
        #expect(sound("PaymentSheet") != sound("PostgreSQL"))
    }

    // MARK: Openings

    @Test("drops the letter an opening does not say")
    func silentOpenings() {
        #expect(sound("gnome") == "NM")
        #expect(sound("knife") == "NF")
        #expect(sound("pneumatic") == "NMTK")
        #expect(sound("wrist") == "RST")
        #expect(sound("psychology") == "SXLJ|SKLK")
    }

    @Test("says an opening X as a Z")
    func openingX() {
        #expect(sound("Xavier") == "SFR")
        #expect(sound("X") == "S")
    }

    @Test("keeps the first vowel and no other")
    func onlyTheFirstVowelSurvives() {
        #expect(sound("occur") == "AKR")
        #expect(sound("edge") == "AJ")
        #expect(sound("Yolanda") == "ALNT")
        #expect(sound("banana") == "PNN")
    }

    // MARK: Consonants, one rule at a time

    @Test("collapses a doubled letter into the one sound it spells")
    func doubledLetters() {
        #expect(sound("ebb") == "AP")
        #expect(sound("off") == "AF")
        #expect(sound("hajj") == "HJ")
        #expect(sound("trekk") == "TRK")
        #expect(sound("tall") == "TL")
        #expect(sound("comm") == "KM")
        #expect(sound("inn") == "AN")
        #expect(sound("supp") == "SP")
        #expect(sound("suqq") == "SK")
        #expect(sound("purr") == "PR")
        #expect(sound("miss") == "MS")
        #expect(sound("mitt") == "MT")
        #expect(sound("revv") == "RF")
        #expect(sound("buzz") == "PS")
    }

    @Test("sounds a hard C, a soft C and the pairs that spell a K")
    func theLettersC() {
        #expect(sound("cat") == "KT")
        #expect(sound("cell") == "SL")
        #expect(sound("city") == "ST")
        #expect(sound("cynic") == "SNK")
        #expect(sound("back") == "PK")
        #expect(sound("blancmange") == "PLNKMNJ|PLNKMNK")
        #expect(sound("cinq") == "SNK")
        #expect(sound("accept") == "AKSPT")
        #expect(sound("occur") == "AKR")
        #expect(sound("special") == "SPXL")
    }

    /// CH is the pair English cannot make up its mind about, which is what the alternate code is for.
    @Test("offers both readings of CH, and hardens it before a consonant")
    func theLettersCH() {
        #expect(sound("Christmas") == "KRSTMS")
        #expect(sound("chair") == "XR|KR")
        #expect(sound("machine") == "MXN|MKN")
        #expect(sound("match") == "MX|MK")
    }

    @Test("sounds D, DG and DT")
    func theLetterD() {
        #expect(sound("dot") == "TT")
        #expect(sound("edge") == "AJ")
        #expect(sound("digit") == "TJT|TKT")
        #expect(sound("dodgy") == "TJ")
        #expect(sound("Wildt") == "ALT|FLT")
        #expect(sound("odd") == "AT")
    }

    @Test("sounds a G, silences it where English does, and offers both where it cannot tell")
    func theLetterG() {
        #expect(sound("ghost") == "KST")
        #expect(sound("Pittsburgh") == "PTSPRK")
        #expect(sound("Bagh") == "P")
        #expect(sound("night") == "NT")
        #expect(sound("sign") == "SN")
        #expect(sound("signed") == "SNT")
        #expect(sound("magnetic") == "MKNTK")
        #expect(sound("egg") == "AK")
        #expect(sound("gem") == "JM|KM")
        #expect(sound("get") == "JT|KT")
        #expect(sound("gym") == "JM|KM")
        #expect(sound("gap") == "KP")
    }

    /// "Nikhil" has an H behind a K that nobody pronounces; sounding it would split it from "nickel".
    @Test("only sounds an H a vowel leans on")
    func theLetterH() {
        #expect(sound("hat") == "HT")
        #expect(sound("ahead") == "AHT")
        #expect(sound("Nikhil") == "NKL")
        #expect(sound("oh") == "A")
    }

    @Test("sounds PH as an F")
    func theLetterP() {
        #expect(sound("phone") == "FN")
        #expect(sound("pat") == "PT")
        #expect(sound("Campbell") == "KMPL")
    }

    @Test("tells the German SCH from the Greek one, and hears SH and SI")
    func theLetterS() {
        #expect(sound("school") == "SKL")
        #expect(sound("scherzo") == "SKRS")
        #expect(sound("schmuck") == "XMK|SKMK")
        #expect(sound("Bosch") == "PX|PSK")
        #expect(sound("sheet") == "XT")
        #expect(sound("vision") == "FXN|FSN")
        #expect(sound("Asia") == "AX|AS")
        #expect(sound("sat") == "ST")
    }

    @Test("borrows a digit for the sound English has no letter for")
    func theLetterT() {
        #expect(sound("nation") == "NXN")
        #expect(sound("partial") == "PRXL")
        #expect(sound("Thomas") == "0MS|TMS")
        #expect(sound("match") == "MX|MK")
        #expect(sound("Rutt") == "RT")
        #expect(sound("Rutdorf") == "RTRF")
        #expect(sound("tap") == "TP")
    }

    /// A W in the middle of a word makes no sound, which is why "clawed" reaches "Claude".
    @Test("says an opening W and swallows every other one")
    func theLetterW() {
        #expect(sound("water") == "ATR|FTR")
        #expect(sound("white") == "AT")
        #expect(sound("wrist") == "RST")
        // A silent W before an R is not only an opening: it turns up in compounds too.
        #expect(sound("handwritten") == "HNTRTN")
        #expect(sound("clawed") == "KLT")
        #expect(sound("wnuk") == "NK")
    }

    @Test("sounds X as KS and ZH as a J")
    func theLettersXAndZ() {
        #expect(sound("box") == "PKS")
        #expect(sound("excel") == "AKSL")
        #expect(sound("Zhang") == "JNK")
        #expect(sound("zoo") == "S")
    }

    // MARK: Nothing to say

    /// Digits, punctuation and accents make no sound and no key.
    @Test("makes no sound out of anything that is not a letter")
    func silence() {
        #expect(DoubleMetaphone.code(for: "").isSilent)
        #expect(DoubleMetaphone.code(for: "2024").isSilent)
        #expect(DoubleMetaphone.code(for: "!!!").isSilent)
        #expect(sound("café") == sound("cafe"))
        #expect(sound("H.264") == "")
    }

    // MARK: What the index is given

    @Test("files an unambiguous word under one key and an ambiguous one under both")
    func keys() {
        #expect(DoubleMetaphone.code(for: "Claude").keys == ["KLT"])
        #expect(DoubleMetaphone.code(for: "gem").keys == ["JM", "KM"])
        #expect(DoubleMetaphone.code(for: "2024").keys.isEmpty)
    }

    /// Two spellings that sound alike must be one hash key, not two equal strings.
    @Test("is a value, so equal sounds are one hash key")
    func codesAreValues() {
        #expect(DoubleMetaphone.code(for: "Claude") == DoubleMetaphone.code(for: "clawed"))
        #expect(
            Set([DoubleMetaphone.code(for: "Claude"), DoubleMetaphone.code(for: "cloud")]).count == 1)
        #expect(PhoneticCode(primary: "KLT", alternate: "KLT") == DoubleMetaphone.code(for: "cloud"))
    }
}

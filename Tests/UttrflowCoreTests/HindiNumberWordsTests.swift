import Testing

import UttrflowCore

/// `NumberWords.hindi` is the one table of Hindi numerals, magnitudes and fraction words.
@Suite("HindiNumberWords")
struct HindiNumberWordsTests {
    /// Each numeral 0 to 100 in Devanagari, the spelling the romaniser writes for it, and one other spelling people type.
    static let numerals: [(devanagari: String, variant: String)] = [
        ("शून्य", "shunya"), ("एक", "ek"), ("दो", "do"), ("तीन", "tin"), ("चार", "char"), ("पाँच", "panch"),
        ("छह", "chhe"), ("सात", "sat"), ("आठ", "ath"), ("नौ", "nau"), ("दस", "das"), ("ग्यारह", "gyarah"),
        ("बारह", "barah"), ("तेरह", "terah"), ("चौदह", "chaudah"), ("पंद्रह", "pandrah"), ("सोलह", "solah"),
        ("सत्रह", "satrah"), ("अठारह", "athaarah"), ("उन्नीस", "unnis"), ("बीस", "bis"), ("इक्कीस", "ikkees"),
        ("बाईस", "baees"), ("तेईस", "teees"), ("चौबीस", "chaubees"), ("पच्चीस", "pachchis"), ("छब्बीस", "chhabbees"),
        ("सत्ताईस", "sattaees"), ("अट्ठाईस", "atthaees"), ("उनतीस", "untees"), ("तीस", "tees"), ("इकतीस", "iktees"),
        ("बत्तीस", "battees"), ("तैंतीस", "taintees"), ("चौंतीस", "chauntees"), ("पैंतीस", "paintees"),
        ("छत्तीस", "chhattees"), ("सैंतीस", "saintees"), ("अड़तीस", "adtees"), ("उनतालीस", "untalees"),
        ("चालीस", "chalis"), ("इकतालीस", "iktalees"), ("बयालीस", "bayalees"), ("तैंतालीस", "taintalees"),
        ("चवालीस", "chawalees"), ("पैंतालीस", "paintalees"), ("छियालीस", "chhiyalees"), ("सैंतालीस", "saintalees"),
        ("अड़तालीस", "adtalees"), ("उनचास", "unchaas"), ("पचास", "pachas"), ("इक्यावन", "ikyawan"), ("बावन", "baawan"),
        ("तिरपन", "tirpan"), ("चौवन", "chauwan"), ("पचपन", "pachpan"), ("छप्पन", "chhappan"),
        ("सत्तावन", "sattawan"),
        ("अट्ठावन", "atthawan"), ("उनसठ", "unsath"), ("साठ", "saath"), ("इकसठ", "iksath"), ("बासठ", "baasath"),
        ("तिरसठ", "tirsath"), ("चौंसठ", "chaunsath"), ("पैंसठ", "painsath"), ("छियासठ", "chhiyasath"),
        ("सड़सठ", "sadsath"), ("अड़सठ", "adsath"), ("उनहत्तर", "unahattar"), ("सत्तर", "sattar"),
        ("इकहत्तर", "ikahattar"), ("बहत्तर", "bahattar"), ("तिहत्तर", "tihattar"), ("चौहत्तर", "chauhattar"),
        ("पचहत्तर", "pachahattar"), ("छिहत्तर", "chhihattar"), ("सतहत्तर", "satahattar"), ("अठहत्तर", "athahattar"),
        ("उन्यासी", "unyasi"), ("अस्सी", "assi"), ("इक्यासी", "ikyasi"), ("बयासी", "bayasi"), ("तिरासी", "tirasi"),
        ("चौरासी", "chaurasi"), ("पचासी", "pachasi"), ("छियासी", "chhiyasi"), ("सत्तासी", "sattasi"),
        ("अट्ठासी", "atthasi"), ("नवासी", "nawasi"), ("नब्बे", "nabbe"), ("इक्यानवे", "ikyaanve"), ("बानवे", "baanve"),
        ("तिरानवे", "tiraanve"), ("चौरानवे", "chauraanve"), ("पचानवे", "pachaanve"), ("छियानवे", "chhiyaanve"),
        ("सत्तानवे", "sattaanve"), ("अट्ठानवे", "atthaanve"), ("निन्यानवे", "ninyaanve"), ("सौ", "sau"),
    ]

    @Test("every numeral 0 to 100 is in the table in both scripts and a typed variant")
    func everyNumeralInBothScripts() {
        #expect(Self.numerals.count == 101)
        for (value, numeral) in Self.numerals.enumerated() {
            let romanised = Romaniser.romanised(numeral.devanagari)
            #expect(NumberWords.hindi[numeral.devanagari] == value, "\(numeral.devanagari)")
            #expect(NumberWords.hindi[romanised] == value, "\(romanised)")
            #expect(NumberWords.hindi[numeral.variant] == value, "\(numeral.variant)")
        }
    }

    @Test("the magnitudes and fraction words carry their values")
    func magnitudesAndFractions() {
        for word in ["हज़ार", "lakh", "करोड़"] { #expect(NumberWords.hindi[Romaniser.romanised(word)] != nil) }
        #expect(NumberWords.hindi["lakh"] == 100_000)
        #expect(NumberWords.hindi["crore"] == 10_000_000)
        #expect(NumberWords.hindiFractions["dedh"]?.value == 1.5)
        #expect(NumberWords.hindiFractions["dhai"]?.value == 2.5)
        #expect(NumberWords.hindiFractions[Romaniser.romanised("साढ़े")]?.isOffset == true)
        #expect(NumberWords.hindiFractions["paune"]?.value == -0.25)
    }

    @Test(
        "reads a Hindi cardinal through its hundreds and scales",
        arguments: [
            (["paanch", "sau"], 500, 2), (["do", "hazaar", "paanch", "sau"], 2500, 4),
            (["dhai"], nil, 0), (["sau"], 100, 1), (["ek", "lakh", "pachas", "hazaar"], 150_000, 4),
            (["teen", "crore"], 30_000_000, 2), (["do", "sau", "pachas"], 250, 3),
            (["hazaar", "lakh"], 1000, 1),
            (["bees", "teen"], 20, 1), (["shunya", "ek"], 0, 1),
        ] as [([String], Int?, Int)]
    )
    func hindiCardinal(keys: [String], value: Int?, count: Int) {
        let read = NumberWords.hindiCardinal(keys[...])
        #expect(read?.value == value)
        #expect((read?.count ?? 0) == count)
    }
}

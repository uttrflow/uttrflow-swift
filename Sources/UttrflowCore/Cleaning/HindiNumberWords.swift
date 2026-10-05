/// The Hindi number words and the one view every consumer reads both languages through.
extension NumberWords {
    /// Hindi numerals 0 to 100 and the magnitudes, in Devanagari, the romaniser's spelling and the variants people type.
    public static let hindi: [String: Int] = [
        "शून्य": 0, "shoonya": 0, "shunya": 0,
        "एक": 1, "ek": 1,
        "दो": 2, "do": 2,
        "तीन": 3, "teen": 3, "tin": 3,
        "चार": 4, "chaar": 4, "char": 4,
        "पाँच": 5, "पांच": 5, "paanch": 5, "panch": 5,
        "छह": 6, "छे": 6, "chhah": 6, "chhe": 6, "chah": 6, "che": 6,
        "सात": 7, "saat": 7, "sat": 7,
        "आठ": 8, "aath": 8, "ath": 8,
        "नौ": 9, "nau": 9,
        "दस": 10, "das": 10,
        "ग्यारह": 11, "gyaarah": 11, "gyarah": 11,
        "बारह": 12, "baarah": 12, "barah": 12,
        "तेरह": 13, "terah": 13,
        "चौदह": 14, "chaudah": 14,
        "पंद्रह": 15, "pandrah": 15,
        "सोलह": 16, "solah": 16,
        "सत्रह": 17, "satrah": 17,
        "अठारह": 18, "atharah": 18, "athaarah": 18,
        "उन्नीस": 19, "unnees": 19, "unnis": 19,
        "बीस": 20, "bees": 20, "bis": 20,
        "इक्कीस": 21, "ikkees": 21,
        "बाईस": 22, "baees": 22,
        "तेईस": 23, "teees": 23,
        "चौबीस": 24, "chaubees": 24,
        "पच्चीस": 25, "pacchees": 25, "pachchis": 25, "pachis": 25,
        "छब्बीस": 26, "chhabbees": 26,
        "सत्ताईस": 27, "sattaees": 27,
        "अट्ठाईस": 28, "atthaees": 28,
        "उनतीस": 29, "untees": 29,
        "तीस": 30, "tees": 30,
        "इकतीस": 31, "iktees": 31,
        "बत्तीस": 32, "battees": 32,
        "तैंतीस": 33, "taintees": 33,
        "चौंतीस": 34, "chauntees": 34,
        "पैंतीस": 35, "paintees": 35,
        "छत्तीस": 36, "chhattees": 36,
        "सैंतीस": 37, "saintees": 37,
        "अड़तीस": 38, "adtees": 38,
        "उनतालीस": 39, "untalees": 39,
        "चालीस": 40, "chaalees": 40, "chalis": 40,
        "इकतालीस": 41, "iktalees": 41,
        "बयालीस": 42, "bayalees": 42,
        "तैंतालीस": 43, "taintalees": 43,
        "चवालीस": 44, "chawalees": 44,
        "पैंतालीस": 45, "paintalees": 45,
        "छियालीस": 46, "chhiyalees": 46,
        "सैंतालीस": 47, "saintalees": 47,
        "अड़तालीस": 48, "adtalees": 48,
        "उनचास": 49, "unchaas": 49,
        "पचास": 50, "pachaas": 50, "pachas": 50,
        "इक्यावन": 51, "ikyawan": 51,
        "बावन": 52, "baawan": 52,
        "तिरपन": 53, "tirpan": 53,
        "चौवन": 54, "chauwan": 54,
        "पचपन": 55, "pachpan": 55,
        "छप्पन": 56, "chhappan": 56,
        "सत्तावन": 57, "sattawan": 57,
        "अट्ठावन": 58, "atthawan": 58,
        "उनसठ": 59, "unsath": 59,
        "साठ": 60, "saath": 60,
        "इकसठ": 61, "iksath": 61,
        "बासठ": 62, "baasath": 62,
        "तिरसठ": 63, "tirsath": 63,
        "चौंसठ": 64, "chaunsath": 64,
        "पैंसठ": 65, "painsath": 65,
        "छियासठ": 66, "chhiyasath": 66,
        "सड़सठ": 67, "sadsath": 67,
        "अड़सठ": 68, "adsath": 68,
        "उनहत्तर": 69, "unahattar": 69,
        "सत्तर": 70, "sattar": 70,
        "इकहत्तर": 71, "ikahattar": 71,
        "बहत्तर": 72, "bahattar": 72,
        "तिहत्तर": 73, "tihattar": 73,
        "चौहत्तर": 74, "chauhattar": 74,
        "पचहत्तर": 75, "pachahattar": 75,
        "छिहत्तर": 76, "chhihattar": 76,
        "सतहत्तर": 77, "satahattar": 77,
        "अठहत्तर": 78, "athahattar": 78,
        "उन्यासी": 79, "unyasi": 79,
        "अस्सी": 80, "assi": 80,
        "इक्यासी": 81, "ikyasi": 81,
        "बयासी": 82, "bayasi": 82,
        "तिरासी": 83, "tirasi": 83,
        "चौरासी": 84, "chaurasi": 84,
        "पचासी": 85, "pachasi": 85,
        "छियासी": 86, "chhiyasi": 86,
        "सत्तासी": 87, "sattasi": 87,
        "अट्ठासी": 88, "atthasi": 88,
        "नवासी": 89, "nawasi": 89,
        "नब्बे": 90, "nabbe": 90,
        "इक्यानवे": 91, "ikyaanve": 91,
        "बानवे": 92, "baanve": 92,
        "तिरानवे": 93, "tiraanve": 93,
        "चौरानवे": 94, "chauraanve": 94,
        "पचानवे": 95, "pachaanve": 95,
        "छियानवे": 96, "chhiyaanve": 96,
        "सत्तानवे": 97, "sattaanve": 97,
        "अट्ठानवे": 98, "atthaanve": 98,
        "निन्यानवे": 99, "ninyaanve": 99,
        "सौ": 100, "sau": 100,
        "हज़ार": 1_000, "हजार": 1_000, "hazaar": 1_000, "hazar": 1_000,
        "लाख": 100_000, "lakh": 100_000, "laakh": 100_000,
        "करोड़": 10_000_000, "crore": 10_000_000, "karod": 10_000_000,
    ]

    /// Hindi fraction words by value, absolute ("dedh" 1.5) or an offset to the number after them ("sawa" +0.25).
    public static let hindiFractions: [String: (value: Double, isOffset: Bool)] = [
        "डेढ़": (1.5, false), "dedh": (1.5, false), "derh": (1.5, false),
        "ढाई": (2.5, false), "dhai": (2.5, false), "dhaai": (2.5, false),
        "सवा": (0.25, true), "sawa": (0.25, true), "sava": (0.25, true),
        "साढ़े": (0.5, true), "saadhe": (0.5, true), "saade": (0.5, true), "sade": (0.5, true),
        "पौने": (-0.25, true), "paune": (-0.25, true), "pone": (-0.25, true),
    ]

    /// Hindi number words as often an ordinary word: "एक" also "a", "दो" also "give", "saath" also "with".
    public static let hindiHomographs: Set<String> = ["एक", "दो", "ek", "do", "saath"]

    /// Reads the longest Hindi cardinal at the start of `keys`, as "do hazaar paanch sau" for 2500, saying how many words it used.
    public static func hindiCardinal(_ keys: ArraySlice<String>) -> (value: Int, count: Int)? {
        var total = 0
        var group = 0
        var hasUnits = false
        var hasHundred = false
        var lastScale = Int.max
        var consumed = 0
        for key in keys {
            guard let value = hindi[key] else { break }
            if value == 0 {
                if consumed == 0 { consumed = 1 }
                break
            } else if value < 100 {
                if hasUnits { break }
                group += value
                hasUnits = true
            } else if value == 100 {
                if hasHundred || (group == 0 && consumed > 0) { break }
                group = max(group, 1) * 100
                hasHundred = true
                hasUnits = false
            } else {
                if value >= lastScale || (group == 0 && consumed > 0) { break }
                total += max(group, 1) * value
                group = 0
                hasUnits = false
                hasHundred = false
                lastScale = value
            }
            consumed += 1
        }
        guard consumed > 0 else { return nil }
        return (total + group, consumed)
    }

    /// Every English number word by value, the units, teens, tens and scales together.
    public static var english: [String: Int] {
        units.merging(teens) { first, _ in first }.merging(tens) { first, _ in first }
            .merging(scales) { first, _ in first }
    }
}

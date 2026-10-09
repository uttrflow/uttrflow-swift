import Testing

@testable import UttrflowCore

@Suite("Romanised Hindi word classes, one data table")
struct HindiWordsTests {
    @Test("every word of the old code tables is a row with its class")
    func oldTablesAreRows() {
        let negations = ["nahi", "nahin", "nahee", "na", "mat"]
        let stems = [
            "aa", "a", "ja", "kar", "kh", "de", "le", "ho", "bol", "chal", "mil", "dekh", "sun", "likh",
            "padh", "bhej", "bata", "samajh", "rakh", "uth", "baith", "so", "pi", "ban", "mang", "khel",
            "khil", "la", "pa", "nikal", "dikh",
        ]
        let pronouns = [
            "yah", "yeh", "ye", "is", "in", "ise", "inhe", "vah", "woh", "wo", "us", "un", "use", "unhe",
        ]
        for word in negations { #expect(HindiWords.classes(of: word).contains(.negation), "\(word)") }
        for word in stems { #expect(HindiWords.verbStems.contains(Romaniser.soundKey(word)), "\(word)") }
        for word in pronouns { #expect(HindiWords.classes(of: word).contains(.pronoun), "\(word)") }
        for (spelling, word) in [
            ("he", "hai"), ("nahin", "nahi"), ("kr", "kar"), ("me", "mein"), ("yeh", "ye"),
        ] {
            #expect(HindiWords.spellingKey(of: spelling) == word, "\(spelling)")
        }
    }

    @Test("every grammar word the script guard held in code is a row with a grammar class")
    func guardGrammarWordsAreRows() {
        let words = [
            "hai", "hain", "hoon", "hun", "tha", "thi", "the", "raha", "rahi", "rahe",
            "ko", "ka", "ki", "ke", "se", "mein", "par", "ne", "to", "toh", "bhi", "hi",
        ]
        for word in words { #expect(HindiWords.grammarWords.contains(Romaniser.soundKey(word)), "\(word)") }
        for word in ["nahi", "yah", "kar", "aur"] {
            #expect(!HindiWords.grammarWords.contains(Romaniser.soundKey(word)), "\(word)")
        }
    }

    @Test("demonstrative cases group under the pronoun they are")
    func pronounCases() {
        #expect(HindiWords.pronounCases[Romaniser.soundKey("ise")] == "yah")
        #expect(HindiWords.pronounCases[Romaniser.soundKey("woh")] == "vah")
    }

    @Test("Hindi function words count as small words; spellings English uses as content words do not")
    func functionWords() {
        for word in ["usko", "usne", "tum", "nahi", "hai", "ko", "aur", "kya"] {
            #expect(FunctionWords.holds(word), "\(word)")
        }
        for word in ["main", "use", "bol", "chalo"] {
            #expect(!HindiWords.functionWords.contains(word), "\(word)")
        }
    }

    @Test("the table loads from the bundle and every row is Latin")
    func bundledAndLatin() {
        #expect(HindiWords.table.source == .bundled)
        for row in HindiWords.table.rows {
            #expect(row.id.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isLowercase }, "\(row.id)")
            #expect(!row.classes.isEmpty, "\(row.id)")
        }
    }
}

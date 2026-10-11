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

    @Test("every word of QuestionShape's old Hindi verb, copula and embedding tables is a row with its class")
    func questionShapeWordsAreRows() {
        let closing = ["hai", "hain", "ho", "hoon", "tha", "thi", "the", "hoga", "hogi", "honge"]
        let finite =
            closing + [
                "hu", "h", "hua", "hui", "hue", "gaya", "gayi", "gaye", "di", "dia", "diya", "kiye", "kiya",
                "ki", "li", "lia", "liya", "kar", "karta", "karte", "karti", "karoge", "karogi", "karega",
                "karegi", "karunga", "karungi", "karna", "chahiye", "sakte", "sakti", "sakta",
            ]
        let copulas = ["hai", "hain", "ho", "hoga"]
        let embedding = [
            "ki", "pata", "kaha", "bola", "pucha", "poocha", "bataya", "batayi", "bataye", "batao", "yaad",
            "dekh", "dekha", "dekho", "maloom", "malum", "samajh", "samjha", "samjho", "suna", "socha",
        ]
        #expect(HindiWords.spellings(of: .closingVerb) == Set(closing))
        #expect(HindiWords.spellings(of: .finiteVerb) == Set(finite))
        #expect(HindiWords.spellings(of: .questionCopula) == Set(copulas))
        #expect(HindiWords.spellings(of: .embeddingWord) == Set(embedding))
    }

    @Test("a word listed only for question shape is not a grammar word, a function word or a Hindi spelling")
    func shapeClassesStayPrivate() {
        for word in ["hua", "gayi", "pata", "karoge", "li"] {
            #expect(HindiWords.classes(of: word).isEmpty, "\(word)")
            #expect(!HindiWords.functionWords.contains(word), "\(word)")
            #expect(!HindiWords.spellings.contains(word), "\(word)")
            #expect(HindiWords.spellingKey(of: word) == nil, "\(word)")
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

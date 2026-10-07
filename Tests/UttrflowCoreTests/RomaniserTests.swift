import Testing

@testable import UttrflowCore

@Suite("Romaniser")
struct RomaniserTests {
    @Test(
        "writes the common words the way people type them",
        arguments: [
            ("हाँ ठीक है", "haan thik hai"), ("हां ठीक है", "haan thik hai"), ("मैं अभी आता हूँ", "main abhi aata hoon"),
            ("नहीं", "nahi"), ("क्या", "kya"), ("क्यों", "kyun"), ("मैं आ रहा हूं", "main aa raha hoon"),
            ("कोई बात नहीं", "koi baat nahi"), ("अच्छा", "accha"), ("धन्यवाद", "dhanyavaad"), ("ज़रा", "zara"),
            ("ऑफिस", "office"), ("मिनट", "minute"),
            ("फ़ाइल", "file"), ("फाइल", "file"), ("शेयर", "share"), ("कंप्यूटर", "computer"),
            ("लड़का", "ladka"),
            ("डेडलाइन", "deadline"), ("मोबाइल", "mobile"), ("चार्ज", "charge"), ("स्कूल", "school"),
            ("डॉक्टर", "doctor"), ("बैंक", "bank"), ("कॉलेज", "college"), ("टैक्सी", "taxi"),
            ("बुक", "book"), ("लैपटॉप", "laptop"), ("इंटरनेट", "internet"), ("पासवर्ड", "password"),
            ("वीडियो", "video"), ("कॉल", "call"), ("फ़ोटो", "photo"), ("फोटो", "photo"),
            ("ऑफ़र", "offer"), ("ऑफर", "offer"), ("कॉपी", "copy"), ("कॉन्टैक्ट", "contact"),
            ("लॉगिन", "login"), ("लॉगआउट", "logout"), ("प्रॉब्लम", "problem"), ("बॉक्स", "box"),
            ("कॉफ़ी", "coffee"), ("कॉफी", "coffee"),
        ])
    func commonSpellings(devanagari: String, typed: String) {
        #expect(Romaniser.romanised(devanagari) == typed)
    }

    @Test(
        "drops the unwritten vowel at the end of a word and between syllables, and keeps it before a conjunct",
        arguments: [
            ("करना", "karna"), ("समझना", "samajhna"), ("निकलने", "nikalne"), ("भागदौड़", "bhaagdaud"),
            ("सड़क", "sadak"), ("कृपया", "kripya"), ("अनन्या", "ananya"),
            ("विक्रम", "vikram"), ("अगस्त", "agast"), ("दोस्त", "dost"), ("मित्र", "mitra"), ("दिल्ली", "dilli"),
            ("घर", "ghar"),
        ])
    func silentVowels(devanagari: String, typed: String) {
        #expect(Romaniser.romanised(devanagari) == typed)
    }

    @Test(
        "keeps the inherent vowel after a nasal syllable",
        arguments: [
            ("ज़िंदगी", "zindagi"), ("इंतज़ार", "intezaar"), ("इंतजार", "intezaar"),
            ("संपादक", "sampadak"),
        ])
    func vowelAfterNasalSyllable(devanagari: String, typed: String) {
        #expect(Romaniser.romanised(devanagari) == typed)
    }

    @Test(
        "writes long vowels, nasals and clusters without diacritics",
        arguments: [
            ("किताब", "kitaab"), ("बताया", "bataya"), ("पूरा", "poora"), ("चीज़", "cheez"), ("दूँगा", "dunga"),
            ("कुर्सियाँ", "kursiyan"), ("मिलेंगे", "milenge"), ("हमें", "hamein"), ("उन्होंने", "unhone"),
            ("मैंने", "maine"), ("पहुँच", "pahunch"), ("बच्चा", "baccha"), ("ज्ञान", "gyaan"), ("क्षमा", "kshama"),
            ("गाँव", "gaon"), ("पाँव", "paon"), ("छाँव", "chhaon"), ("गाँवों", "gaonon"),
            ("गाव", "gaav"), ("कार्य", "karya"), ("मित्र", "mitra"),
            ("वजह", "wajah"), ("पहले", "pehle"), ("आए", "aaye"), ("लीजिए", "lijiye"),
            ("दुःख", "duhkh"), ("सफ़र", "safar"), ("क़िला", "qila"), ("ॐ", "om"), ("जगत्", "jagat"),
            ("न", "na"), ("आ", "aa"),
        ])
    func vowelsAndClusters(devanagari: String, typed: String) {
        #expect(Romaniser.romanised(devanagari) == typed)
    }

    @Test(
        "writes Devanagari digits and stops as Latin ones, and leaves Latin text and spacing alone",
        arguments: [
            ("१२३", "123"), ("है।", "hai."), ("है।.", "hai."), ("है॥", "hai."),
            ("है।।", "hai."), ("है!।", "hai!"), ("है।ठीक", "hai. thik"), ("है।\"", "hai.\""),
            ("कल का deploy हो गया", "kal ka deploy ho gaya"),
            ("PR भेज दूँगा, ok?", "PR bhej dunga, ok?"), ("ठीक\nहै", "thik\nhai"),
            ("so I'll be offline", "so I'll be offline"),
            ("नमस्ते 👋", "namaste 👋"), ("सोऽहम्", "soham"),
        ])
    func textAround(devanagari: String, typed: String) {
        #expect(Romaniser.romanised(devanagari) == typed)
    }

    @Test("reads a letter with its nukta built in as the letter and the nukta, and a joiner as nothing")
    func variantEncodings() {
        #expect(
            Romaniser.romanised("\u{095B}\u{0930}\u{093E}")
                == Romaniser.romanised("\u{091C}\u{093C}\u{0930}\u{093E}"))
        #expect(Romaniser.romanised("\u{0915}\u{094D}\u{200D}\u{092F}\u{093E}") == "kya")
        #expect(Romaniser.romanised("\u{093E}") == "")
    }

    @Test("capitalises a romanised word only where it opens a sentence")
    func capitalises() {
        #expect(
            Romaniser.romanised("हाँ ठीक है। कल मिलते हैं", capitalisingSentences: true)
                == "Haan thik hai. Kal milte hain")
        #expect(Romaniser.romanised("Okay, कल मिलते हैं", capitalisingSentences: true) == "Okay, kal milte hain")
        #expect(Romaniser.romanised("  ठीक", capitalisingSentences: true) == "  Thik")
    }

    @Test("romanises long mixed-script text without changing sentence capitalization")
    func longMixedScriptText() {
        let devanagari = "कल"
        let input = Array(repeating: "English \(devanagari) sentence. ", count: 2_000).joined()
        let expected = Array(repeating: "English kal sentence. ", count: 2_000).joined()

        #expect(Romaniser.romanised(input, capitalisingSentences: true) == expected)
    }

    /// No letter of the block may survive, whatever it sits next to.
    @Test("never leaves a Devanagari scalar behind, for any scalar of the block alone or after a consonant")
    func noDevanagariSurvives() {
        for value in UInt32(0x0900)...0x097F {
            guard let scalar = Unicode.Scalar(value) else { continue }
            for text in [
                String(Character(scalar)), "क" + String(Character(scalar)),
                "क\u{094D}" + String(Character(scalar)) + "ा",
            ] {
                #expect(
                    !Romaniser.containsDevanagari(Romaniser.romanised(text)), "U+\(String(value, radix: 16))")
            }
        }
    }

    @Test(
        "folds common spelling variants to one key, and keeps different words apart",
        arguments: [
            ("theek", "thik"), ("woh", "wo"), ("hoon", "hun"), ("phir", "fir"), ("Mein", "men"),
            ("accha", "acha"),
        ])
    func soundKeysMeet(first: String, second: String) {
        #expect(Romaniser.soundKey(first) == Romaniser.soundKey(second))
    }

    @Test(
        "keeps apart words that only look alike",
        arguments: [("hai", "hain"), ("four", "chaar"), ("is", "hai"), ("h", "")])
    func soundKeysDiffer(first: String, second: String) {
        #expect(Romaniser.soundKey(first) != Romaniser.soundKey(second))
    }

    /// पहुँच and पहुंच are the same word, one written with chandrabindu and one with anusvara.
    @Test("folds chandrabindu to anusvara and drops nukta, so spelling variants share a form")
    func scriptFoldedMergesVariants() {
        #expect(
            Romaniser.scriptFolded("\u{092A}\u{0939}\u{0941}\u{0901}\u{091A}")
                == Romaniser.scriptFolded("\u{092A}\u{0939}\u{0941}\u{0902}\u{091A}"))
        #expect(Romaniser.scriptFolded("\u{0915}\u{093C}") == Romaniser.scriptFolded("\u{0915}"))
    }

    @Test("leaves a non-Devanagari spelling untouched")
    func scriptFoldedPassesOtherScriptsThrough() {
        #expect(Romaniser.scriptFolded("Uttrflow") == "Uttrflow")
    }

    @Test("romanises a transcription into a draft, keeping each word's confidence and its Devanagari origin")
    func romanisesTranscription() {
        let heard = Transcription(
            text: "हाँ ठीक है", detectedLanguage: DetectedLanguage(code: .hindi, confidence: 0.9),
            segments: [
                TranscriptionSegment(
                    text: "हाँ ठीक है", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: "हाँ", confidence: 0.4),
                        TranscribedWord(text: "ठीक", confidence: 1),
                        TranscribedWord(text: "है", confidence: 0.8),
                    ])
            ], audioDuration: .seconds(1))

        let draft = Draft(romanising: heard)

        #expect(draft.text == "haan thik hai")
        #expect(draft.words.map(\.confidence) == [0.4, 1, 0.8])
        #expect(draft.confidencesAreReal)
        #expect(draft.words.indices.allSatisfy(draft.isHindi(at:)))
        let english = Draft(romanising: Transcription(text: "hello there"))
        #expect(english == Draft(transcription: Transcription(text: "hello there")))
    }
}

@Suite("LatinScript")
struct LatinScriptTests {
    @Test(
        "counts Latin letters, accents, punctuation, digits, symbols and emoji as Latin text",
        arguments: [
            "Hello, world!", "Café naïve résumé", "“Quoted” — and ‘so’ on…", "3.5% of ₹1,50,000", "👍🏽 🇮🇳 ❤️ 1️⃣",
            "x² ≤ ½ ™ ℃", "", "ﬁnal", "Ⓐ",
        ])
    func latin(text: String) {
        #expect(LatinScript.isLatin(text))
        #expect(LatinScript.enforced(text) == text)
    }

    @Test(
        "counts any other script's letters as not Latin",
        arguments: ["है", "Привет", "مرحبا", "你好", "γεια", "a\u{0951}", "\u{1D6C2}"])
    func notLatin(text: String) {
        #expect(!LatinScript.isLatin(text))
    }

    @Test("counts Mathematical Latin letters as Latin, distinct from Mathematical Greek in the same block")
    func mathematicalLatinLetter() {
        #expect(LatinScript.isLatin("\u{1D400}"))
        #expect(LatinScript.enforced("\u{1D400}") == "\u{1D400}")
    }

    @Test("transliterates a Mathematical Greek letter rather than passing it through unchanged")
    func mathematicalGreekLetter() {
        let input = "\u{1D6C2}"  // MATHEMATICAL BOLD SMALL ALPHA
        #expect(!LatinScript.isLatin(input))
        let enforced = LatinScript.enforced(input)
        #expect(LatinScript.isLatin(enforced))
    }

    @Test("romanises Devanagari, capitalising a sentence it opens")
    func enforcesDevanagari() {
        #expect(LatinScript.enforced("हाँ ठीक है।") == "Haan thik hai.")
        #expect(LatinScript.enforced("Okay. कल मिलते हैं.") == "Okay. Kal milte hain.")
        #expect(LatinScript.enforced("१०") == "10")
        #expect(LatinScript.enforced("।") == ".")
    }

    @Test(
        "writes any other script in Latin letters, and never leaves one of its letters behind",
        arguments: ["Привет мир", "مرحبا بالعالم", "你好", "γεια σου", "٣ دقائق", "שלום", "ᚠᚢᚦ"])
    func enforcesOtherScripts(text: String) {
        let enforced = LatinScript.enforced(text)
        #expect(LatinScript.isLatin(enforced))
        #expect(!enforced.unicodeScalars.contains { LatinScript.westernDigit($0) != nil })
    }

    @Test("writes another script's digits as Western ones")
    func foreignDigits() {
        #expect(LatinScript.enforced("٣") == "3")
        #expect(LatinScript.westernDigit("7") == nil)
        #expect(LatinScript.westernDigit("x") == nil)
    }
    @Test(
        "treats a change between Latin and Devanagari inside a token as a word boundary",
        arguments: [
            ("PostgreSQLमें", "PostgreSQL mein"), ("PRभेज", "PR bhej"), ("मैंPR", "main PR"),
            ("PR-भेज", "PR-bhej"), ("PR'में", "PR'mein"), ("में-PR", "mein-PR"), ("PR में", "PR mein"),
            ("v2में", "v2 mein"),
        ])
    func scriptChangeIsBoundary(mixed: String, typed: String) {
        #expect(Romaniser.romanised(mixed) == typed)
    }

    @Test("leaves English text byte-identical")
    func englishUntouched() {
        let english = "PostgreSQL in v2, PR-sent; don't."
        #expect(Romaniser.romanised(english) == english)
    }
}

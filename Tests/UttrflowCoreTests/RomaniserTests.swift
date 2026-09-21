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
        "writes long vowels, nasals and clusters without diacritics",
        arguments: [
            ("किताब", "kitaab"), ("बताया", "bataya"), ("पूरा", "poora"), ("चीज़", "cheez"), ("दूँगा", "dunga"),
            ("कुर्सियाँ", "kursiyan"), ("मिलेंगे", "milenge"), ("हमें", "hamein"), ("उन्होंने", "unhone"),
            ("मैंने", "maine"), ("पहुँच", "pahunch"), ("बच्चा", "baccha"), ("ज्ञान", "gyaan"), ("क्षमा", "kshama"),
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

    @Test("romanises a transcription's text and timed words, keeping its timings and language")
    func romanisesTranscription() {
        let heard = Transcription(
            text: "हाँ ठीक है", detectedLanguage: DetectedLanguage(code: .hindi, confidence: 0.9),
            segments: [
                TranscriptionSegment(
                    text: "हाँ ठीक है", start: .zero, end: .seconds(1),
                    words: [
                        TranscribedWord(text: "हाँ", confidence: 0.4),
                        TranscribedWord(text: "ठीक", confidence: 1),
                    ])
            ], audioDuration: .seconds(1))

        let romanised = heard.romanised

        #expect(romanised.text == "haan thik hai")
        #expect(romanised.segments.first?.words.map(\.text) == ["haan", "thik"])
        #expect(romanised.segments.first?.words.first?.confidence == 0.4)
        #expect(romanised.segments.first?.end == .seconds(1))
        #expect(romanised.detectedLanguage == heard.detectedLanguage)
        #expect(romanised.audioDuration == heard.audioDuration)
        let english = Transcription(text: "hello there")
        #expect(english.romanised == english)
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
        arguments: ["है", "Привет", "مرحبا", "你好", "γεια", "a\u{0951}"])
    func notLatin(text: String) {
        #expect(!LatinScript.isLatin(text))
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
}

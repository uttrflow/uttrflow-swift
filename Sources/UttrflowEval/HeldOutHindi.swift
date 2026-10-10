import UttrflowCore

/// One invented Devanagari sentence kept back from the romaniser's table and rules, with the Latin spellings people wrote for it.
public struct HeldOutSentence: Sendable, Equatable {
    public let id: String
    public let devanagari: String
    /// Each written independently by someone who has not seen the romaniser's table; empty until written.
    public let references: [String]

    public init(id: String, devanagari: String, references: [String] = []) {
        self.id = id
        self.devanagari = devanagari
        self.references = references
    }
}

/// Word and character accuracy of a romanisation against one or more references per sentence.
public struct RomanisationScore: Sendable, Equatable {
    public let words: Double
    public let characters: Double

    /// Pooled over `pairs`, each scored against whichever of its references `romanise` comes closest to.
    public static func measure(
        _ pairs: [(devanagari: String, references: [String])],
        normaliser: TextNormaliser = .standard,
        romanise: (String) -> String
    ) -> RomanisationScore? {
        var wordErrors = 0
        var wordCount = 0
        var characterErrors = 0
        var characterCount = 0
        for pair in pairs where !pair.references.isEmpty {
            let hypothesis = normaliser.words(romanise(pair.devanagari))
            let scored = pair.references.map { text in
                let reference = normaliser.words(text)
                return (
                    words: WordErrorRate.measure(reference: reference, hypothesis: hypothesis),
                    characters: WordErrorRate.measure(
                        reference: reference.joined(separator: " ").map(String.init),
                        hypothesis: hypothesis.joined(separator: " ").map(String.init))
                )
            }
            guard
                let best = scored.min(by: {
                    Double($0.words.errors) / Double(max($0.words.referenceWordCount, 1))
                        < Double($1.words.errors) / Double(max($1.words.referenceWordCount, 1))
                })
            else { continue }
            wordErrors += best.words.errors
            wordCount += best.words.referenceWordCount
            characterErrors += best.characters.errors
            characterCount += best.characters.referenceWordCount
        }
        guard wordCount > 0, characterCount > 0 else { return nil }
        return RomanisationScore(
            words: 1 - Double(wordErrors) / Double(wordCount),
            characters: 1 - Double(characterErrors) / Double(characterCount))
    }
}

/// Devanagari sentences no rule, table entry or tuning passage was written against. See `Docs/latin-output.md`.
public enum HeldOutHindi {
    public static let all: [HeldOutSentence] = [
        HeldOutSentence(id: "ho-01", devanagari: "सुबह की चाय ठंडी हो गई, इसलिए मैंने दोबारा पानी गरम किया।"),
        HeldOutSentence(id: "ho-02", devanagari: "कल शाम बारिश इतनी तेज़ थी कि हम बस अड्डे पर ही रुक गए।"),
        HeldOutSentence(id: "ho-03", devanagari: "बच्चों ने आँगन में पतंग उड़ाई और छत से माँ ने आवाज़ दी।"),
        HeldOutSentence(id: "ho-04", devanagari: "दफ़्तर का कंप्यूटर फिर से धीमा चल रहा है, कोई देख सकता है क्या?"),
        HeldOutSentence(id: "ho-05", devanagari: "रविवार को बाज़ार में भीड़ कम होती है, तब सब्ज़ी लेने चलेंगे।"),
        HeldOutSentence(id: "ho-06", devanagari: "उसने चिट्ठी लिखी पर डाक में डालना भूल गया।"),
        HeldOutSentence(id: "ho-07", devanagari: "पंखा बंद कर दो, ठंड लग रही है और खिड़की भी खुली है।"),
        HeldOutSentence(id: "ho-08", devanagari: "हमारी गाड़ी पुरानी है लेकिन अब तक कभी रास्ते में ख़राब नहीं हुई।"),
        HeldOutSentence(id: "ho-09", devanagari: "परीक्षा के बाद सब दोस्त मिलकर पहाड़ों पर घूमने जाएँगे।"),
        HeldOutSentence(id: "ho-10", devanagari: "दादी ने कहा कि दूध में थोड़ी इलायची डालो, स्वाद अच्छा आएगा।"),
        HeldOutSentence(id: "ho-11", devanagari: "मेरा फ़ोन चार्ज नहीं हो रहा, शायद तार टूट गया है।"),
        HeldOutSentence(id: "ho-12", devanagari: "अगले हफ़्ते से दुकान सुबह नौ बजे खुलेगी और रात दस बजे बंद होगी।"),
        HeldOutSentence(id: "ho-13", devanagari: "किताब का आख़िरी अध्याय सबसे लंबा था, पर पढ़ने में मज़ा आया।"),
        HeldOutSentence(id: "ho-14", devanagari: "छोटे भाई ने अपना कमरा साफ़ किया और पुराने खिलौने बाँट दिए।"),
        HeldOutSentence(id: "ho-15", devanagari: "गर्मियों में हम नींबू पानी और ठंडा शरबत ज़्यादा पीते हैं।"),
        HeldOutSentence(id: "ho-16", devanagari: "डॉक्टर ने आराम करने को कहा है, इसलिए आज मैं घर से काम करूँगा।"),
        HeldOutSentence(id: "ho-17", devanagari: "बगीचे में गुलाब के नए पौधे लगाए हैं, अगले महीने फूल आएँगे।"),
        HeldOutSentence(id: "ho-18", devanagari: "स्टेशन पहुँचते ही पता चला कि रेलगाड़ी एक घंटा देर से आएगी।"),
        HeldOutSentence(id: "ho-19", devanagari: "उसकी हँसी सुनकर पूरा कमरा ख़ुश हो गया।"),
        HeldOutSentence(id: "ho-20", devanagari: "बिजली का बिल इस महीने बहुत ज़्यादा आया है, हमें ध्यान रखना होगा।"),
        HeldOutSentence(id: "ho-21", devanagari: "क्षमा कीजिए, मुझे आपकी बात ठीक से समझ नहीं आई, फिर से बताइए।"),
        HeldOutSentence(id: "ho-22", devanagari: "पड़ोस की बिल्ली रोज़ दोपहर को हमारी खिड़की पर आकर सो जाती है।"),
        HeldOutSentence(id: "ho-23", devanagari: "त्योहार से पहले घर की पुताई और सफ़ाई का काम पूरा करना है।"),
        HeldOutSentence(id: "ho-24", devanagari: "मैंने खाने में नमक कम डाला था, फिर भी सबको पसंद आया।"),
        HeldOutSentence(id: "ho-25", devanagari: "शिक्षक ने बच्चों को विज्ञान का एक आसान प्रयोग करके दिखाया।"),
        HeldOutSentence(id: "ho-26", devanagari: "अतः यह तय हुआ कि बैठक सोमवार को नहीं, मंगलवार को होगी।"),
        HeldOutSentence(id: "ho-27", devanagari: "सड़क पर गड्ढे इतने हैं कि साइकिल चलाना मुश्किल हो गया है।"),
        HeldOutSentence(id: "ho-28", devanagari: "चाँद की रोशनी में झील का पानी चाँदी जैसा चमक रहा था।"),
        HeldOutSentence(id: "ho-29", devanagari: "अपना सामान संभालकर रखना, भीड़ में कुछ भी गुम हो सकता है।"),
        HeldOutSentence(id: "ho-30", devanagari: "धन्यवाद, आपकी मदद के बिना यह काम समय पर पूरा नहीं होता।"),
    ]

    /// The held-out score of `romanise`, or nil while no sentence has a reference yet.
    public static func score(_ romanise: (String) -> String) -> RomanisationScore? {
        RomanisationScore.measure(all.map { ($0.devanagari, $0.references) }, romanise: romanise)
    }
}

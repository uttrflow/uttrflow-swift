import UttrflowCore

/// Words a general recogniser already knows and the dictionary must not learn. See Docs/ordinary-words.md.
public enum GeneralVocabulary {
    /// The fewest letters a word worth learning can have: three, the length of `SQL` or `API`.
    static let shortestWorthLearning = 3

    /// Whether the recogniser already spells this word: lowercased and nothing more, so a phrase or a form with marks never is.
    public static func isOrdinary(_ word: String) -> Bool { known.contains(word.lowercased()) }

    /// Whether a speaker may mean this word in lower case: ordinary and English, or listed romanised Hindi.
    package static func isEveryday(_ word: String) -> Bool {
        let key = word.lowercased()
        return commonHinglish.contains(key) || (known.contains(key) && LexicalClass.isKnownEnglishWord(key))
    }

    /// Whether this word could be one of the user's own: long enough, has a letter, and not ordinary.
    static func isWorthLearning(_ word: String) -> Bool {
        word.count >= shortestWorthLearning && word.contains(where: \.isLetter) && !isOrdinary(word)
    }

    /// Whether `word` is the user's own spelling of the listed Hindi word `heard`: both listed, spelt apart, one sound key.
    static func isHindiSpellingPreference(_ word: String, over heard: String) -> Bool {
        let chosen = word.lowercased()
        let replaced = heard.lowercased()
        return chosen != replaced && commonHinglish.contains(chosen) && commonHinglish.contains(replaced)
            && Romaniser.soundKey(chosen) == Romaniser.soundKey(replaced)
    }

    /// The listed spellings `word` is a spelling preference over, in alphabetical order; none when it is no listed Hindi word.
    static func otherSpellings(of word: String) -> [String] {
        commonHinglish.filter { isHindiSpellingPreference(word, over: $0) }.sorted()
    }

    /// The most readings offered for one sound, so a crowded sound cannot fill a prompt line.
    public static let maximumPerSound = 4

    /// The opening letters a reading must share; stated once in `ReadingRestraint`, which the sources read it from.
    public static let openingLettersShared = ReadingRestraint.openingLettersShared

    /// Ordinary words this one could have been misheard as: the same likelier sound and opening, no function word, and a homophone where both are ordinary. See `Docs/cleanup.md`.
    public static func wordsSounding(like text: String) -> [String] {
        // A function word carries the sentence's structure, so its homophone changes the meaning, not the spelling.
        guard !FunctionWords.holds(text.lowercased()) else { return [] }
        return Array(
            (byPrimarySound[DoubleMetaphone.code(for: text).primary] ?? [])
                .filter {
                    Homophones.share($0, text)
                        || ReadingRestraint.closedUp($0) != ReadingRestraint.closedUp(text)
                }
                .filter { ReadingRestraint.opensAlike($0, heard: text) && !FunctionWords.holds($0) }
                // Both sides ordinary is a metaphone collision — "man" for "main" — unless they are said alike.
                .filter { !ReadingRestraint.isOrdinaryCollision($0, heard: text) }
                .prefix(maximumPerSound))
    }

    /// Every ordinary word filed under its likelier sound, built once over a set that never grows at runtime.
    private static let byPrimarySound: [String: [String]] = {
        var buckets: [String: [String]] = [:]
        for word in known {
            let primary = DoubleMetaphone.code(for: word).primary
            if !primary.isEmpty { buckets[primary, default: []].append(word) }
        }
        return buckets.mapValues { $0.sorted() }
    }()

    /// The one definition of an ordinary word: what the recogniser spells as one token, plus romanised Hindi, which it splits.
    private static let known: Set<String> = RecogniserWords.all.union(commonHinglish)

    /// Romanised Hindi and Hinglish glue, so a bilingual user does not end up with a dictionary of `nahi`.
    private static let commonHinglish: Set<String> = words(
        """
        nahi nahin haan han hum tum aap main mera meri tera teri hamara aapka unka uska
        iska kya kyu kyun kaise kaisa kaisi kab kahan kaun kitna kitne kitni woh yeh vo
        abhi phir bhi bhai behen didi yaar arre acha accha achha theek thik bilkul matlab
        lekin magar aur toh bas sirf zyada thoda kam bahut bohot chalo chal chalte karna
        karo kar kiya karta karte karti hona hota hote hoti hoga hogi honge raha rahe rahi
        gaya gayi gaye diya diye dena lena liya milna mila milta dekh dekho dekha suno suna
        bolo bola bolna kaam baat din raat subah shaam aaj parso samay waqt paisa paise
        rupaye ghar dost khana pani chai shukriya dhanyavaad namaste sahi galat naya purana
        chhota bada bura jaldi der pehle baad andar bahar upar niche saath bina liye wala
        wali kuch sab sabhi koi kisi apna apne khud hoon tha thi thay sakta sakte sakti
        chahiye padega jaana jao aana aao rakho rakha batao bataya samajh samjha hai hain
        mein jab tab jitna utna wahan yahan idhar udhar agar warna kripya
        """)

    /// One list split at first use, because a set literal of several hundred elements costs the type checker.
    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() })
    }
}

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

    /// Ordinary words this one could have been misheard as: a shared sound key, misheard by `PhonemeLexicon.soundsMisheard`, nearest first, no function word, no Hindi word (a Hindi respelling is `isHindiSpellingPreference`'s question), and said exactly alike where both are ordinary. See `Docs/cleanup.md`.
    public static func wordsSounding(like text: String) -> [String] {
        // A function word carries the sentence's structure, so its homophone changes the meaning, not the spelling.
        guard !FunctionWords.holds(text.lowercased()) else { return [] }
        // A listed romanised Hindi word is the speaker's own word, never a misspelt English one.
        guard !LoanwordRestoration.isRomanisedHindi(text) else { return [] }
        let lexicon = PhonemeLexicon.shared
        let closed = ReadingRestraint.closedUp(text)
        var seen: Set<String> = []
        let near = WordSound(of: text).keys.flatMap { bySound[$0] ?? [] }
            .filter {
                seen.insert($0).inserted && ReadingRestraint.closedUp($0) != closed
                    && !FunctionWords.holds($0) && !commonHinglish.contains($0)
            }
            .compactMap { word in lexicon.soundDistance(word, text).map { (word: word, distance: $0) } }
            .filter {
                lexicon.soundsMisheard(text, as: $0.word)
                    && !ReadingRestraint.isOrdinaryCollision($0.word, heard: text)
            }
        return near.sorted { ($0.distance, $0.word) < ($1.distance, $1.word) }.prefix(maximumPerSound).map(
            \.word)
    }

    /// The ordinary words the lexicon lists as said exactly like this ordinary one: "here" for "hear". Both sides ordinary, because the lexicon also lists rare spellings and surnames ("thee", "appel") that are no reading of a confidently heard word; a single letter is its name, never a homophone.
    public static func homophones(of text: String) -> [String] {
        guard text.count > 1, isOrdinary(text) else { return [] }
        // A clipped form ("in'") is the same word written short, not a homophone of it.
        return PhonemeLexicon.shared.homophones(of: text).filter {
            $0.count > 1 && $0.first != "'" && $0.last != "'" && isOrdinary($0)
        }
    }

    /// The words the lexicon lists as said exactly like this one, for judging a respelling. A word under three letters keeps only `homophones(of:)`, because a reduced listing makes "er" sound like "are" and "or".
    public static func soundAlikes(of text: String) -> [String] {
        guard ReadingRestraint.closedUp(text).count < 3 else {
            return PhonemeLexicon.shared.homophones(of: text)
        }
        return homophones(of: text)
    }

    /// Every common word filed under each of its sound keys, built once over a list that never grows at runtime.
    private static let bySound: [String: [String]] = {

        var buckets: [String: [String]] = [:]
        for word in known {
            for key in WordSound(of: word).keys { buckets[key, default: []].append(word) }
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

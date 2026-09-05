/// The words a general recogniser already knows, and therefore the words this
/// dictionary must never learn.
///
/// The dictionary exists for what a general model has *not* heard of — a colleague's
/// surname, `pgvector`, an internal product name. Every ordinary word that gets in
/// costs twice: it takes a slot in the conditioning prompt that a rare word needed, and
/// it puts a homophone into the phonetic index where it can win an argument against the
/// word the user actually said. "There" and "their" are the same sound; one of them
/// being in the dictionary is how a correct sentence gets broken.
///
/// A list and not a spell-checker. `NSSpellChecker` would be the obvious instrument and
/// is the wrong one here for three reasons. It is a UI framework, main-actor bound, in a
/// module whose whole point is that it can be tested in isolation; its answers depend on
/// which dictionaries the machine has installed, so the same build would learn different
/// words on two Macs; and it has no opinion at all about romanised Hindi, so every
/// Hinglish word would read as novel and the dictionary would fill up with `nahi` and
/// `matlab`. A list is deterministic, testable, offline by construction, and can hold
/// both languages.
///
/// It is deliberately a list of *common* words rather than a dictionary of all words.
/// A rare but real English word — "rhododendron" — getting in is harmless: the user
/// said it, and biasing the recogniser towards a word they actually use costs nothing.
/// A function word getting in is not harmless, and those are exactly what frequency
/// lists contain.
public enum GeneralVocabulary {
    /// The fewest letters a word worth learning can have.
    ///
    /// Three. Two-letter tokens are overwhelmingly noise — the "s" left behind by an
    /// apostrophe, an initial, "ok" — and the shortest thing anybody dictates that this
    /// dictionary could help with is a three-letter acronym like `SQL` or `API`.
    static let shortestWorthLearning = 3

    /// Whether a general model would already expect this word.
    ///
    /// Lowercased and nothing more. Case-folding is the one normalisation that always
    /// applies; stripping accents would be guessing at a language, and a word with an
    /// accent in it is not one of the few hundred below.
    static func knows(_ word: String) -> Bool { known.contains(word.lowercased()) }

    /// Whether this word could be one of the user's own.
    ///
    /// The single gate both learning paths ask. Three refusals, in order of how cheaply
    /// they can be decided: too short to be a word, no letters in it at all — so a date
    /// or a version number cannot become an entry — and already known to any recogniser.
    static func isWorthLearning(_ word: String) -> Bool {
        word.count >= shortestWorthLearning && word.contains(where: \.isLetter) && !knows(word)
    }

    /// The most readings offered for one sound, so a crowded sound cannot fill a prompt line.
    public static let maximumPerSound = 4

    /// The opening letters a reading must share, because a common word that merely rhymes is noise, not a reading.
    public static let openingLettersShared = 2

    /// Ordinary words this one could have been misheard as: the same likelier sound, the same opening. See `Docs/cleanup.md`.
    public static func wordsSounding(like text: String) -> [String] {
        let heard = text.lowercased()
        let opening = heard.prefix(openingLettersShared)
        return Array(
            (byPrimarySound[DoubleMetaphone.code(for: text).primary] ?? [])
                .filter { $0 != heard && $0.hasPrefix(opening) }
                .prefix(maximumPerSound))
    }

    /// Every common word filed under its likelier sound, built once over a list that never grows at runtime.
    private static let byPrimarySound: [String: [String]] = {
        var buckets: [String: [String]] = [:]
        for word in known {
            let primary = DoubleMetaphone.code(for: word).primary
            if !primary.isEmpty { buckets[primary, default: []].append(word) }
        }
        return buckets.mapValues { $0.sorted() }
    }()

    /// Both lists, merged once, because a lookup does not care which language refused it.
    private static let known: Set<String> = commonEnglish.union(commonHinglish)

    /// Ordinary English: the high-frequency core, plus the vocabulary of the things
    /// people actually dictate into — mail, chat, notes and calendars. "Meeting",
    /// "tomorrow" and "deadline" are not frequent enough to appear in a top-200 list and
    /// are exactly the words a dictation app would otherwise learn first.
    private static let commonEnglish: Set<String> = words(
        """
        the be to of and a in that have i it for not on with he as you do at this but his
        by from they we say her she or an will my one all would there their what so up out
        if about who get which go me when make can like time no just him know take people
        into year your good some could them see other than then now look only come its over
        think also back after use two how our work first well way even new want because any
        these give day most us is are was were been being am does did doing has had having
        man thing woman life child world school state family student group country problem
        hand part place case week company system program question government number night
        point home water room mother area money story fact month lot right study book eye
        job word business issue side kind head house service friend father power hour game
        line end member law car city community name president team minute idea kid body
        information parent face others level office door health person art war history party
        result change morning reason research girl guy moment air teacher force education
        become show leave feel put bring begin keep hold write stand hear let mean set meet
        run pay sit speak lie lead read grow open walk win offer remember love consider
        appear buy wait serve die send expect build stay fall cut reach remain suggest raise
        pass sell require report decide pull last long great little own old big high
        different small large next early young important few public bad same able very
        really here today tomorrow yesterday tonight please thanks thank yes okay sure maybe
        email mail meeting call message note notes update project client deadline draft
        document file folder link photo picture video schedule calendar reminder task list
        plan review agenda summary hello morning afternoon evening regards best sincerely
        cheers okay fine done ready sorry welcome again still never always often sometimes
        before during between under above through around against without within across
        should must might shall cannot every each both another such same other more less
        many much little few lots week weekend month quarter year daily weekly monthly
        too why where while whom whose off once ago yet else though since until upon per
        via ever soon later things quite rather almost enough instead however therefore
        actually basically probably definitely hi hey bye night week day thanks cool nice
        """)

    /// Romanised Hindi, and the Hinglish glue that holds a bilingual sentence together.
    ///
    /// Here for a reason the English list cannot cover. Uttrflow does English, Hindi and
    /// Hinglish, and a filter that knew only English would find every romanised Hindi
    /// word novel — so a user who speaks the way half of India speaks would end up with
    /// a dictionary of `nahi`, `matlab` and `theek`, which no recogniser needs help with
    /// and which crowd out the names and terms that do. These are common words in a
    /// language the recogniser already handles, so they are refused for exactly the same
    /// reason "meeting" is.
    ///
    /// Only the romanisations. Devanagari needs no list: a word written in it is either
    /// spoken Hindi the recogniser already transcribes or a name, and either way it does
    /// not collide with the English homophones this filter exists to keep out.
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
        mein jab tab jitna utna wahan yahan idhar udhar sirf agar warna kripya thik
        """)

    /// One list, written the way a list is easiest to read and to add to.
    ///
    /// A string split at first use rather than a set literal of several hundred elements:
    /// the literal costs the type checker real time for no benefit, and a wall of quotes
    /// and commas is where a duplicate hides.
    private static func words(_ list: String) -> Set<String> {
        Set(list.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() })
    }
}

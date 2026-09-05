/// Words a general recogniser already knows and the dictionary must not learn. See Docs/app-dictionary.md.
enum GeneralVocabulary {
    /// The fewest letters a word worth learning can have: three, the length of `SQL` or `API`.
    static let shortestWorthLearning = 3

    /// Whether a general model would already expect this word; lowercased and nothing more.
    static func knows(_ word: String) -> Bool { known.contains(word.lowercased()) }

    /// Whether this word could be one of the user's own: long enough, has a letter, and not already known.
    static func isWorthLearning(_ word: String) -> Bool {
        word.count >= shortestWorthLearning && word.contains(where: \.isLetter) && !knows(word)
    }

    /// Both lists, merged once, because a lookup does not care which language refused it.
    private static let known: Set<String> = commonEnglish.union(commonHinglish)

    /// Ordinary English: the high-frequency core plus the vocabulary of mail, chat, notes and calendars.
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
        plan review agenda summary hello afternoon evening regards best sincerely
        cheers fine done ready sorry welcome again still never always often sometimes
        before during between under above through around against without within across
        should must might shall cannot every each both another such more less
        many much lots weekend quarter daily weekly monthly
        too why where while whom whose off once ago yet else though since until upon per
        via ever soon later things quite rather almost enough instead however therefore
        actually basically probably definitely hi hey bye cool nice
        """)

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

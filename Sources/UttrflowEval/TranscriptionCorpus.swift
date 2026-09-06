/// The passages the operator reads once and every run is measured on. See Docs/eval-methodology.md.
public enum TranscriptionCorpus {
    public static let all: [TranscriptionCase] = english + hindi + hinglish

    public static func cases(in language: TranscriptionCase.Language) -> [TranscriptionCase] {
        all.filter { $0.language == language }
    }

    public static func cases(stressing stressor: TranscriptionCase.Stressor) -> [TranscriptionCase] {
        all.filter { $0.stressor == stressor }
    }

    public static func passage(_ id: String) -> TranscriptionCase? {
        all.first { $0.id == id }
    }

    /// `records` in corpus order, with anything the corpus has dropped sorted to the end by id.
    public static func inCorpusOrder<Record: Identifiable>(
        _ records: [Record], corpus: [TranscriptionCase] = all
    ) -> [Record] where Record.ID == String {
        let position = Dictionary(uniqueKeysWithValues: corpus.enumerated().map { ($1.id, $0) })
        return records.sorted {
            (position[$0.id] ?? corpus.count, $0.id) < (position[$1.id] ?? corpus.count, $1.id)
        }
    }

    /// Words in a passage as it will be read, counted the way the scorer counts them.
    public static func wordCount(of passage: TranscriptionCase) -> Int {
        TextNormaliser.standard.words(passage.prompt).count
    }

    /// Words in the whole corpus.
    public static var wordCount: Int { all.reduce(0) { $0 + wordCount(of: $1) } }

    /// Roughly how long reading these passages takes, at 120 words a minute plus half a minute each.
    public static func estimatedReadingTime(of passages: [TranscriptionCase]) -> Duration {
        let words = passages.reduce(0) { $0 + wordCount(of: $1) }
        return .seconds(Double(words) / 120 * 60 + Double(passages.count) * 30)
    }

    public static var estimatedReadingTime: Duration { estimatedReadingTime(of: all) }

    // MARK: English

    static let english: [TranscriptionCase] = [
        .init(
            id: "en-standup", language: .english, stressor: .everyday,
            romanised: """
                Morning everyone, quick update from me. The billing migration finished \
                overnight and nothing broke, so I am going to spend today on the refund flow \
                instead. If anyone needs the staging database I will be leaving it alone \
                until about four o'clock. Otherwise I have nothing blocking me.
                """,
            mustKeep: ["billing", "refund", "staging"]
        ),
        .init(
            id: "en-people", language: .english, stressor: .properNouns,
            romanised: """
                Priya Raghunathan is joining the platform team on Monday and she will be \
                sitting with Siobhan and Aditya in the Bengaluru office. Can someone add her \
                to the on-call rota, tell Marcus she needs access to Grafana, and forward her \
                the handover note that Ravi wrote for Chen last quarter.
                """,
            mustKeep: ["Priya Raghunathan", "Siobhan", "Aditya", "Bengaluru", "Grafana"]
        ),
        .init(
            id: "en-versions", language: .english, stressor: .digits,
            romanised: """
                We are pinning Python 3.11 for now because 3.12 breaks two of our extensions. \
                The staging box listens on port 8080, production is on 443, and the nightly \
                job starts at 2:30. Roughly 42 percent of requests are still hitting the old \
                endpoint, which is about 60 an hour.
                """,
            mustKeep: ["3.11", "3.12", "8080", "443", "42"]
        ),
        .init(
            id: "en-terms", language: .english, stressor: .technical,
            romanised: """
                The get_user helper is calling PostgreSQL twice per request, once through the \
                ORM and once in raw SQL, so I have made it idempotent and cached the result in \
                Redis. If that does not hold up under load we will move it behind an \
                OAuth-scoped endpoint and return JSON rather than protobuf.
                """,
            mustKeep: ["get_user", "PostgreSQL", "idempotent", "Redis", "OAuth", "JSON"]
        ),
        .init(
            id: "en-restarts", language: .english, stressor: .falseStarts,
            romanised: """
                So I was, I was going to say that the, the deploy can wait until, sorry, until \
                after the review. Actually no, let us do it, let us do it before, because \
                Ananya is off tomorrow and, um, nobody else has the keys to that account.
                """,
            mustKeep: ["Ananya"]
        ),
        .init(
            id: "en-message", language: .english, stressor: .everyday,
            romanised: """
                Hi Tom, thanks for sending the contract through. I have read it twice and the \
                only clause I am unsure about is the one on notice periods, because 30 days \
                feels short given how long the handover took last time. Could we make it 60? \
                Everything else looks fine and I am happy to sign this week.
                """,
            mustKeep: ["Tom", "30", "60"]
        ),
    ]

    // MARK: Hindi, with no English loanwords, since a mixed passage is Hinglish whatever its label

    static let hindi: [TranscriptionCase] = [
        .init(
            id: "hi-everyday", language: .hindi, stressor: .everyday,
            romanised: """
                Kal shaam ko main ghar jaldi pahunch gaya tha isliye wo kaam nahi ho paya. Aaj \
                subah kar dunga, chinta mat karo. Agar kuch aur chahiye to mujhe bata dena.
                """,
            devanagari: """
                कल शाम को मैं घर जल्दी पहुँच गया था इसलिए वो काम नहीं हो पाया। आज सुबह कर दूँगा, \
                चिंता मत करो। अगर कुछ और चाहिए तो मुझे बता देना।
                """
        ),
        .init(
            id: "hi-people", language: .hindi, stressor: .properNouns,
            romanised: """
                Ananya aur Raghunath kal Dilli se aa rahe hain. Unhe lene ke liye Vikram \
                jayega, aur shaam ko hum sab Meera ke ghar par milenge. Kripya dadi ko bhi \
                bata dena.
                """,
            devanagari: """
                अनन्या और रघुनाथ कल दिल्ली से आ रहे हैं। उन्हें लेने के लिए विक्रम जाएगा, और शाम को \
                हम सब मीरा के घर पर मिलेंगे। कृपया दादी को भी बता देना।
                """
        ),
        .init(
            id: "hi-numbers", language: .hindi, stressor: .digits,
            romanised: """
                Mujhe aadha ghanta aur chahiye, phir main paanch baje tak sab bhej dunga. Kal \
                das log aa rahe hain aur hamare paas sirf aath kursiyan hain, to chaar aur \
                mangwa lena.
                """,
            devanagari: """
                मुझे आधा घंटा और चाहिए, फिर मैं पाँच बजे तक सब भेज दूँगा। कल दस लोग आ रहे हैं और \
                हमारे पास सिर्फ़ आठ कुर्सियाँ हैं, तो चार और मँगवा लेना।
                """
        ),
        .init(
            id: "hi-restarts", language: .hindi, stressor: .falseStarts,
            romanised: """
                Yaar wo wo jo kal wali baat thi na, maine socha tha ki, nahi nahi ruko, pehle \
                ye bata do ki tumne unse kaha ya nahi. Agar nahi kaha to main khud keh dunga.
                """,
            devanagari: """
                यार वो वो जो कल वाली बात थी न, मैंने सोचा था कि, नहीं नहीं रुको, पहले ये बता दो कि \
                तुमने उनसे कहा या नहीं। अगर नहीं कहा तो मैं खुद कह दूँगा।
                """
        ),
        .init(
            id: "hi-request", language: .hindi, stressor: .everyday,
            romanised: """
                Suno, zara wo purani wali kitaab nikaal kar dekh lena, usmein pichhle saal ka \
                saara hisaab hai. Agar kuch samajh na aaye to mujhe shaam tak bata dena, main \
                ghar par hi rahunga.
                """,
            devanagari: """
                सुनो, ज़रा वो पुरानी वाली किताब निकाल कर देख लेना, उसमें पिछले साल का सारा हिसाब है। \
                अगर कुछ समझ न आए तो मुझे शाम तक बता देना, मैं घर पर ही रहूँगा।
                """
        ),
        .init(
            id: "hi-long", language: .hindi, stressor: .everyday,
            romanised: """
                Pichhle hafte jo baarish hui thi uski wajah se sadak abhi tak kharab hai, \
                isliye subah nikalne mein thodi der ho jayegi. Tum apna saamaan aaj raat hi \
                taiyaar rakhna, warna kal subah bhaagdaud mach jayegi aur kuch na kuch chhoot \
                jayega.
                """,
            devanagari: """
                पिछले हफ़्ते जो बारिश हुई थी उसकी वजह से सड़क अभी तक ख़राब है, इसलिए सुबह निकलने में \
                थोड़ी देर हो जाएगी। तुम अपना सामान आज रात ही तैयार रखना, वरना कल सुबह भागदौड़ मच \
                जाएगी और कुछ न कुछ छूट जाएगा।
                """
        ),
    ]

    // MARK: Hinglish; the Devanagari forms keep borrowed words in Latin script, as the recogniser does

    static let hinglish: [TranscriptionCase] = [
        .init(
            id: "hinglish-standup", language: .hinglish, stressor: .everyday,
            romanised: """
                Kal ka deploy ho gaya hai, bas ek chhota sa issue tha staging mein lekin wo fix \
                kar diya. Aaj main refund wala flow dekhunga aur shaam tak PR bhej dunga.
                """,
            devanagari: """
                कल का deploy हो गया है, बस एक छोटा सा issue था staging में लेकिन वो fix कर दिया। \
                आज मैं refund वाला flow देखूँगा और शाम तक PR भेज दूँगा।
                """,
            mustKeep: ["deploy", "staging", "refund", "PR"]
        ),
        .init(
            id: "hinglish-terms", language: .hinglish, stressor: .technical,
            romanised: """
                Wo query bahut slow chal rahi hai kyunki index nahi laga hai, to maine \
                PostgreSQL mein ek composite index bana diya aur ab response time aadha ho gaya \
                hai.
                """,
            devanagari: """
                वो query बहुत slow चल रही है क्योंकि index नहीं लगा है, तो मैंने PostgreSQL में एक \
                composite index बना दिया और अब response time आधा हो गया है।
                """,
            mustKeep: ["query", "index", "PostgreSQL", "composite"]
        ),
        .init(
            id: "hinglish-numbers", language: .hinglish, stressor: .digits,
            romanised: """
                Meeting bees minute late shuru hogi kyunki Anand abhi raaste mein hai. Uske \
                baad hamein version 2.4 ka demo dena hai, aur wo mushkil se das minute ka hoga.
                """,
            devanagari: """
                meeting बीस minute late शुरू होगी क्योंकि Anand अभी रास्ते में है। उसके बाद हमें \
                version 2.4 का demo देना है, और वो मुश्किल से दस minute का होगा।
                """,
            mustKeep: ["meeting", "Anand", "2.4", "demo"]
        ),
        .init(
            id: "hinglish-people", language: .hinglish, stressor: .properNouns,
            romanised: """
                Priya ne kaha ki Bengaluru wali team aaj call par nahi aa payegi, isliye maine \
                Rohit aur Fatima ko alag se update bhej diya hai. Baaki sab theek chal raha hai.
                """,
            devanagari: """
                Priya ने कहा कि Bengaluru वाली team आज call पर नहीं आ पाएगी, इसलिए मैंने Rohit \
                और Fatima को अलग से update भेज दिया है। बाकी सब ठीक चल रहा है।
                """,
            mustKeep: ["Priya", "Bengaluru", "Rohit", "Fatima", "update"]
        ),
        .init(
            id: "hinglish-restarts", language: .hinglish, stressor: .falseStarts,
            romanised: """
                Are wo wo bug abhi tak fix nahi hua, matlab maine try kiya tha lekin, nahi \
                ruko, maine sirf log dekhe the. Aaj poora debug karke batata hun.
                """,
            devanagari: """
                अरे वो वो bug अभी तक fix नहीं हुआ, मतलब मैंने try किया था लेकिन, नहीं रुको, मैंने \
                सिर्फ़ log देखे थे। आज पूरा debug करके बताता हूँ।
                """,
            mustKeep: ["bug", "fix", "log", "debug"]
        ),
        .init(
            id: "hinglish-message", language: .hinglish, stressor: .everyday,
            romanised: """
                Sir, main aaj thoda late pahunchunga kyunki doctor ke paas jaana hai. Maine \
                apna kaam kal raat hi finish kar diya tha, to koi bhi cheez pending nahi hai. \
                Zaroorat ho to call kar lijiyega.
                """,
            devanagari: """
                sir, मैं आज थोड़ा late पहुँचूँगा क्योंकि doctor के पास जाना है। मैंने अपना काम कल रात \
                ही finish कर दिया था, तो कोई भी चीज़ pending नहीं है। ज़रूरत हो तो call कर लीजिएगा।
                """,
            mustKeep: ["late", "doctor", "finish", "pending", "call"]
        ),
    ]
}

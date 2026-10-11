// Invented Hindi sentences holding a name, a place or a weekday, scored by a case-sensitive check apart from the case-folded word error rate.
import UttrflowCore

/// One invented Devanagari sentence, what the person owns that could name its capitalised word, and how a typist writes it.
struct RomanisedNameCase: Sendable, Equatable {
    /// Whether a source the person owns, or a closed table, can supply the capital.
    enum Reach: String, Sendable, CaseIterable {
        /// A dictionary word, a name on the screen or the weekday table spells the word.
        case owned
        /// Only a shipped list of names and places could spell the word.
        case unowned
        /// No word needs a capital; a capital here is the over-capitalising failure.
        case control
    }

    let id: String
    let reach: Reach
    let spoken: String
    let dictionary: [String]
    let onScreenNames: [String]
    let expected: String

    init(
        id: String, reach: Reach, spoken: String, dictionary: [String] = [], onScreenNames: [String] = [],
        expected: String
    ) {
        self.id = id
        self.reach = reach
        self.spoken = spoken
        self.dictionary = dictionary
        self.onScreenNames = onScreenNames
        self.expected = expected
    }
}

/// How many mid-sentence words of each kind kept their case, per `Reach`.
struct RomanisedNameScore: Sendable, Equatable {
    /// Case-sensitive tallies of every case, grouped by its reach.
    let tallies: [RomanisedNameCase.Reach: CapitalisationTally]

    /// The share of capitalised words written with their capital among the cases of `reach`; nil when none.
    func nameAccuracy(_ reach: RomanisedNameCase.Reach) -> Double? {
        tallies[reach]?.accuracy(of: .capitalised)
    }

    /// The share of lower-case words kept lower case over every case: the over-capitalising check.
    var lowerCaseAccuracy: Double? {
        tallies.values.reduce(CapitalisationTally(), +).accuracy(of: .lowerCase)
    }
}

/// The romanised-names class: at least twenty cases, every name invented, scored on case alone.
enum RomanisedNameCorpus {
    static let all: [RomanisedNameCase] = [
        RomanisedNameCase(
            id: "rn-01", reach: .owned, spoken: "कल आरव से मिलना है", dictionary: ["Aarav"],
            expected: "Kal Aarav se milna hai."),
        RomanisedNameCase(
            id: "rn-02", reach: .owned, spoken: "मैंने कल मीरा को फोन किया", dictionary: ["Meera"],
            expected: "Maine kal Meera ko phone kiya."),
        RomanisedNameCase(
            id: "rn-03", reach: .owned, spoken: "यह फाइल कबीर को भेज दो", dictionary: ["Kabir"],
            expected: "Yeh file Kabir ko bhej do."),
        RomanisedNameCase(
            id: "rn-04", reach: .owned, spoken: "आज नेहा ने खाना बनाया", dictionary: ["Neha"],
            expected: "Aaj Neha ne khaana banaya."),
        RomanisedNameCase(
            id: "rn-05", reach: .owned, spoken: "अमित और प्रिया कल आएंगे", dictionary: ["Amit", "Priya"],
            expected: "Amit aur Priya kal aayenge."),
        RomanisedNameCase(
            id: "rn-06", reach: .owned, spoken: "विकास भाई से बात हुई", dictionary: ["Vikas"],
            expected: "Vikas bhai se baat hui."),
        RomanisedNameCase(
            id: "rn-07", reach: .owned, spoken: "गुप्ता साहब का फोन आया था", dictionary: ["Gupta"],
            expected: "Gupta saahab ka phone aaya tha."),
        RomanisedNameCase(
            id: "rn-08", reach: .owned, spoken: "अनिका जी कल आ रही हैं", dictionary: ["Anika"],
            expected: "Anika ji kal aa rahi hain."),
        RomanisedNameCase(
            id: "rn-09", reach: .owned, spoken: "हम जयपुर चलेंगे", dictionary: ["Jaipur"],
            expected: "Hum Jaipur chalenge."),
        RomanisedNameCase(
            id: "rn-10", reach: .owned, spoken: "मेरी बहन पुणे में रहती है", dictionary: ["Pune"],
            expected: "Meri bahan Pune mein rehti hai."),
        RomanisedNameCase(
            id: "rn-11", reach: .owned, spoken: "मीटिंग भोपाल में है", dictionary: ["Bhopal"],
            expected: "Meeting Bhopal mein hai."),
        RomanisedNameCase(
            id: "rn-12", reach: .owned, spoken: "कल मैंने रोहन को बुलाया", onScreenNames: ["Rohan Shah"],
            expected: "Kal maine Rohan ko bulaya."),
        RomanisedNameCase(
            id: "rn-13", reach: .owned, spoken: "आज तनया का जन्मदिन है", onScreenNames: ["Tanya Roy"],
            expected: "Aaj Tanya ka janmadin hai."),
        RomanisedNameCase(
            id: "rn-14", reach: .owned, spoken: "अभी अनिका का संदेश आया", onScreenNames: ["Anika Rao"],
            expected: "Abhi Anika ka sandesh aaya."),
        RomanisedNameCase(
            id: "rn-15", reach: .owned, spoken: "हम सोमवार को चलेंगे", expected: "Hum Somwaar ko chalenge."),
        RomanisedNameCase(
            id: "rn-16", reach: .owned, spoken: "मीटिंग मंगलवार को है", expected: "Meeting Mangalwaar ko hai."),
        RomanisedNameCase(
            id: "rn-17", reach: .owned, spoken: "बुधवार और शुक्रवार खाली हैं",
            expected: "Budhwaar aur Shukrawaar khaali hain."),
        RomanisedNameCase(
            id: "rn-18", reach: .owned, spoken: "शनिवार को छुट्टी रहेगी", expected: "Shaniwaar ko chhutti rahegi."),
        RomanisedNameCase(
            id: "rn-19", reach: .owned, spoken: "रविवार को सब घर पर रहेंगे",
            expected: "Raviwaar ko sab ghar par rahenge."),
        RomanisedNameCase(
            id: "rn-20", reach: .unowned, spoken: "कल दिल्ली जाना है", expected: "Kal Delhi jaana hai."),
        RomanisedNameCase(
            id: "rn-21", reach: .unowned, spoken: "मैंने रोहन को बताया", expected: "Maine Rohan ko bataya."),
        RomanisedNameCase(
            id: "rn-22", reach: .unowned, spoken: "वह चेन्नई से आ रहा है", expected: "Woh Chennai se aa raha hai."),
        RomanisedNameCase(
            id: "rn-23", reach: .unowned, spoken: "शर्मा जी कल लखनऊ जा रहे हैं",
            dictionary: ["Sharma"], expected: "Sharma ji kal Lucknow ja rahe hain."),
        RomanisedNameCase(
            id: "rn-24", reach: .control, spoken: "मैंने कल चाय पी", onScreenNames: ["Kal Verma"],
            expected: "Maine kal chai pi."),
    ]

    /// The case-sensitive score of `run` over every case, apart from the word error rate that folds case.
    static func score(
        _ run: (RomanisedNameCase) async throws -> String
    ) async rethrows
        -> RomanisedNameScore
    {
        var tallies: [RomanisedNameCase.Reach: CapitalisationTally] = [:]
        for nameCase in all {
            let produced = try await run(nameCase)
            let tally = CapitalisationTally.measure(
                ClassifiedWord.words(of: produced).map(\.word),
                against: ClassifiedWord.words(of: nameCase.expected))
            tallies[nameCase.reach, default: CapitalisationTally()] =
                (tallies[nameCase.reach] ?? CapitalisationTally()) + tally
        }
        return RomanisedNameScore(tallies: tallies)
    }
}

import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary

/// Romanised Hindi names, places and weekdays take a capital only where a source the person owns or the weekday table spells them. See `Docs/latin-output.md`.
@Suite("Romanised name casing")
struct RomanisedNameCasingTests {
    private func written(
        _ spoken: String, dictionary: [String] = [], onScreen: [String] = []
    ) -> String {
        let draft = Draft(romanising: Transcription(text: spoken))
        return RomanisedNameCasing(personal: dictionary, onScreenNames: onScreen).casing(draft).text
    }

    @Test("a weekday is written with its capital")
    func weekday() {
        #expect(written("हम सोमवार को चलेंगे") == "hum Somwaar ko chalenge")
    }

    @Test("a dictionary name that a respelling does not reach takes its capital")
    func dictionaryName() {
        #expect(written("आज नेहा ने खाना बनाया", dictionary: ["Neha"]) == "aaj Neha ne khaana banaya")
    }

    @Test("a name on the screen takes its capital, and a tail word after a name stays lower case")
    func screenNameAndTail() {
        #expect(written("कल रोहन भाई आए", onScreen: ["Rohan Shah"]) == "kal Rohan bhai aaye")
        #expect(written("कल रोहन भाई आए", onScreen: ["Rohan Bhai"]) == "kal Rohan bhai aaye")
    }

    @Test("a name that is a listed romanised Hindi word is never cased")
    func hindiWordKeepsLowerCase() {
        #expect(written("मैंने कल चाय पी", dictionary: ["Kal"], onScreen: ["Kal Verma"]) == "maine kal chai pi")
    }

    @Test("no source, no capital")
    func nothingOwned() {
        #expect(written("कल दिल्ली जाना है") == "kal dilli jaana hai")
    }

    @Test("a word that did not come from Devanagari is left as it was")
    func englishUntouched() {
        let draft = Draft(transcription: Transcription(text: "call neha on monday"))
        let cased = RomanisedNameCasing(personal: ["Neha"]).casing(draft)
        #expect(cased.text == "call neha on monday")
    }

    @Test("casing twice is casing once")
    func idempotent() {
        let casing = RomanisedNameCasing(personal: ["Neha"])
        let once = casing.casing(Draft(romanising: Transcription(text: "नेहा सोमवार को आएगी")))
        #expect(casing.casing(once).text == once.text)
    }

    @Test("the entry shapes that name a person or a place are the only ones read")
    func entryShapes() {
        for entry in ["Neha", "Pune"] { #expect(RomanisedNameCasing.isCasedName(entry)) }
        for entry in ["neha", "NASA", "iPhone", "Neha Rao", "A", "Ne1ha"] {
            #expect(!RomanisedNameCasing.isCasedName(entry))
        }
    }
}

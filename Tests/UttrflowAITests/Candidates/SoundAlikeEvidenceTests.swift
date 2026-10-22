import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

/// The recogniser's word stands unless the user's dictionary, the place or a grammar rule gives the sound-alike evidence.
@Suite("A sound-alike replaces a heard word only on evidence", .bug(id: 8105))
struct SoundAlikeEvidenceTests {
    private func offered(
        _ text: String, for heard: String, in situation: Situation = .unknown
    ) async -> [String] {
        await DoubtfulWords.standard.spans(in: Draft.heard(text), for: situation)
            .filter { $0.heard == heard }.flatMap { $0.candidates.map(\.spelling) }
    }

    @Test(
        "a content word that stands as heard is offered no sound-alike, heard surely or not",
        arguments: [
            ("we ?need three things open bracket c below close bracket", "need"),
            ("we need three things open bracket c below close bracket", "need"),
            ("what a ?scene that was at the party", "scene"),
            ("what a scene that was at the party", "scene"),
            ("kia ?scene hai for the weekend", "scene"),
            ("please write the answer at the meeting", "write"),
        ])
    func standingWordGetsNoReading(text: String, heard: String) async {
        let found = await offered(text, for: heard)
        #expect(found.isEmpty, "\(heard) was offered \(found)")
    }

    @Test(
        "the guard refuses the rewrite that swaps the heard word for its sound-alike",
        arguments: [
            ("we ?need three things", "we knead three things"),
            ("what a ?scene that was at the party", "what a seen that was at the party"),
            ("kia ?scene hai for the weekend", "kia seen hai for the weekend"),
            ("action item for ?John schedule a follow up", "action item for Jon schedule a follow up"),
        ])
    func guardRefusesTheSwap(text: String, swapped: String) async {
        let draft = Draft.heard(text)
        let spans = await DoubtfulWords.standard.spans(in: draft, for: .unknown)
        #expect(
            !MeaningPreservationGuard().verdict(draft: draft, rewritten: swapped, offering: spans).isAccepted)
    }

    @Test("a name the user did not add is offered no other spelling", arguments: ["?John", "John"])
    func nameGetsNoReading(name: String) async {
        let found = await offered("action item for \(name) schedule a follow up", for: "John")
        #expect(found.isEmpty, "John was offered \(found)")
    }

    @Test("a name the user's dictionary spells another way is offered that spelling")
    func dictionarySpellingOfANameIsOffered() async {
        let entry = DictionaryEntry(word: "Jon", origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        let index = PhoneticIndex(entries: [entry])
        let spans = await DoubtfulWords.including(dictionary: { index }).spans(
            in: Draft.heard("action item for ?John schedule a follow up"), for: .unknown)
        #expect(spans.contains { $0.heard == "John" && $0.candidates.contains { $0.entryID == entry.id } })
    }

    @Test("a sound-alike the screen shows is offered")
    func screenShownSoundAlikeIsOffered() async {
        let found = await offered(
            "now ?need the dough for ten minutes", for: "need",
            in: .showing(preceding: "Step 3: knead the dough"))
        #expect(found.contains("knead"), "got \(found)")
    }

    @Test(
        "a heard word a grammar rule rules out is still offered its partner",
        arguments: [
            ("put it over ?their", "their", "there"),
            ("wait an ?our please", "our", "hour"),
            ("?their is a problem", "their", "there"),
            ("send it ?too me", "too", "to"),
        ])
    func ruledOutWordIsOffered(text: String, heard: String, partner: String) async {
        let found = await offered(text, for: heard)
        #expect(found.contains(partner), "\(heard) was offered \(found)")
    }
}

@Suite("When a heard word cannot stand in its place", .bug(id: 8105))
struct HeardWordFitTests {
    private func rule(_ text: String, at index: Int) -> HeardWordFit.Rule? {
        HeardWordFit.ruledOut(index..<(index + 1), in: text.split(separator: " ").map(String.init))
    }

    @Test(
        "each rule names the slot it rules out",
        arguments: [
            ("put it over their", 3, HeardWordFit.Rule.possessiveClosing),
            ("put it over their. then leave", 3, .possessiveClosing),
            ("wait an our please", 2, .possessiveAfterArticle),
            ("their is a problem", 0, .possessiveBeforeBe),
            ("send it too me", 2, .tooBeforeObject),
            ("we xqzv three things", 1, .notAWord),
        ])
    func rulesOut(text: String, index: Int, expected: HeardWordFit.Rule) {
        #expect(rule(text, at: index) == expected)
    }

    @Test(
        "a word that can stand in its place is ruled out by no rule",
        arguments: [
            ("we need three things", 1),
            ("what a scene that was", 2),
            ("their car is red", 0),
            ("whose is this", 0),
            ("me too. them as well", 1),
            ("it is too much for them", 2),
            ("kia scene hai for the weekend", 1),
            ("it costs 49 dollars", 2),
        ])
    func standsAsHeard(text: String, index: Int) {
        #expect(rule(text, at: index) == nil)
    }

    @Test("a romanised Hindi word is no unknown word")
    func hindiIsNotUnknown() {
        #expect(rule("kia scene hai", at: 0) == nil)
    }

    @Test("a capitalised name is a name, a capitalised ordinary word is not")
    func names() {
        #expect(HeardWordFit.isName(3..<4, in: ["action", "item", "for", "John"]))
        #expect(!HeardWordFit.isName(1..<2, in: ["add", "Oath", "login"]))
        #expect(!HeardWordFit.isName(1..<2, in: ["add", "john", "login"]))
    }
}

@Suite("A word in a romanised Hindi clause is offered no English reading", .bug(id: 8158))
struct HindiClauseSoundAlikeTests {
    @Test(
        "an unlisted spelling beside a Hindi copula is ruled out by no rule",
        arguments: [
            ("Thiek hai, I will do it tomorrow.", 0),
            ("Achcha, so the client wants changes. Thiek hai.", 6),
            ("Woh thiek tha, I checked.", 1),
        ])
    func copulaClauseIsHindi(text: String, index: Int) {
        let said = text.split(separator: " ").map(String.init)
        #expect(HeardWordFit.ruledOut(index..<(index + 1), in: said) == nil)
    }

    @Test("the unsure spelling is offered no English sound-alike")
    func noEnglishReadingOffered() async {
        let spans = await DoubtfulWords.standard.spans(
            in: Draft.heard("?Thiek hai, I will do it tomorrow."), for: .unknown)
        let found = spans.filter { $0.heard == "Thiek" }.flatMap { $0.candidates.map(\.spelling) }
        #expect(found.isEmpty, "Thiek was offered \(found)")
    }

    @Test("an unknown word in an English sentence is still ruled out")
    func englishSentenceStillRuledOut() {
        #expect(HeardWordFit.ruledOut(1..<2, in: ["we", "xqzv", "three", "things"]) == .notAWord)
    }
}

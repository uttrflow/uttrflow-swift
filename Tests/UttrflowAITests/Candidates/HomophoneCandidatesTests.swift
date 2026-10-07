import Testing
import UttrflowCore
@testable import UttrflowAI
@testable import UttrflowDictionary

@Suite("Homophone candidates")
struct HomophoneCandidatesTests {
    @Test("Offers every partner of a three-way group, in the table's order")
    func offersEveryPartnerInOrder() async {
        let source = HomophoneCandidates()
        let offered = await source.candidates(for: Draft.Word("there", evidence: .score(0.8)), in: .unknown)
        #expect(offered.map(\.spelling) == ["their", "they're"])
    }

    @Test(
        "Offers each word's partners in table order, never capped below the group",
        arguments: Homophones.groups)
    func offersWholeGroup(group: [String]) async {
        let source = HomophoneCandidates()
        for word in group {
            let offered = await source.candidates(for: Draft.Word(word, evidence: .score(0.8)), in: .unknown)
            #expect(offered.map(\.spelling) == group.filter { $0 != word })
        }
    }
}

// Tests that the generated homophone cases cover every hand-kept class and are well formed.
import Testing
import UttrflowEval

@testable import UttrflowDictionary

@Suite("HomophoneCaseSet")
struct HomophoneCaseSetTests {
    static let cases = HomophoneCaseSet.cases(classes: Homophones.groups)

    @Test func everySpellingOfEveryClassHasTwoCarriers() {
        for spelling in Homophones.groups.joined() {
            #expect(HomophoneCarriers.all.count { $0.spelling == spelling } == 2, "\(spelling)")
        }
        let spellings = Set(Homophones.groups.joined())
        for carrier in HomophoneCarriers.all {
            #expect(spellings.contains(carrier.spelling), "\(carrier.spelling)")
        }
    }

    @Test func everyCarrierHoldsOneSlotAndNoMemberOfItsClass() {
        for carrier in HomophoneCarriers.all {
            let words = carrier.template.split(separator: " ").map(String.init)
            #expect(words.count { $0 == "_" } == 1, "\(carrier.template)")
            let members = Homophones.group(containing: carrier.spelling) ?? []
            #expect(words.allSatisfy { !members.contains($0) }, "\(carrier.template)")
        }
    }

    @Test func eachCaseSwapsOnlyTheSlot() {
        for item in Self.cases {
            #expect(item.input != item.expected)
            #expect(Homophones.share(item.meant, item.heard), "\(item.expected)")
            let input = item.input.split(separator: " ")
            let expected = item.expected.split(separator: " ")
            #expect(input.count == expected.count)
            let changed = zip(input, expected).filter { $0 != $1 }
            #expect(
                changed.count == 1 && changed.first.map { String($0.0) == item.heard } == true,
                "\(item.input)")
        }
    }

    @Test func theSetCoversEveryClassAndCountsItsCases() {
        let meant = Set(Self.cases.map(\.meant))
        #expect(meant == Set(Homophones.groups.joined()))
        let carriersWithOthers = HomophoneCarriers.all.map { carrier in
            (Homophones.group(containing: carrier.spelling)?.count ?? 1) - 1
        }
        #expect(Self.cases.count == carriersWithOthers.reduce(0, +))
        #expect(Self.cases.count >= 250)
        for decider in [HomophoneDecider.role, .sense, .domain, .none] {
            #expect(Self.cases.contains { $0.decider == decider }, "\(decider)")
        }
    }
}

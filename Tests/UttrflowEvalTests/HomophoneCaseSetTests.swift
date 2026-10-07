// Tests that the generated homophone cases cover every hand-kept class and are well formed.
import Testing
@testable import UttrflowEval

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

    static let lexiconClasses = Homophones.groups + HomophoneLexiconClasses.all
    static let lexiconCases = HomophoneCaseSet.cases(
        classes: lexiconClasses, carriers: HomophoneCarriers.all + HomophoneCarriers.lexicon)

    @Test func lexiconClassesShareNoSpellingWithTheHandKeptOnes() {
        let kept = Set(Homophones.groups.joined())
        let added = HomophoneLexiconClasses.all.joined()
        #expect(added.allSatisfy { !kept.contains($0) })
        #expect(Set(added).count == added.count)
    }

    @Test func everyLexiconSpellingHasTwoCarriersWithOneSlotAndNoClassMember() {
        for spelling in HomophoneLexiconClasses.all.joined() {
            #expect(HomophoneCarriers.lexicon.count { $0.spelling == spelling } == 2, "\(spelling)")
        }
        for carrier in HomophoneCarriers.lexicon {
            let words = carrier.template.split(separator: " ").map(String.init)
            #expect(words.count { $0 == "_" } == 1, "\(carrier.template)")
            let members = HomophoneLexiconClasses.all.first { $0.contains(carrier.spelling) } ?? []
            #expect(!members.isEmpty, "\(carrier.spelling)")
            #expect(words.allSatisfy { !members.contains($0) }, "\(carrier.template)")
        }
    }

    @Test func theGrownSetHoldsAHundredClassesAndFiveHundredCases() {
        #expect(Self.lexiconClasses.count >= 100)
        #expect(Self.lexiconCases.count >= 500)
        #expect(Set(Self.lexiconCases.map(\.meant)) == Set(Self.lexiconClasses.joined()))
        for item in Self.lexiconCases {
            let changed = zip(item.input.split(separator: " "), item.expected.split(separator: " "))
                .filter { $0 != $1 }
            #expect(changed.count == 1, "\(item.input)")
        }
    }
}

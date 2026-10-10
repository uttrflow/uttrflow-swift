// Tests the confusable-pair inventory, the cost class each group lands in, and how a decode is read.
import Testing
import UttrflowAI
import UttrflowEval

@Suite("ConfusablePairs")
struct ConfusablePairsTests {
    private static func words(_ text: String) -> [String] { TextNormaliser.standard.words(text) }

    @Test("every group is listed, and every pair's readings differ once normalised")
    func inventoryShape() {
        let groups = Set(ConfusablePairs.all.map(\.group))
        #expect(groups == Set(ConfusablePair.Group.allCases))
        #expect(ConfusablePairs.all.count == 30)
        for pair in ConfusablePairs.all {
            #expect(pair.carrier.split(separator: " ").count { $0 == "_" } == 1, "\(pair.carrier)")
            #expect(Self.words(pair.firstReading) != Self.words(pair.secondReading), "\(pair.carrier)")
        }
    }

    @Test("a dropped word leaves a sentence with no gap")
    func droppedSlot() {
        let pair = ConfusablePair(.negation, "the tests are _ passing", "not", "")
        #expect(pair.firstReading == "the tests are not passing")
        #expect(pair.secondReading == "the tests are passing")
    }

    @Test("negations flip meaning, teens and amounts flip numbers, articles and meaning swaps stay cosmetic")
    func costClassByGroup() {
        let cosmeticAmounts: Set<String> = ["a", "an", "on"]
        for pair in ConfusablePairs.all {
            let cost = ConfusionCost.of(heard: pair.firstReading, candidate: pair.secondReading)
            let expected: ConfusionCost =
                switch pair.group {
                case .negation, .hindiNegation: .meaningFlip
                case .teenTen: .numberFlip
                case .nearQuantity: cosmeticAmounts.contains(pair.first) ? .cosmetic : .numberFlip
                case .meaningSwap: .cosmetic
                }
            #expect(cost == expected, "\(pair.firstReading) / \(pair.secondReading)")
        }
    }

    @Test("a decode is right, flipped toward the other reading, or wrong some other way")
    func outcomes() {
        let meant = Self.words("order fifteen boxes of paper")
        let other = Self.words("order fifty boxes of paper")
        #expect(ConfusablePairs.outcome(meant: meant, other: other, heard: Self.words("Order 15 boxes of paper.")) == .right)
        #expect(ConfusablePairs.outcome(meant: meant, other: other, heard: Self.words("order 50 boxes of paper")) == .flipped)
        #expect(
            ConfusablePairs.outcome(meant: meant, other: other, heard: Self.words("order 15 boxes of pepper")) == .otherError)
        let negated = Self.words("the tests are not passing")
        let dropped = Self.words("the tests are passing")
        #expect(ConfusablePairs.outcome(meant: negated, other: dropped, heard: dropped) == .flipped)
        #expect(ConfusablePairs.outcome(meant: dropped, other: negated, heard: negated) == .flipped)
    }

    @Test("a tally counts flips apart from other errors")
    func tally() {
        var tally = ConfusablePairs.Tally()
        #expect(tally.flipRate == 0 && tally.errorRate == 0)
        for outcome in [ConfusablePairs.Outcome.right, .flipped, .otherError, .right] { tally.add(outcome) }
        #expect(tally.decodes == 4 && tally.flips == 1 && tally.otherErrors == 1)
        #expect(tally.flipRate == 0.25)
        #expect(tally.errorRate == 0.5)
    }
}

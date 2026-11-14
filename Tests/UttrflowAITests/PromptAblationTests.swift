import Testing

@testable import UttrflowAI

@Suite("Leave-one-out prompt elements")
struct PromptAblationTests {
    private let builder = PromptBuilder.standard

    @Test("every element is listed once and the counts match what the prompt holds")
    func listsEveryElement() {
        let elements = builder.elements
        #expect(Set(elements).count == elements.count)
        let examples = elements.filter {
            switch $0 {
            case .contractExample, .blockExample: true
            default: false
            }
        }
        let blockExamples = builder.blocks.values.reduce(0) { $0 + $1.examples.count }
        #expect(examples.count == builder.contractExamples.count + blockExamples)
        #expect(elements.count > examples.count)
    }

    @Test("leaving out an example removes only that example")
    func removesOneExample() throws {
        let removed = builder.leavingOut(.contractExample(0))
        #expect(removed.contractExamples.count == builder.contractExamples.count - 1)
        #expect(removed.contractExamples == Array(builder.contractExamples.dropFirst()))
        #expect(removed.contract == builder.contract)
        #expect(removed.blocks == builder.blocks)
    }

    @Test("leaving out a contract rule line removes exactly one line")
    func removesOneRuleLine() {
        let before = builder.contract.split(separator: "\n", omittingEmptySubsequences: false)
        let removed = builder.leavingOut(.contractRule(0))
        let after = removed.contract.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(after.count == before.count - 1)
        #expect(removed.contractExamples == builder.contractExamples)
    }

    @Test("leaving out a block element changes that block alone")
    func removesFromOneBlock() throws {
        let id = try #require(builder.blocks.values.first { !$0.examples.isEmpty }?.id)
        let removed = builder.leavingOut(.blockExample(id, 0))
        #expect(removed.blocks[id]?.examples.count == (builder.blocks[id]?.examples.count ?? 0) - 1)
        for other in builder.blocks.keys where other != id {
            #expect(removed.blocks[other] == builder.blocks[other])
        }
    }

    @Test("every element costs tokens and the table lists each one with a total")
    func costsTokens() {
        for element in builder.elements { #expect(builder.tokenCost(of: element) > 0, "\(element)") }
        let table = builder.ablationCostTable().split(separator: "\n")
        #expect(table.count == builder.elements.count + 2)
        #expect(table.last?.hasSuffix("over \(builder.elements.count) elements") == true)
    }
}

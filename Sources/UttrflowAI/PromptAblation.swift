package import UttrflowCore

/// One part of the prompt that can be taken out alone: a rule line or a worked example.
package enum PromptElement: Hashable, Sendable {
    case contractRule(Int)
    case contractExample(Int)
    case blockRule(PromptBlockID, Int)
    case blockExample(PromptBlockID, Int)
}

extension PromptBuilder {
    /// Every rule line and worked example the prompt holds, the contract's first, then each block's in id order.
    package var elements: [PromptElement] {
        var found: [PromptElement] = Self.ruleLines(contract).indices.map { .contractRule($0) }
        found += contractExamples.indices.map { .contractExample($0) }
        for id in blocks.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let block = blocks[id] else { continue }
            found += Self.ruleLines(block.rules).indices.map { .blockRule(id, $0) }
            found += block.examples.indices.map { .blockExample(id, $0) }
        }
        return found
    }

    /// This prompt with exactly `element` removed and everything else as it was.
    package func leavingOut(_ element: PromptElement) -> PromptBuilder {
        switch element {
        case .contractRule(let line):
            return PromptBuilder(
                contract: Self.removingRuleLine(line, from: contract), contractExamples: contractExamples,
                blocks: blocks)
        case .contractExample(let index):
            var examples = contractExamples
            examples.remove(at: index)
            return PromptBuilder(contract: contract, contractExamples: examples, blocks: blocks)
        case .blockRule(let id, let line):
            guard let block = blocks[id] else { return self }
            return replacing(
                PromptBlock(
                    id: id, rules: Self.removingRuleLine(line, from: block.rules), examples: block.examples))
        case .blockExample(let id, let index):
            guard let block = blocks[id] else { return self }
            var examples = block.examples
            examples.remove(at: index)
            return replacing(PromptBlock(id: id, rules: block.rules, examples: examples))
        }
    }

    /// The estimated tokens the element adds to the instructions, counted as the model reads them.
    package func tokenCost(of element: PromptElement) -> Int {
        let text: String
        switch element {
        case .contractRule(let line): text = Self.ruleLines(contract)[line]
        case .blockRule(let id, let line): text = Self.ruleLines(blocks[id]?.rules ?? "")[line]
        case .contractExample(let index):
            text = ModelPrompt(rules: "", examples: [contractExamples[index]]).instructions
        case .blockExample(let id, let index):
            text = ModelPrompt(rules: "", examples: [blocks[id]?.examples[index]].compactMap { $0 }).instructions
        }
        return FoundationModelRequestBudget.estimatedTokens(in: text)
    }

    private func replacing(_ block: PromptBlock) -> PromptBuilder {
        var changed = blocks
        changed[block.id] = block
        return PromptBuilder(contract: contract, contractExamples: contractExamples, blocks: changed)
    }

    /// The non-blank lines of a rule text, which a leave-one-out run takes out one at a time.
    private static func ruleLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func removingRuleLine(_ line: Int, from text: String) -> String {
        var seen = -1
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { raw in
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
            seen += 1
            return seen != line
        }.joined(separator: "\n")
    }

    /// Each element with the tokens it costs, largest first, then the whole; the pass-rate column needs a model run.
    package func ablationCostTable() -> String {
        let rows = elements.map { ($0, tokenCost(of: $0)) }.sorted { $0.1 > $1.1 }
        let lines = rows.map { "\(String($0.1).padding(toLength: 6, withPad: " ", startingAt: 0))\($0.0)" }
        return (["tokens element"] + lines + ["\(rows.reduce(0) { $0 + $1.1 }) tokens over \(rows.count) elements"])
            .joined(separator: "\n")
    }
}

public import UttrflowCore

/// Builds the model's instructions and user prompt from three layers: the contract, the destination's block and the situation. See `Docs/cleanup.md`.
public struct PromptBuilder: Sendable, Equatable {
    /// Bumped whenever any wording changes, so a measured result can be tied to the prompt that produced it.
    public static let version = 7

    /// The label the text before a mid-sentence caret sits behind; the contract teaches the model to read it.
    public static let caretLabel = "Text before the caret:"
    /// The label the half-heard runs and their readings sit behind.
    public static let doubtfulLabel = "Doubtful words:"
    /// The most characters of preceding text quoted to the model.
    public static let caretLimit = 120

    /// The rules every destination shares.
    public let contract: String
    /// The examples every destination is shown, ahead of its block's own.
    public let contractExamples: [WorkedExample]
    public let blocks: [PromptBlockID: PromptBlock]

    public init(contract: String, contractExamples: [WorkedExample], blocks: [PromptBlockID: PromptBlock]) {
        self.contract = contract
        self.contractExamples = contractExamples
        self.blocks = blocks
    }

    /// The shipping prompt.
    public static let standard = PromptBuilder(
        contract: PromptContract.text, contractExamples: PromptContract.examples,
        blocks: PromptBlocks.standard)

    // MARK: Instructions

    /// The block the destination's formatter names, falling back to plain text's for an id no block carries.
    public func block(for destination: Destination) -> PromptBlock {
        let id = DestinationFormatter.standard(for: destination).promptBlock
        return blocks[id] ?? blocks["plain"] ?? PromptBlock(id: id, rules: "", examples: [])
    }

    /// The contract, the destination's style rules, then the shared and the destination's examples.
    public func instructions(for destination: Destination) -> String {
        let block = block(for: destination)
        let examples = (contractExamples + block.examples).map(\.rendered).joined(separator: "\n\n")
        return [contract, block.rules, "Examples:\n\(examples)"].joined(separator: "\n\n")
    }

    /// Every sentence the model is shown for a destination, so a test can prove the corpus reuses none of them.
    public func workedExamples(for destination: Destination) -> [String] {
        (contractExamples + block(for: destination).examples).flatMap(\.sentences)
    }

    /// Every sentence any destination is shown, each once.
    public var allWorkedExamples: [String] {
        var seen: Set<String> = []
        return
            (contractExamples + blocks.values.sorted { $0.id.rawValue < $1.id.rawValue }.flatMap(\.examples))
            .flatMap(\.sentences)
            .filter { seen.insert($0).inserted }
    }

    // MARK: The user prompt

    /// The situation lines above the quoted words, in the same shape as the worked examples.
    public func userPrompt(
        for request: TransformationRequest, spoken: String? = nil, doubtful: [DoubtfulSpan] = []
    ) -> String {
        let spoken = "Spoken: \"\(spoken ?? request.transcription.text)\""
        return (situationBlock(for: request.situation, doubtful: doubtful) + [spoken])
            .joined(separator: "\n")
    }

    /// The "Typed into:" line, the caret line and the doubtful-words line, each only when there is something to say.
    public func situationBlock(for situation: Situation, doubtful: [DoubtfulSpan] = []) -> [String] {
        var lines: [String] = []
        if let place = AppContextDescriber.describe(situation.app) { lines.append(place) }
        if let caret = Self.caretText(situation.insertion) { lines.append("\(Self.caretLabel) \"\(caret)\"") }
        if let readings = Self.doubtfulText(doubtful) { lines.append("\(Self.doubtfulLabel) \(readings)") }
        return lines
    }

    /// Each doubtful run, what it was heard at and the readings offered for it, or `nil` when none were.
    static func doubtfulText(_ spans: [DoubtfulSpan]) -> String? {
        guard !spans.isEmpty else { return nil }
        return spans.prefix(DoubtfulWords.maximumSpans)
            .map {
                "\"\($0.heard)\" (heard at \(hundredths($0.confidence))) — could be: "
                    + $0.candidates.joined(separator: ", ")
            }
            .joined(separator: "; ")
    }

    /// A confidence as two decimal places, without a number formatter for one number.
    static func hundredths(_ value: Double) -> String {
        let scaled = Int((min(1, max(0, value)) * 100).rounded())
        return "\(scaled / 100).\(scaled % 100 < 10 ? "0" : "")\(scaled % 100)"
    }

    /// The tail of the text before a mid-sentence caret, cut at a word boundary, or `nil` anywhere else.
    static func caretText(_ insertion: InsertionPoint, limit: Int = caretLimit) -> String? {
        guard insertion.sentenceState == .midSentence, let preceding = insertion.precedingText else {
            return nil
        }
        let flattened = TextTidy.collapseWhitespace(preceding).replacingOccurrences(of: "\"", with: "'")
        guard flattened.count > limit else { return flattened }
        let tail = flattened.suffix(limit)
        // A single word longer than the whole budget keeps the hard cut rather than vanishing.
        let kept = tail.firstIndex(of: " ").map { tail[tail.index(after: $0)...] } ?? tail
        return "…\(kept)"
    }
}

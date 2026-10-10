public import UttrflowCore

/// A language model that rewrites one short text; the boundary that keeps prompt and guards testable.
public protocol CleanupModel: Sendable {
    /// Whether this model can handle a request, chiefly whether it knows the language.
    func availability(for language: LanguageCode?) async -> TransformerAvailability

    /// Rewrites `text` under `instructions` with no wrapper or commentary, or throws `transformFailed`.
    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String

    /// Rewrites `text` under `prompt`; a chat model shows the examples as earlier turns rather than inside the instructions.
    func rewrite(
        _ text: String, prompt: ModelPrompt, kind: TransformerKind
    ) async throws(TransformationError) -> String

    /// Gets ready to rewrite under `instructions`, so the next ``rewrite`` does not pay for that.
    func warm(instructions: String) async
}

/// The contract and the destination's rules, and the worked examples apart from them.
public struct ModelPrompt: Sendable, Equatable {
    /// The contract followed by the destination's style rules.
    public let rules: String
    /// The examples, in the order the model reads them.
    public let examples: [WorkedExample]

    public init(rules: String, examples: [WorkedExample]) {
        self.rules = rules
        self.examples = examples
    }

    /// The rules with the examples written inline, for a model that takes one block of instructions.
    public var instructions: String {
        "\(rules)\n\nExamples:\n" + examples.map(\.rendered).joined(separator: "\n\n")
    }
}

extension CleanupModel {
    /// One block of instructions, which is what a model without chat turns takes.
    public func rewrite(
        _ text: String, prompt: ModelPrompt, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        try await rewrite(text, instructions: prompt.instructions, kind: kind)
    }

    /// Nothing to prepare, which is what a hosted model has.
    public func warm(instructions: String) async {}
}

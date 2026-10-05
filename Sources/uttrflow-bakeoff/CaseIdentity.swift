// What a clean-up case asks, fingerprinted, so a saved score is only compared with the same question.
import UttrflowAI
import UttrflowCore
import UttrflowEval

extension EvaluationCase {
    /// A fingerprint of everything a case is scored on; origin, split, issue, category and classes are labels and stay out.
    var identity: String {
        PromptBuilder.fingerprint(
            [
                "spoken", spoken, "expected", expected, "language", language.description,
                "destination", destination.rawValue,
                "mustBeginWith", Self.optional(mustBeginWith), "mustEndWith", Self.optional(mustEndWith),
            ] + Self.list("mustKeep", mustKeep) + Self.list("mustNotAdd", mustNotAdd)
                + Self.list("doubtful", doubtful) + Self.parts(of: context))
    }

    /// A fingerprint of every case's id and identity in id order, so adding, removing or changing any one moves it.
    static func corpusIdentity(of cases: [EvaluationCase]) -> String {
        PromptBuilder.fingerprint(cases.sorted { $0.id < $1.id }.flatMap { [$0.id, $0.identity] })
    }

    private static func optional(_ value: String?) -> String { value.map { "=" + $0 } ?? "nil" }

    private static func list(_ label: String, _ values: [String]) -> [String] {
        [label, String(values.count)] + values
    }

    private static func parts(of context: AppContext) -> [String] {
        [
            "context", optional(context.applicationName), optional(context.bundleIdentifier),
            optional(context.documentName), optional(context.selectedText), optional(context.precedingText),
            optional(context.followingText), String(context.isSecure), optional(context.accessibilityRole),
            optional(context.isMultiline.map(String.init)),
        ]
    }
}

// What a completion fixture asks, fingerprinted, so a saved fixture report is only compared with the same question.
import UttrflowAI
import UttrflowEval
import UttrflowPredict

extension Fixture {
    /// A fingerprint of every fixture input that can change its score.
    var identity: String {
        PromptBuilder.fingerprint(
            ["name", name, "typed", typed] + Self.parts(of: situation) + Self.parts(of: expectation)
                + Self.parts(of: machine) + Self.parts(of: seededCandidates))
    }

    private static func parts(of situation: GenerationSituation) -> [String] {
        [
            "situation", situation.application, String(situation.isCodeDestination),
            optional(situation.field), optional(situation.document), optional(situation.preceding),
            optional(situation.windowTitle), optional(situation.surroundings),
        ] + list("recentLines", situation.recentLines)
            + [String(situation.timedTurnLines), String(situation.isMultiline)]
            + list("choices", situation.choices)
    }

    private static func parts(of expectation: CompletionExpectation) -> [String] {
        list("acceptable", expectation.acceptable)
            + [String(expectation.lengthBand.lowerBound), String(expectation.lengthBand.upperBound)]
            + list("forbidden", expectation.forbidden)
    }

    private static func parts(of machine: [EnvironmentKind: [String]]?) -> [String] {
        guard let machine else { return ["no machine snapshot"] }
        let facts = machine.map { (kind: name(of: $0.key), values: $0.value) }.sorted { $0.kind < $1.kind }
        return ["machine snapshot", String(facts.count)] + facts.flatMap { list($0.kind, $0.values) }
    }

    private static func parts(of candidates: [Candidate]) -> [String] {
        ["candidates", String(candidates.count)]
            + candidates.flatMap { candidate in
                [
                    candidate.text, name(of: candidate.source), String(candidate.editDistance),
                    String(candidate.isIrreversible),
                ] + parts(of: candidate.evidence)
            }
    }

    /// Source fixtures seed fresh recency evidence at process launch, so its clock sample is not scenario data.
    private static func parts(of evidence: Entry?) -> [String] {
        guard let evidence else { return ["no evidence"] }
        return [
            "evidence", evidence.text, String(evidence.count), String(evidence.accepted),
            String(evidence.rejected), String(evidence.selfSourced),
        ]
    }

    private static func optional(_ value: String?) -> String { value.map { "=" + $0 } ?? "nil" }

    private static func list(_ label: String, _ values: [String]) -> [String] {
        [label, String(values.count)] + values
    }

    private static func name(of source: UttrflowPredict.CandidateSource) -> String {
        switch source {
        case .personal: "personal"
        case .environment: "environment"
        case .succession: "succession"
        }
    }

    private static func name(of kind: EnvironmentKind) -> String {
        switch kind {
        case .branch: "branch"
        case .entries(let path): "entries:\(path)"
        case .directories(let path): "directories:\(path)"
        case .executable: "executable"
        case .alias: "alias"
        case .subcommand(let program): "subcommand:\(program)"
        case .gitAlias: "gitAlias"
        }
    }
}

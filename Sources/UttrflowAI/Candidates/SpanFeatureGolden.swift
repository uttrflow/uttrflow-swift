// A committed file of invented spans and the vectors SpanFeatures must give them, read by the tests and by the fit tool.

package import Foundation
private import UttrflowCore

/// One invented span, its candidate and the evidence around it, with the vector `SpanFeatures` gave it when the file was written.
package struct SpanFeatureGoldenCase: Codable, Sendable, Equatable {
    /// One token of decoder evidence.
    package struct Token: Codable, Sendable, Equatable {
        package let logProb: Double
        package let alternatives: [Double]
    }

    package let heard: String
    package let candidate: String
    package let firstSource: Int
    package let agreement: Int
    package let before: [String]
    package let after: [String]
    package let tokens: [Token]
    package let useContext: Bool
    package let persona: SpanPersonaSnapshot?
    /// Each feature in stored form, see `SpanFeatureGolden.stored`.
    package var expected: [String]
}

/// The golden file: the spec it records, an invented language model and the cases.
package struct SpanFeatureGolden: Codable, Sendable, Equatable {
    package var specVersion: Int
    package var identifiers: [String]
    /// An invented ARPA model the context feature reads.
    package var arpa: String
    package var cases: [SpanFeatureGoldenCase]

    /// A float in the stored form that cannot change on a last bit, so a vector compares as text.
    package static func stored(_ value: Double) -> String {
        String(format: "%.11e", value == 0 ? 0.0 : value)
    }

    /// The vector `SpanFeatures` gives a case, in stored form.
    package static func computed(
        _ golden: SpanFeatureGoldenCase, model: InterpolatedLanguageModel
    ) -> [String] {
        let answers: [[Reading]] = (0..<(golden.firstSource + golden.agreement)).map {
            $0 >= golden.firstSource ? [Reading(golden.candidate)] : []
        }
        let set = HypothesisSet(
            heard: golden.heard, confidence: 0, answers: answers, before: golden.before, after: golden.after)
        guard let hypothesis = set.hypotheses.first else { return [] }
        let evidence = SpanFeatures.Evidence(
            tokens: golden.tokens.map { TokenEvidence(logProb: $0.logProb, alternatives: $0.alternatives) },
            context: golden.useContext ? model : nil, persona: golden.persona)
        return SpanFeatures.vector(of: hypothesis, in: set, evidence: evidence).map(stored)
    }

    /// The language model the file carries, or nil when it does not parse.
    package var model: InterpolatedLanguageModel? {
        (try? ARPAReader.model(from: arpa)).map { InterpolatedLanguageModel([.init(model: $0, weight: 1)]) }
    }

    /// Why this file differs from the compiled spec, one line each; empty when it matches.
    package func disagreements() -> [String] {
        var found: [String] = []
        if specVersion != SpanFeatures.specVersion {
            found.append("golden spec version \(specVersion), compiled \(SpanFeatures.specVersion)")
        }
        if identifiers != SpanFeatures.identifiers {
            found.append("golden identifiers \(identifiers), compiled \(SpanFeatures.identifiers)")
        }
        guard let model else { return found + ["golden model unreadable"] }
        for (index, golden) in cases.enumerated() {
            let now = Self.computed(golden, model: model)
            if now != golden.expected {
                found.append("case \(index) gives \(now), golden has \(golden.expected)")
            }
        }
        return found
    }

    /// The file in `data`, or why it cannot be read.
    package static func read(_ data: Data) throws -> SpanFeatureGolden {
        try JSONDecoder().decode(SpanFeatureGolden.self, from: data)
    }
}

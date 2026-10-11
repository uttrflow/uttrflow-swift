import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// One extractor turns a span and a candidate into the vector a fit and the app both weigh, pinned by a committed golden file.
@Suite("Span features")
struct SpanFeaturesTests {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent()
    /// Kept where the package already excludes a Golden folder, so a data file adds no unhandled-file warning.
    static let goldenURL = directory.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "UttrflowEvalTests/Golden/span-features.json")
    static let sources = directory.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources")

    static func golden() throws -> SpanFeatureGolden {
        try SpanFeatureGolden.read(Data(contentsOf: goldenURL))
    }

    private func vector(
        heard: String = "their", candidate: String = "there", evidence: SpanFeatures.Evidence = .init()
    ) throws -> [Double] {
        let set = HypothesisSet(heard: heard, confidence: 0, answers: [[Reading(candidate)]])
        return SpanFeatures.vector(of: try #require(set.hypotheses.first), in: set, evidence: evidence)
    }

    @Test("The committed golden file holds at least 50 spans and matches the compiled extractor")
    func goldenMatches() throws {
        let golden = try Self.golden()
        #expect(golden.cases.count >= 50)
        #expect(golden.disagreements().isEmpty)
    }

    @Test("A changed spec version, feature list or expected vector fails the golden check")
    func goldenDetectsChange() throws {
        var golden = try Self.golden()
        golden.specVersion += 1
        #expect(golden.disagreements().count == 1)
        golden = try Self.golden()
        golden.identifiers.removeLast()
        #expect(golden.disagreements().count == 1)
        golden = try Self.golden()
        golden.cases[7].expected[2] = SpanFeatureGolden.stored(0.123)
        #expect(golden.disagreements().count == 1)
    }

    @Test("Every vector is as long as the feature list and finite")
    func fixedLength() throws {
        let golden = try Self.golden()
        let model = try #require(golden.model)
        for entry in golden.cases {
            let vector = SpanFeatureGolden.computed(entry, model: model)
            #expect(vector.count == SpanFeatures.features.count)
            #expect(vector.allSatisfy { Double($0)?.isFinite == true })
        }
    }

    @Test("With no evidence every feature takes its stated missing value")
    func missingValues() throws {
        let set = HypothesisSet(heard: "zorblat", confidence: 0, answers: [[], [Reading("zorplat")]])
        let result = SpanFeatures.vector(of: try #require(set.hypotheses.first), in: set, evidence: .init())
        let missing = SpanFeatures.features.map(\.ifMissing)
        #expect(result[0] == missing[0])
        #expect(result[1] == missing[1])
        #expect(result[2] == missing[2])
        #expect(result[3] == 1)
        #expect(result[4] == 1)
        #expect(result[5] == 1)
        #expect(result[6] == missing[6])
        #expect(result[7] == missing[7])
        #expect(result[8] == missing[8])
    }

    @Test("Decoder evidence gives the mean probability, the negated entropy and the first margin")
    func decoderFeatures() throws {
        let token = TokenEvidence(logProb: log(0.5), alternatives: [log(0.25), log(0.25)])
        let result = try vector(evidence: .init(tokens: [token]))
        #expect(abs(result[0] - 0.5) < 1e-12)
        #expect(abs(result[1] - -1.0397207708399179) < 1e-9)
        #expect(abs(result[2] - 0.25) < 1e-12)
    }

    @Test("Persona counts lead by the log of one plus the difference in uses")
    func personaLead() throws {
        let persona = SpanPersonaSnapshot(counts: ["there": 3, "their": 0])
        let result = try vector(evidence: .init(persona: persona))
        #expect(abs(result[8] - log(4.0)) < 1e-12)
    }

    @Test("Each feature identifier is defined once in the shipped sources")
    func oneDefinitionEach() throws {
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)
        let enumerator = try #require(files)
        var text = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            text += try String(contentsOf: url, encoding: .utf8)
        }
        for identifier in SpanFeatures.identifiers {
            #expect(text.components(separatedBy: "\"\(identifier)\"").count == 2, "\(identifier)")
        }
    }
}

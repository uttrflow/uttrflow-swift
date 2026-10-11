import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// The romanised-names class: a case-sensitive score beside the case-folded word error rate, which cannot see a missing capital. See `Docs/latin-output.md`.
@Suite("The romanised names corpus")
struct RomanisedNameCorpusTests {
    static func run(_ nameCase: RomanisedNameCase) async throws -> String {
        let app = AppContext().adding(onScreenNames: nameCase.onScreenNames)
        let request = TransformationRequest(
            transcription: Transcription(text: nameCase.spoken),
            situation: Situation(app: app, insertion: .unknown, destination: .plain),
            vocabulary: nameCase.dictionary)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test("holds at least twenty cases with unique ids, all in Devanagari")
    func size() {
        #expect(RomanisedNameCorpus.all.count >= 20)
        #expect(Set(RomanisedNameCorpus.all.map(\.id)).count == RomanisedNameCorpus.all.count)
        #expect(RomanisedNameCorpus.all.allSatisfy { Romaniser.containsDevanagari($0.spoken) })
    }

    @Test("every name a source the person owns can spell is written with its capital")
    func ownedNamesKeepTheirCapital() async throws {
        for nameCase in RomanisedNameCorpus.all where nameCase.reach == .owned {
            #expect(try await Self.run(nameCase) == nameCase.expected, "\(nameCase.id)")
        }
    }

    @Test("a name no owned source holds stays lower case, and nothing else gains a capital")
    func unownedAndControl() async throws {
        let score = try await RomanisedNameCorpus.score(Self.run)
        #expect(score.nameAccuracy(.owned) == 1)
        #expect(score.nameAccuracy(.unowned) == 0)
        #expect(score.lowerCaseAccuracy == 1)
    }
}

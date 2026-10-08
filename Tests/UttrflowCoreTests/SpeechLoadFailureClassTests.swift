// Tests the class a failed speech model load is given.
import Testing

@testable import UttrflowCore

@Suite("SpeechLoadFailureClass")
struct SpeechLoadFailureClassTests {
    @Test(
        "each load error gets its class",
        arguments: [
            (SpeechEngineError.modelNotInstalled, SpeechLoadFailureClass.missingFiles),
            (.modelDamaged(fileCount: 2), .damaged),
            (.modelLoadFailed(description: "fixture"), .other),
            (.transcriptionFailed(description: "fixture"), .other),
        ])
    func classOfError(error: SpeechEngineError, expected: SpeechLoadFailureClass) {
        #expect(SpeechLoadFailureClass(error) == expected)
    }

    @Test("an error from outside the recogniser is other")
    func foreignErrorIsOther() {
        #expect(SpeechLoadFailureClass(CancellationError()) == .other)
    }

    @Test("every class has its own summary")
    func summariesDiffer() {
        let summaries = Set(SpeechLoadFailureClass.allCases.map(\.summary))
        #expect(summaries.count == SpeechLoadFailureClass.allCases.count)
    }
}

import Testing

@testable import UttrflowEval

@Suite("Transcription cross-side leakage")
struct TranscriptionCrossSideLeakTests {
    private static let shared = "amber birch cedar daisy elm fern golden hazel"

    @Test(
        "fit and calibration overlap is reported once regardless of input order",
        arguments: [TranscriptionSplit.fit, .calibration])
    func fitAndCalibration(first: TranscriptionSplit) {
        let fit = passage("split-fit")
        let calibration = passage("split-calibration")
        let additions = first == .fit ? [fit, calibration] : [calibration, fit]
        let audit = audit(additions, sides: [fit.id: .fit, calibration.id: .calibration])
        #expect(
            audit.findings == [
                .sharedRun(
                    passageID: calibration.id, side: .calibration,
                    testPassageID: fit.id, words: Self.shared)
            ])
    }

    @Test("a shared run inside one side remains permitted", arguments: TranscriptionSplit.allCases)
    func sameSide(side: TranscriptionSplit) {
        let first = passage("split-first")
        let second = passage("split-second")
        #expect(audit([first, second], sides: [first.id: side, second.id: side]).findings == [])
    }

    @Test("existing test-side findings stay first with their exact contents")
    func testSideOrder() {
        let fit = passage("split-fit")
        let calibration = passage("split-calibration")
        let test = passage("split-test")
        let findings = audit(
            [fit, calibration, test],
            sides: [fit.id: .fit, calibration.id: .calibration, test.id: .test]
        ).findings
        #expect(
            findings == [
                .sharedRun(passageID: fit.id, side: .fit, testPassageID: test.id, words: Self.shared),
                .sharedRun(
                    passageID: calibration.id, side: .calibration,
                    testPassageID: test.id, words: Self.shared),
                .sharedRun(
                    passageID: calibration.id, side: .calibration,
                    testPassageID: fit.id, words: Self.shared),
            ])
    }

    @Test(
        "distinct text and shared runs shorter than eight words do not leak",
        arguments: [
            "amber birch cedar daisy elm fern golden", "iris juniper kelp lily maple nettle oak poppy",
        ])
    func noSharedRun(other: String) {
        let fit = passage("split-fit")
        let calibration = TranscriptionCase(
            id: "split-calibration", language: .english,
            stressor: .everyday, romanised: other)
        #expect(
            audit([fit, calibration], sides: [fit.id: .fit, calibration.id: .calibration]).findings == [])
    }

    private func passage(_ id: String) -> TranscriptionCase {
        TranscriptionCase(id: id, language: .english, stressor: .everyday, romanised: Self.shared)
    }

    private func audit(
        _ additions: [TranscriptionCase], sides: [String: TranscriptionSplit]
    ) -> SplitLeakAudit {
        SplitLeakAudit(
            passages: TranscriptionCorpus.all + additions,
            assignment: TranscriptionSplit.assignment.merging(sides) { _, new in new })
    }
}

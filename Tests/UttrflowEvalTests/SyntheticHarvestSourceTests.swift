// Tests the synthetic-voice source of harvest manifests and coverage on real calibration-split errors.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("SyntheticHarvestSource")
struct SyntheticHarvestSourceTests {
    private let voices = [
        SyntheticHarvestSource.Voice(name: "Samantha", voiceClass: "en_US"),
        SyntheticHarvestSource.Voice(name: "Rishi", voiceClass: "en_IN"),
    ]

    @Test func aVoiceArgumentIsNameAndClass() {
        #expect(
            SyntheticHarvestSource.Voice(argument: "Samantha:en_US")
                == SyntheticHarvestSource.Voice(name: "Samantha", voiceClass: "en_US"))
        #expect(SyntheticHarvestSource.Voice(argument: "Samantha") == nil)
        #expect(SyntheticHarvestSource.Voice(argument: ":en_US") == nil)
    }

    @Test func everySentenceIsReadByEveryVoiceAtEveryRateWithStableFileNames() {
        let sentences = ["The blue folder\tis open.", "", "Ship it\non Friday."]
        let first = SyntheticHarvestSource.takes(sentences: sentences, voices: voices, rates: [160, 220])
        let second = SyntheticHarvestSource.takes(sentences: sentences, voices: voices, rates: [160, 220])
        #expect(first == second)
        #expect(first.count == 2 * 2 * 2)
        #expect(Set(first.map(\.file)).count == first.count)
        #expect(first[0].file == "0-samantha-160.wav")
        #expect(first[0].text == "The blue folder is open.")
        #expect(first.last?.text == "Ship it on Friday.")
    }

    @Test func theManifestIsOneHarvestLinePerTakeWithClassAsGroupAndVoiceAtRateAsSpeaker() {
        let takes = SyntheticHarvestSource.takes(sentences: ["Open the door."], voices: voices, rates: [180])
        let entries = AccentSlice.entries(SyntheticHarvestSource.manifest(takes))
        #expect(entries == takes.map(\.entry))
        #expect(
            entries[1]
                == AccentSlice.Entry(
                    audio: "0-rishi-180.wav", reference: "Open the door.", group: "en_IN",
                    speaker: "Rishi@180"))
    }

    @Test func coverageOnRealErrorsCountsOnlyCalibrationSplitSubstitutions() throws {
        let calibration = try #require(TranscriptionSplit.assignment.first { $0.value == .calibration }?.key)
        let fit = try #require(TranscriptionSplit.assignment.first { $0.value == .fit }?.key)
        let errors = ConfusionHarvest.calibrationErrors([
            score(
                calibration, reference: ["the", "vest", "is", "cold"], heard: ["the", "west", "is", "gold"]),
            score(fit, reference: ["a", "long", "road"], heard: ["a", "wrong", "road"]),
        ])
        #expect(errors.map { [$0.0, $0.1] } == [["vest", "west"], ["cold", "gold"]])
        let table = ConfusionHarvest.table(
            [
                HarvestUtterance(
                    reference: ["vest"], recognised: ["west"], group: "en_IN", speaker: "Rishi@160")
            ],
            provenance: HarvestProvenance(
                dataset: "synthetic", version: "1", licence: "none", engine: "whisperKit test", seed: 1),
            minimumSpeakers: 1)
        #expect(ConfusionHarvest.coverage(of: table, errors: errors) == 0.5)
        #expect(ConfusionHarvest.coverage(of: table, errors: []) == nil)
    }

    @Test func theSyntheticSourceReadsNoLexiconOrCandidateSource() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UttrflowEval/SyntheticHarvestSource.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        for name in ["PhoneticIndex", "Homophones", "UttrflowDictionary", "CandidateSource"] {
            #expect(!text.contains(name), "\(name)")
        }
    }
}

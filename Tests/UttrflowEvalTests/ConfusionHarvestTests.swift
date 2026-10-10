// Tests the accented-speech confusion table: what it keeps, how it groups, and that it is reproducible.
import Foundation
import Testing
import UttrflowEval

@Suite("ConfusionHarvest")
struct ConfusionHarvestTests {
    private let provenance = HarvestProvenance(
        dataset: "example", version: "1", licence: "CC0", engine: "whisperKit test", seed: 7)

    private func utterance(
        _ reference: String, _ recognised: String, group: String, speaker: String
    )
        -> HarvestUtterance
    {
        HarvestUtterance(
            reference: reference.split(separator: " ").map(String.init),
            recognised: recognised.split(separator: " ").map(String.init), group: group, speaker: speaker)
    }

    private var utterances: [HarvestUtterance] {
        [
            utterance("the vest is red", "the west is red", group: "hi", speaker: "s1"),
            utterance("i think so", "i tink so", group: "hi", speaker: "s2"),
            utterance("the vest is red", "the west is red", group: "ta", speaker: "s3"),
            utterance("a long road", "a wrong road", group: "ta", speaker: "s4"),
        ]
    }

    @Test func classesReadTheContrastFromTheSpellings() {
        #expect(ConfusionClass(reference: "vest", recognised: "west") == .vw)
        #expect(ConfusionClass(reference: "think", recognised: "tink") == .th)
        #expect(ConfusionClass(reference: "light", recognised: "right") == .lr)
        #expect(ConfusionClass(reference: "zip", recognised: "sip") == .sz)
        #expect(ConfusionClass(reference: "ship", recognised: "sip") == .shs)
        #expect(ConfusionClass(reference: "hair", recognised: "air") == .hDropping)
        #expect(ConfusionClass(reference: "cold", recognised: "col") == .finalConsonant)
        #expect(ConfusionClass(reference: "ship", recognised: "sheep") == .vowel)
        #expect(ConfusionClass(reference: "cache", recognised: "cash") == .other)
    }

    @Test func groupsBelowTheSpeakerFloorAreMergedIntoOther() {
        let table = ConfusionHarvest.table(utterances, provenance: provenance, minimumSpeakers: 2)
        #expect(Set(table.pairs.map(\.group)) == ["hi", "ta"])
        let merged = ConfusionHarvest.table(utterances, provenance: provenance, minimumSpeakers: 3)
        #expect(Set(merged.pairs.map(\.group)) == ["other"])
        #expect(merged.pairs.first { $0.reference == "vest" }?.count == 2)
    }

    @Test func theTableHoldsOnlyWordPairsCountsAndProvenance() throws {
        let table = ConfusionHarvest.table(utterances, provenance: provenance, minimumSpeakers: 2)
        let json = try #require(String(data: JSONEncoder().encode(table), encoding: .utf8))
        #expect(!json.contains("s1") && !json.contains("is red"))
        #expect(table.classes.contains { $0.group == "hi" && $0.confusionClass == "v/w" && $0.count == 1 })
    }

    @Test func twoRunsOverTheSameInputGiveTheSameDigest() {
        let first = ConfusionHarvest.table(utterances, provenance: provenance, minimumSpeakers: 2)
        let second = ConfusionHarvest.table(utterances.reversed(), provenance: provenance, minimumSpeakers: 2)
        #expect(first == second)
        #expect(first.digest == second.digest)
    }

    @Test func coverageIsTheShareOfHeldOutErrorsTheTableHolds() {
        let table = ConfusionHarvest.table(
            Array(utterances.prefix(2)), provenance: provenance, minimumSpeakers: 1)
        #expect(ConfusionHarvest.coverage(of: table, on: Array(utterances.suffix(2))) == 0.5)
        #expect(ConfusionHarvest.coverage(of: table, on: []) == nil)
    }

    @Test func theHarvestReadsNoLexiconOrCandidateSource() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UttrflowEval/ConfusionHarvest.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        for name in ["PhoneticIndex", "Homophones", "UttrflowDictionary", "CandidateSource"] {
            #expect(!text.contains(name), "\(name)")
        }
    }
}

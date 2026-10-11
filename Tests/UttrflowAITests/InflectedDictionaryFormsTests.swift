import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary
import UttrflowTestSupport

@testable import UttrflowAI

/// A dictionary word said with a plural, possessive or verb ending still finds its entry. See Docs/cleanup.md.
@Suite("Inflected dictionary forms")
struct InflectedDictionaryFormsTests {
    /// Invented entries and the inflected form each is heard as, lower-cased the way a recogniser writes an unknown word.
    static let probe: [(entry: String, heard: String)] = [
        ("Kubelet", "kubelets"), ("Orvanta", "orvanta's"), ("Zentrix", "zentrixes"),
        ("Quorvane", "quorvanes"), ("Lumexa", "lumexa's"), ("Bravinth", "bravinths"),
        ("Tesmora", "tesmora’s"), ("Klarvox", "klarvox's"), ("Nydrel", "nydrels"),
        ("Vexalon", "vexalon's"), ("Falquist", "falquists"), ("Driomar", "driomar’s"),
        ("Pexton", "pextons"), ("Solvane", "solvane's"), ("Merivox", "merivox’s"),
        ("Halcrest", "halcrests"), ("Truvana", "truvana's"), ("Zephlin", "zephlins"),
        ("Corvexa", "corvexa’s"), ("Galdrin", "galdrins"), ("Qualtrex", "qualtrexed"),
        ("Vornik", "vorniked"), ("Selvaro", "selvaroed"), ("Plintar", "plintared"),
        ("Ruvex", "ruvexed"), ("Jexmond", "jexmonding"), ("Calvirn", "calvirning"),
        ("Wendrix", "wendrixing"), ("Brindlecomb", "brindlecombing"), ("Taskwell", "taskwelling"),
    ]

    /// The probe entries filed in one index, with one fixed date so bucket order is the same every run.
    static let index = PhoneticIndex(
        entries: probe.map {
            DictionaryEntry(word: $0.entry, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        })

    /// The probe forms offered their entry, by the whole-word lookup alone or with the ending set aside.
    static func offered() -> (whole: [String], all: [String]) {
        var whole: [String] = []
        var all: [String] = []
        for pair in probe {
            let found = WordCorrectionEngine.spellings(of: pair.heard, in: index).filter {
                $0.entry.word == pair.entry
            }
            if found.contains(where: { $0.ending.isEmpty }) { whole.append(pair.heard) }
            if !found.isEmpty { all.append(pair.heard) }
        }
        return (whole, all)
    }

    @Test("every plural and possessive in the probe is offered its entry")
    func probeOfferedRate() throws {
        let (whole, all) = Self.offered()
        print(
            "PROBE whole-word \(whole.count)/\(Self.probe.count) \(whole); with endings \(all.count)/\(Self.probe.count) \(all)"
        )
        for pair in Self.probe {
            try QualityGridReport.emit(
                suite: "inflected", id: "\(pair.entry)/\(pair.heard)",
                passed: WordForms.nameEnding(of: pair.heard) == nil ? nil : all.contains(pair.heard),
                measurements: [
                    "whole": whole.contains(pair.heard) ? 1 : 0, "all": all.contains(pair.heard) ? 1 : 0,
                ])
        }
        let named = Self.probe.filter { WordForms.nameEnding(of: $0.heard) != nil }.map(\.heard)
        #expect(Set(named).isSubset(of: Set(all)), "missed \(Set(named).subtracting(all).sorted())")
    }

    @Test(
        "a heard plural keeps the entry's spelling and its own ending",
        arguments: [
            ("kubelets", "Kubelets"), ("orvanta's", "Orvanta's"), ("tesmora\u{2019}s", "Tesmora\u{2019}s"),
        ])
    func reattachesTheEndingVerbatim(heard: String, written: String) {
        let words = WordCorrectionEngine.spellings(of: heard, in: Self.index).map(\.word)
        #expect(words.contains(written), "\(heard) → \(words)")
        #expect(!words.contains("Kubelet's"))
    }

    @Test("the correction engine writes a doubted plural with the entry's spelling")
    func proposesTheInflectedSpelling() throws {
        let utterance = CorrectionFixtures.spoken(
            "the Kubelet log says restart the ?kubelits on every node before the rollout tonight")
        let proposal = try #require(
            WordCorrectionEngine().proposals(
                for: utterance, against: Self.index, seeing: CorrectionFixtures.showing("Kubelet logs")
            ).first)
        #expect(proposal.replacement == "Kubelets")
    }

    @Test("a name already written with its ending is left alone")
    func leavesAWrittenPluralAlone() {
        #expect(WordCorrectionEngine.spellings(of: "Kubelets", in: Self.index).isEmpty)
        #expect(WordCorrectionEngine.spellings(of: "Orvanta's", in: Self.index).isEmpty)
    }

    @Test("a short word keeps its ending to itself")
    func shortWordsAreNotSplit() {
        #expect(WordForms.nameEnding(of: "its") == nil)
        #expect(WordForms.nameEnding(of: "bus")?.name == nil)
    }

    /// Correct sentences whose plurals and possessives sound like the fixture dictionary's names.
    static let alreadyCorrectPlurals = [
        "She wrote two sonnets about the harbour at dawn",
        "The kestrels hovered above the motorway verge",
        "Both mavens of modern architecture spoke first",
        "The bears clawed the bark off the young trees",
        "The clouds thickened over the estuary at noon",
        "Three nickels rolled under the old sofa",
        "The griffins guarded the gate in the fresco",
        "My sister's postcards arrived from the coast",
        "The redistricting maps were redrawn twice",
        "Her editors reviewed the chapters this morning",
    ]

    @Test(
        "changes nothing in a correct sentence with plurals, the whole dictionary on screen",
        arguments: alreadyCorrectPlurals)
    func leavesCorrectPluralsAlone(sentence: String) {
        let proposals = WordCorrectionEngine().proposals(
            for: CorrectionFixtures.doubting(sentence), against: CorrectionFixtures.index,
            seeing: CorrectionFixtures.showingEverything)
        #expect(proposals.isEmpty, "\(sentence) → \(proposals.map(\.replacement))")
    }
}

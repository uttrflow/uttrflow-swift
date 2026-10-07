// Weeks of learning through the real learner and corrector, scored on persona-free speech. See Docs/learning-simulator.md.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary
import UttrflowTestSupport

@testable import UttrflowAI

/// How the edits a person makes over a selection are generated, each week.
private enum EditModel: String, CaseIterable, Sendable {
    /// Nothing is learnt; the dictionary stays empty.
    case noLearning = "no learning"
    /// Every edit in the corpus is made exactly as written.
    case rightPersona = "right persona"
    /// One edit in five writes a misspelling of what was meant.
    case wrongEdits = "20% wrong edits"
    /// One application rewrites the last word of every dictation into its own respelling.
    case scriptedPage = "scripted page"
}

/// The rates the simulation runs at, stated once so the report can quote them.
private enum Rates {
    static let weeks = 8
    static let wrongEditShare = 0.2
    /// The share of wrong overrides a person undoes; the rest are left in place.
    static let undoShare = 0.7
    /// The confidence a doubted word is heard at, under the corrector's threshold.
    static let doubted = 0.3
    static let clear = 0.95
    static let seed = 4513
    /// The application whose page rewrites what lands, in the scripted-page model.
    static let scriptingApplication = "Browser"
}

/// One sentence of persona-free speech; words starred are heard doubtfully, and every word is right.
private let heldOut: [String] = [
    "the *core* *vain* argument fell apart", "a *tall* *more* careful plan",
    "buy a *brick* *cell* phone case",
    "the *new* *jello* recipe set well", "she *knew* the answer", "*right* a short note",
    "a *hole* in the road",
    "*there* car is outside", "wait *by* the door", "*four* chairs and a table", "a *meat* pie for lunch",
    "the *peace* talks resumed", "the *van* *drill* was loud", "*so* *rent* was due",
    "the *pick* *sore* a fruit",
    "*tess* *rah* came by", "the *fen* *nick* in the wall", "a *larva* in the pond",
    "the *ombre* *mix* of paint",
    "the *talk* *mora* rule in poetry", "*jazz* *trail* at the festival", "*drum* *let* the band play",
    "the *pix* *aura* was bright", "the *core* *van* left early", "*zen* *traffic* in the morning",
    "the *quarter* *bit* moved", "*kelp* *arrow* in the sea", "the *brick* *sell* off",
    "a *new* *vellum* page",
    "the *sore* *rent* stayed high", "*in* *box* the gifts", "a *screen* *shot* of light",
    "the *draft* was cold",
    "*weather* or not", "the *final* *copy* of the deed", "*notes* from class",
]

/// A doubted run from the corpus's own mishearings and the term it should become.
private struct Probe {
    let utterance: Utterance
    let term: String
    /// The window it was spoken in, with its title, as the corrector sees it.
    let context: AppContext
}

/// One week's score for one edit model.
private struct WeekScore {
    let week: Int
    let entries: Int
    let heldOutWords: Int
    let falseOverrides: Int
    let probesFixed: Int
    let probes: Int

    /// False overrides per thousand held-out words, which equals the word error the learner added there.
    var falseOverridesPerThousand: Double { Double(falseOverrides) * 1_000 / Double(heldOutWords) }
}

/// What a whole run produced: the weekly curve and the evidence the learner constants are chosen from.
private struct RunReport {
    let model: EditModel
    var weeks: [WeekScore] = []
    /// Most entries the learner took in on one simulated day.
    var mostLearnedInADay = 0
    /// For each entry that was ever undone, how many uses it had before its first undo.
    var usesBeforeFirstUndo: [String: Int] = [:]
    /// For each term-spelled entry, uses it survived with no undo.
    var cleanUses: [String: Int] = [:]
}

/// Builds an utterance from a starred sentence.
private func utterance(_ sentence: String) -> Utterance {
    Utterance(
        words: sentence.split(separator: " ").map { token in
            let doubted = token.hasPrefix("*")
            return SpokenWord(
                text: doubted ? String(token.dropFirst().dropLast()) : String(token),
                confidence: doubted ? Rates.doubted : Rates.clear)
        })
}

/// The corpus's mishearings whose fix is a real term, each heard doubtfully inside its sentence.
private func probes() -> [Probe] {
    LearnedWordReplay.dictations.compactMap { dictation in
        guard let selection = dictation.selection,
            LearnedWordReplay.realTerms.contains(dictation.wrote.lowercased())
        else { return nil }
        let doubted = Set(selection.split(separator: " ").map(String.init))
        return Probe(
            utterance: Utterance(
                words: dictation.heard.split(separator: " ").map {
                    SpokenWord(
                        text: String($0),
                        confidence: doubted.contains(String($0)) ? Rates.doubted : Rates.clear)
                }),
            term: dictation.wrote,
            context: AppContext(applicationName: dictation.application, documentName: dictation.title))
    }
}

/// A misspelling of what was meant: two inner letters swapped, which still reads alike.
private func misspelt(_ word: String) -> String {
    var letters = Array(word)
    guard letters.count > 3 else { return word + String(letters.last ?? "e") }
    letters.swapAt(1, 2)
    return String(letters)
}

/// The scripted page's respelling of a word: capitalised, with its last letter doubled.
private func respelt(_ word: String) -> String {
    guard let last = word.last else { return word }
    return word.prefix(1).uppercased() + word.dropFirst() + String(last)
}

/// One dictation as the edit model lands it: the selection it was spoken over and what was written.
private func landed(
    _ dictation: LearnedWordReplay.Dictation, under model: EditModel, using random: inout Seeded
) -> (selection: String?, wrote: String) {
    switch model {
    case .noLearning, .rightPersona:
        return (dictation.selection, dictation.wrote)
    case .wrongEdits:
        guard dictation.selection != nil, random.chance(Rates.wrongEditShare) else {
            return (dictation.selection, dictation.wrote)
        }
        return (dictation.selection, misspelt(dictation.wrote))
    case .scriptedPage:
        guard dictation.application == Rates.scriptingApplication,
            let last = dictation.heard.split(separator: " ").last
        else { return (dictation.selection, dictation.wrote) }
        return (String(last), respelt(String(last)))
    }
}

/// Runs one edit model for the stated weeks and scores every week.
private func simulate(_ model: EditModel) async throws -> RunReport {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "uttrflow-learning-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = PersonalDictionaryStore(file: folder.appending(path: "dictionary.v1.json"))
    let engine = WordCorrectionEngine()
    var random = Seeded(seed: Rates.seed)
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let corpus = LearnedWordReplay.dictations
    let perDay = max(1, corpus.count / 7)
    let checks = probes()
    var report = RunReport(model: model)

    for week in 1...Rates.weeks {
        var learnedToday: [Int: Int] = [:]
        if model != .noLearning {
            for (index, dictation) in corpus.shuffled(using: &random).enumerated() {
                let (selection, wrote) = landed(dictation, under: model, using: &random)
                let day = (week - 1) * 7 + index / perDay
                let learnt = try await store.learn(
                    heard: dictation.heard, wrote: wrote,
                    seeing: AppContext(
                        applicationName: dictation.application, documentName: dictation.title,
                        selectedText: selection),
                    at: start.addingTimeInterval(Double(day * 86_400 + index * 60)))
                learnedToday[day, default: 0] += learnt.count
            }
        }
        report.mostLearnedInADay = max(report.mostLearnedInADay, learnedToday.values.max() ?? 0)

        let entries = await store.allEntries()
        let index = PhoneticIndex(entries: entries)
        var falseOverrides = 0
        var words = 0
        for sentence in heldOut {
            let spoken = utterance(sentence)
            words += spoken.words.count
            for proposal in engine.proposals(for: spoken, against: index) {
                falseOverrides += proposal.wordRange.count
                try await record(
                    proposal, wasWrong: true, in: store, entries: entries, into: &report, using: &random)
            }
        }
        var fixed = 0
        for probe in checks {
            for proposal in engine.proposals(for: probe.utterance, against: index, seeing: probe.context) {
                let isRight = proposal.replacement.lowercased() == probe.term.lowercased()
                if isRight { fixed += 1 }
                try await record(
                    proposal, wasWrong: !isRight, in: store, entries: entries, into: &report, using: &random)
            }
        }
        report.weeks.append(
            WeekScore(
                week: week, entries: entries.count, heldOutWords: words, falseOverrides: falseOverrides,
                probesFixed: fixed, probes: checks.count))
    }
    return report
}

/// Counts a use against the entry, undoes a wrong one at the stated share, and notes when its first undo came.
private func record(
    _ proposal: WordCorrection, wasWrong: Bool, in store: PersonalDictionaryStore, entries: [DictionaryEntry],
    into report: inout RunReport, using random: inout Seeded
) async throws {
    guard let entry = try await store.recordUse(of: proposal.entryID) else { return }
    if wasWrong, random.chance(Rates.undoShare) {
        try await store.recordRevert(of: proposal.entryID)
        if report.usesBeforeFirstUndo[entry.word] == nil {
            report.usesBeforeFirstUndo[entry.word] = entry.timesUsed - 1
        }
    } else if !wasWrong, entry.timesReverted == 0 {
        report.cleanUses[entry.word] = entry.timesUsed
    }
}

/// The ceiling: learning may add at most this many false overrides per thousand persona-free words, at any week.
private let falseOverrideCeilingPerThousand = 6.0

@Suite("Weeks of simulated learning, scored for harm on persona-free speech")
struct LearningDynamicsSimulatorTests {
    @Test("No edit model lifts false overrides on persona-free speech past the ceiling at any week")
    func learningStaysUnderTheHarmCeiling() async throws {
        var reports: [RunReport] = []
        for model in EditModel.allCases {
            reports.append(try await simulate(model))
        }
        let floor = reports[0].weeks.map(\.falseOverridesPerThousand)
        for report in reports {
            let curve = report.weeks.map {
                "w\($0.week) entries \($0.entries) fo/1k \(String(format: "%.1f", $0.falseOverridesPerThousand)) "
                    + "fixed \($0.probesFixed)/\($0.probes)"
            }
            print("Learning simulator [\(report.model.rawValue)]: \(curve.joined(separator: "; "))")
            print(
                "Learning simulator [\(report.model.rawValue)] most learnt in a day \(report.mostLearnedInADay); "
                    + "uses before first undo \(report.usesBeforeFirstUndo.sorted { $0.key < $1.key }); "
                    + "clean uses \(report.cleanUses.sorted { $0.key < $1.key })")
            for (week, score) in report.weeks.enumerated() {
                #expect(
                    score.falseOverridesPerThousand - floor[week] <= falseOverrideCeilingPerThousand,
                    "\(report.model.rawValue) week \(score.week)")
            }
        }
        let undone = reports.flatMap(\.usesBeforeFirstUndo.values)
        let kept = reports.flatMap(\.cleanUses.values)
        for count in 1...6 {
            print(
                "Learning simulator promotion \(count): harmful caught provisional "
                    + "\(undone.filter { $0 < count }.count)/\(undone.count); "
                    + "real terms promoted \(kept.filter { $0 >= count }.count)/\(kept.count)")
        }
        // The chosen count must still be provisional at every harmful entry's first undo and promote every kept term.
        #expect(undone.allSatisfy { $0 < DictionaryEntry.promotionUses })
        #expect(kept.allSatisfy { $0 >= DictionaryEntry.promotionUses })
    }
}

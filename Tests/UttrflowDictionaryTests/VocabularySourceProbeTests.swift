// Probe: what window titles, selections and typed lines each yield as new vocabulary for an invented persona.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowDictionary

/// One invented working day: what was on screen, typed, corrected and dictated.
private struct ProbeDay {
    let title: String
    let typed: [String]
    let dictated: [String]
    let corrections: [(selected: String, wrote: String)]
}

/// An invented persona: the terms a correct dictionary would hold, and a fortnight of work.
private struct ProbePersona {
    let name: String
    let truth: Set<String>
    let days: [ProbeDay]
}

/// What one source proposed over the fortnight.
private struct SourceYield: Equatable {
    var proposed: Set<String> = []
    var learntOnDay: [String: Int] = [:]

    func correct(_ truth: Set<String>) -> Int { proposed.filter { truth.contains($0) }.count }
    var unknownToGeneralVocabulary: Int { proposed.filter(GeneralVocabulary.isWorthLearning).count }
    var medianDay: Int? {
        let days = learntOnDay.values.sorted()
        return days.isEmpty ? nil : days[(days.count - 1) / 2]
    }
}

private enum Source: String, CaseIterable { case title, selection, typed }

/// Runs each source through the existing candidate rules; no store is touched.
private func probe(_ persona: ProbePersona) -> [Source: SourceYield] {
    var ledgers: [Source: SightingLedger] = [.title: SightingLedger(), .typed: SightingLedger()]
    var yields: [Source: SourceYield] = [:]
    func keep(_ terms: [String], from source: Source, day: Int) {
        for term in terms where yields[source, default: SourceYield()].proposed.insert(term).inserted {
            yields[source, default: SourceYield()].learntOnDay[term] = day
        }
    }
    for (index, day) in persona.days.enumerated() {
        let dayNumber = index + 1
        // The typed source reads only that day's committed lines, as the screen the speech is matched against.
        let typedScreen = day.typed.joined(separator: " ")
        for heard in day.dictated {
            for (source, seen) in [(Source.title, day.title), (.typed, typedScreen)] {
                let terms = LearnableWords.seenAndSaid(heard: heard, seeing: AppContext(documentName: seen))
                keep(
                    ledgers[source, default: SightingLedger()].record(terms, on: dayNumber).learnt,
                    from: source, day: dayNumber)
            }
        }
        for correction in day.corrections {
            if let learnt = LearnableWords.corrected(over: correction.selected, wrote: correction.wrote) {
                keep([learnt], from: .selection, day: dayNumber)
            }
        }
    }
    return yields
}

/// An invented backend engineer; every name and tool is made up.
private let engineer = ProbePersona(
    name: "engineer",
    truth: ["Zorvik", "Tamsyn", "Quillon", "Brevka", "Nalaprit", "Dovecraft"],
    days: (1...14).map { day in
        let project = day <= 7 ? "Zorvik" : "Quillon"
        return ProbeDay(
            title: "\(project)\(day) migration plan",
            typed: [
                "ping Tamsyn about the \(project) rollout",
                "Brevka queue is stuck again, Dovecraft retry",
                "asdfgh wip Nalaprit fixtures",
            ],
            dictated: [
                "ask tamsin to review the \(project == "Zorvik" ? "zorvick" : "quillan") change",
                "the brefka queue needs a dovecraft retry",
                "nalapreet fixtures are ready",
            ],
            corrections: day % 5 == 0
                ? [(selected: "tamsin", wrote: "Tamsyn"), (selected: "their", wrote: "there")] : [])
    })

/// An invented clinic administrator; every name and place is made up.
private let administrator = ProbePersona(
    name: "administrator",
    truth: ["Rhosmere", "Ilvane", "Okonta", "Pemberlin", "Sarvadi"],
    days: (1...14).map { day in
        ProbeDay(
            title: day % 2 == 0 ? "Rhosmere rota" : "Inbox",
            typed: [
                "Dr Okonta clinic moved to Thursday",
                "Pemberlin invoices sent, Sarvadi pending",
                "Kavlothra referral form",
            ],
            dictated: [
                "doctor okonto is running late at rosmere",
                "please chase the pemberline invoices",
                day % 3 == 0 ? "ilvain wants the rota by friday" : "thanks see you tomorrow",
            ],
            corrections: day == 4 ? [(selected: "ilvain", wrote: "Ilvane")] : [])
    })

@Suite("Vocabulary source probe")
struct VocabularySourceProbeTests {
    /// Prints the per-source table Docs/app-dictionary.md records, and pins it so the page cannot drift.
    @Test("Each source's yield on the invented personas", arguments: [0, 1])
    func yieldPerSource(_ which: Int) {
        let persona = [engineer, administrator][which]
        let yields = probe(persona)
        var measured: [String] = []
        for source in Source.allCases {
            let yield = yields[source] ?? SourceYield()
            let row = [
                persona.name, source.rawValue, "\(yield.proposed.count)", "\(yield.correct(persona.truth))",
                "\(persona.truth.count)", "\(yield.unknownToGeneralVocabulary)",
                yield.medianDay.map(String.init) ?? "-",
            ].joined(separator: " | ")
            print("probe | \(row)")
            measured.append(row)
        }
        #expect(measured == expected[which])
    }

    /// The shipped aggregation: titles and typed lines through the store's one ledger, as the pipeline calls it.
    @Test("The store learns from typed lines what the probe's typed row found", arguments: [0, 1])
    func storeAggregatesTypedLines(_ which: Int) async throws {
        let persona = [engineer, administrator][which]
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for (index, day) in persona.days.enumerated() {
            let moment = epoch.addingTimeInterval(Double(index) * 86_400)
            for heard in day.dictated {
                try await store.learn(
                    heard: heard, wrote: heard,
                    seeing: AppContext(applicationName: "Editor", documentName: day.title),
                    typed: day.typed, at: moment)
            }
        }
        let learnt = Set(await store.allEntries().filter { $0.origin == .observed }.map(\.word))
        let typed = probe(persona)[.typed]?.proposed ?? []
        #expect(learnt == typed.union(probe(persona)[.title]?.proposed ?? []))
        #expect(learnt.isSubset(of: persona.truth))
    }

    /// The dictionary file holds the matched term, never the typed line.
    @Test("No typed line is written to the dictionary")
    func typedLinesAreNotKept() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for day in 0..<3 {
            try await store.learn(
                heard: "ask tamsin", wrote: "ask tamsin", seeing: AppContext(applicationName: "Editor"),
                typed: ["ping Tamsyn about the rollout"], at: epoch.addingTimeInterval(Double(day) * 86_400))
        }
        #expect(await store.allEntries().map(\.word) == ["Tamsyn"])
        let written = try String(contentsOf: sandbox.file, encoding: .utf8)
        #expect(!written.contains("rollout"))
    }

    private let expected: [[String]] = [
        [
            "engineer | title | 2 | 2 | 6 | 2 | 3", "engineer | selection | 1 | 1 | 6 | 1 | 5",
            "engineer | typed | 6 | 6 | 6 | 6 | 3",
        ],
        [
            "administrator | title | 1 | 1 | 5 | 1 | 6", "administrator | selection | 1 | 1 | 5 | 1 | 4",
            "administrator | typed | 2 | 2 | 5 | 2 | 3",
        ],
    ]
}

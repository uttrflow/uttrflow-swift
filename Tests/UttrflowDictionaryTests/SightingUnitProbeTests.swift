// Probe: which unit of independent evidence, a dictation or a day, learns the right title words.

import UttrflowCore
import Testing

@testable import UttrflowDictionary

/// One invented dictation: the day, the app run it fell in, and the title terms both seen and said.
private struct ProbeSighting {
    let day: Int
    let run: Int
    let terms: [String]
}

/// Terms the user keeps returning to across days; every one is made up.
private let recurring = ["Zorvik", "Tamsyn", "Quillon", "Brevka", "Nalaprit", "Dovecraft"]

/// A fortnight: recurring terms on spaced days, plus one document a day dictated over in a burst and never again.
private let fortnight: [ProbeSighting] = (1...14).flatMap { day -> [ProbeSighting] in
    // The app is quit every night and also at midday on even days.
    let morning = day * 2
    let afternoon = day.isMultiple(of: 2) ? morning + 1 : morning
    var sightings: [ProbeSighting] = []
    for (index, term) in recurring.enumerated() where day.isMultiple(of: index + 2) || day == index + 1 {
        sightings.append(ProbeSighting(day: day, run: morning, terms: [term]))
        if index.isMultiple(of: 2) {
            sightings.append(ProbeSighting(day: day, run: afternoon, terms: [term]))
        }
    }
    let burst = "Brindle\(day)moor"
    for _ in 1...3 { sightings.append(ProbeSighting(day: day, run: afternoon, terms: [burst])) }
    return sightings
}

/// What one counting rule learnt over the fortnight.
private struct RuleYield {
    var learnt: Set<String> = []
    var trueTerms: Int { learnt.intersection(recurring).count }
    var falseTerms: Int { learnt.subtracting(recurring).count }
}

/// Counts every dictation as a sighting, forgetting the tally whenever the app quits: the earlier rule.
private func perDictationInMemory(_ sightings: [ProbeSighting]) -> RuleYield {
    var yield = RuleYield()
    var ledger = SightingLedger()
    var run = sightings.first?.run
    for (index, sighting) in sightings.enumerated() {
        if sighting.run != run { ledger = SightingLedger() }
        run = sighting.run
        tally(ledger.record(sighting.terms, on: index).learnt, into: &yield)
    }
    return yield
}

/// Counts each distinct day once and carries the tally across quits through its rows: the adopted rule.
private func perDayPersisted(_ sightings: [ProbeSighting]) -> RuleYield {
    var yield = RuleYield()
    var rows: [UttrflowCore.EvidenceRow] = []
    var ledger = SightingLedger()
    var run = sightings.first?.run
    for sighting in sightings {
        if sighting.run != run { ledger = SightingLedger(remembering: rows) }
        run = sighting.run
        let counted = ledger.record(sighting.terms, on: sighting.day)
        rows += counted.rows
        tally(counted.learnt, into: &yield)
    }
    return yield
}

private func tally(_ learnt: [String], into yield: inout RuleYield) {
    yield.learnt.formUnion(learnt)
}

@Suite("Which unit of evidence learns title words")
struct SightingUnitProbeTests {
    @Test("Counting distinct days across quits learns more true terms and no burst terms")
    func perDayBeatsPerDictation() {
        let before = perDictationInMemory(fortnight)
        let after = perDayPersisted(fortnight)
        print(
            "per dictation, in memory: true \(before.trueTerms)/\(recurring.count), false \(before.falseTerms)"
        )
        print("per day, persisted: true \(after.trueTerms)/\(recurring.count), false \(after.falseTerms)")
        #expect(after.trueTerms >= before.trueTerms)
        #expect(after.falseTerms == 0)
    }
}

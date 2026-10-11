// Tests for the persona projection and the ranking it feeds.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("The persona projected from the evidence ledger")
struct PersonaProjectionTests {
    private let today = EvidenceRow.day(of: epoch)

    private func row(_ kind: EvidenceRow.Kind, _ id: UUID, weight: Int = 1, daysAgo: Int = 0) -> EvidenceRow {
        EvidenceRow(
            kind: kind, subject: id.uuidString, weight: weight, day: today - daysAgo, provenance: .dictation)
    }

    @Test("Kept uses count, undone ones subtract, and an entry with nothing kept is absent")
    func usesMinusReverts() {
        let kept = UUID()
        let undone = UUID()
        let standing = PersonaProjection.standing(
            of: [row(.use, kept, weight: 3), row(.revert, kept), row(.use, undone), row(.revert, undone)],
            now: epoch)
        #expect(standing[kept] == 2)
        #expect(standing[undone] == nil)
    }

    @Test("A use one half-life old counts half")
    func decays() {
        let id = UUID()
        let standing = PersonaProjection.standing(
            of: [row(.use, id, daysAgo: Int(WorkingSet.recencyHalfLifeInDays))], now: epoch)
        #expect(standing[id] == 0.5)
    }

    @Test("A restore ignores reverts on or before its day, and not later ones")
    func restoreIsAMarker() {
        let id = UUID()
        let rows = [
            row(.use, id, weight: 2), row(.revert, id, weight: 2, daysAgo: 0), row(.restore, id),
        ]
        #expect(PersonaProjection.standing(of: rows, now: epoch)[id] == 2)
        let later =
            rows + [
                EvidenceRow(
                    kind: .revert, subject: id.uuidString, weight: 2, day: today + 1, provenance: .undo)
            ]
        #expect(PersonaProjection.standing(of: later, now: epoch)[id] == nil)
    }

    @Test("Sightings and subjects that are not entry ids project nothing")
    func ignoresOtherRows() {
        let id = UUID()
        let rows = [
            row(.sighting, id),
            EvidenceRow(kind: .use, subject: "kubectl", day: today, provenance: .dictation),
        ]
        #expect(PersonaProjection.standing(of: rows, now: epoch).isEmpty)
    }

    @Test("Recent ledger use lifts an entry the stored counters rank lower, and no persona changes nothing")
    func liftsTheRanking() {
        let ledgerFavourite = word("Kubernetes", saying: "kooberneteez", used: 0, daysAgo: 20)
        let counterFavourite = word("Zorvane", saying: "zorvain", used: 1, daysAgo: 20)
        let entries = [ledgerFavourite, counterFavourite]
        #expect(WorkingSet.words(from: entries, limit: 1, now: epoch) == ["Zorvane"])
        let evidence = [row(.use, ledgerFavourite.id, weight: 4)]
        #expect(WorkingSet.words(from: entries, limit: 1, now: epoch, evidence: evidence) == ["Kubernetes"])
        let explained = WorkingSet.explain(entries: entries, limit: 1, now: epoch, evidence: evidence)
        #expect(explained[ledgerFavourite.id] == .inPrompt(rank: 1))
    }

    @Test("The last use is the newest use row's day, and an undo does not move it")
    func lastUse() {
        let id = UUID()
        let rows = [
            row(.use, id, daysAgo: 40), row(.use, id, daysAgo: 3), row(.revert, id), row(.sighting, id),
        ]
        #expect(PersonaProjection.lastUse(in: rows) == [id: today - 3])
        #expect(PersonaProjection.lastUse(in: [row(.revert, id)]).isEmpty)
    }

    @Test(
        "Of two entries with equal counts, the one used yesterday outranks the one last used 90 days ago",
        arguments: [1, 5, 20], [91.0, 400, 2000])
    func lastUseOutranksFirstSeen(uses: Int, firstSeenDaysAgo: Double) {
        let recent = word(
            "Kubernetes", saying: "kooberneteez", from: .added, used: uses, daysAgo: firstSeenDaysAgo)
        let stale = word("Zorvane", saying: "zorvain", from: .added, used: uses, daysAgo: 90)
        let evidence =
            (0..<uses).map { _ in row(.use, recent.id, daysAgo: 1) }
            + (0..<uses).map { _ in row(.use, stale.id, daysAgo: 90) }
        #expect(
            WorkingSet.words(from: [stale, recent], limit: 1, now: epoch, evidence: evidence) == [
                "Kubernetes"
            ])
    }
}

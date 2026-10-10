// Tests for the persona list Settings shows from the evidence ledger.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowUX

@Suite("Persona presentation")
struct PersonaPresentationTests {
    private let now = Date(timeIntervalSince1970: 20_001 * 86_400)

    private func row(_ kind: EvidenceRow.Kind, _ subject: String, _ weight: Int = 1) -> EvidenceRow {
        EvidenceRow(kind: kind, subject: subject, weight: weight, day: 20_000, provenance: .dictation)
    }

    @Test("words are listed by recorded uses with their undos, then kinds of place, then watched words")
    func itemsReportOnlyRecordedSums() {
        let often = DictionaryEntry(word: "Grafana", origin: .learned, firstSeen: now)
        let once = DictionaryEntry(word: "Aarav", origin: .added, firstSeen: now)
        let gone = UUID()
        let rows =
            [
                row(.use, often.id.uuidString, 3), row(.revert, often.id.uuidString),
                row(.use, once.id.uuidString), row(.use, gone.uuidString), row(.use, gone.uuidString),
                row(.sighting, "hash-a"), row(.sighting, "hash-b"), row(.sighting, "hash-b", -1),
            ] + StyleSignals.rows(for: "Sure, see you there.", into: .messaging, day: 20_000)
        let items = PersonaProfile.items(from: rows, entries: [often, once])
        #expect(
            items.map(\.title) == [
                "Grafana", "A word no longer in your dictionary", "Aarav", "Writing in a chat",
                "Words heard but not learned yet",
            ])
        #expect(items[0].detail == "Used 3 times, undone once")
        #expect(items[2].detail == "Used once")
        #expect(
            items[3].detail
                == "1 dictation, about 4 words a sentence, 100% of short ones end with a full stop")
        #expect(items[4].detail == "1 word, kept without their spelling")
    }

    @Test("an empty ledger lists nothing and offers no reset")
    func emptyLedgerListsNothing() {
        #expect(PersonaProfile.items(from: [], entries: []).isEmpty)
        let group = SettingsPresenter.personaGroup(.nothing)
        #expect(group.rows.map(\.id) == ["resetPersona"])
        #expect(group.rows[0].control == .status("Empty"))
    }

    @Test("each item is a row whose Remove names its own fact without asking, and reset asks first")
    func rowsCarryTheirFacts() {
        let item = PersonaItem(fact: .style(.email), title: "Writing in an email", detail: "2 dictations")
        let personalisation = SettingsPersonalisation(
            learnedWords: 0, addedWords: 0, transcripts: 0, persona: [item])
        let rows = SettingsPresenter.personaGroup(personalisation).rows
        #expect(rows.map(\.id) == ["resetPersona", "persona.style.email"])
        #expect(
            rows[1].control
                == .removal(
                    SettingsRemoval(reset: .personaFact(.style(.email)), title: "Remove", confirmation: nil)))
        #expect(rows[0].unavailability == nil)
        #expect(SettingsReset.persona.isConfirmed)
        #expect(!SettingsReset.personaFact(.noticedWords).isConfirmed)
        #expect(SettingsEditor.unavailability(of: .personaFact(.noticedWords), given: personalisation) != nil)
    }
}

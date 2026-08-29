import Foundation
import Testing

@testable import UttrflowHistory

@Suite("What one kept dictation is")
struct DictationRecordTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("survives inside the window and not outside it")
    func retentionWindow() {
        let record = DictationRecord(text: "hello", when: noon)
        #expect(record.survives(days: 7, now: noon.addingTimeInterval(6 * 86_400)))
        #expect(!record.survives(days: 7, now: noon.addingTimeInterval(8 * 86_400)))
    }

    /// The boundary is where an off-by-one keeps something the user was told was gone.
    @Test("stops surviving exactly at the boundary")
    func retentionBoundary() {
        let record = DictationRecord(text: "hello", when: noon)
        #expect(!record.survives(days: 7, now: noon.addingTimeInterval(7 * 86_400)))
        #expect(record.survives(days: 7, now: noon.addingTimeInterval(7 * 86_400 - 1)))
    }

    /// A stored zero or a negative must not be read as "keep for ever".
    @Test("keeps nothing when the window is not a real number of days")
    func nonPositiveRetention() {
        let record = DictationRecord(text: "hello", when: noon)
        #expect(!record.survives(days: 0, now: noon))
        #expect(!record.survives(days: -3, now: noon))
    }

    @Test("round-trips through Codable with every field")
    func codableRoundTrip() throws {
        let correction = RecordedCorrection(
            heard: "utter flow", wrote: "Uttrflow", wordRange: 0..<2, entryID: UUID(),
            reason: .seenOnScreen, heardConfidence: 0.4)
        let record = DictationRecord(
            text: "hello", when: noon, applicationName: "Notes", spokenFor: .seconds(11),
            changes: RecordedChanges(
                corrections: [correction],
                snippets: [RecordedSnippet(snippetID: UUID(), matched: "brb", expansion: "back")]))
        let decoded = try JSONDecoder().decode(
            DictationRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    /// The field is new and every file already on disk is missing it. This is a literal
    /// of what the previous shape actually wrote, rather than a re-encoding of today's
    /// — a test that encodes before it decodes cannot fail the way an upgrade does.
    @Test("a record written before changes were kept still decodes")
    func decodesTheShapeBeforeChanges() throws {
        let stored = """
            [{"applicationName":"Mail","id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8",\
            "spokenFor":[0,11000000000000000000],"text":"Right, the drafting is done.",\
            "when":721692800}]
            """
        let decoded = try JSONDecoder().decode([DictationRecord].self, from: Data(stored.utf8))

        #expect(decoded.map(\.text) == ["Right, the drafting is done."])
        #expect(decoded.first?.applicationName == "Mail")
        #expect(decoded.first?.spokenFor == .seconds(11))
        // Absent, not empty: nobody was keeping a record when this was written, and
        // reading it as "nothing was changed" would let the accuracy figure count an
        // unmeasured dictation as a perfect one.
        #expect(decoded.first?.changes == nil)
        #expect(CorrectionHistory(of: decoded).corrections.isEmpty)
        // A dictation nobody flagged and one from before flags existed are the same
        // fact — the user has not complained about it — so there is no third state and
        // the missing key reads as `false` rather than refusing the whole file.
        #expect(decoded.first?.isFlagged == false)
        // Nor did anything record which app that was, beyond its name. The row still
        // knows where it went; only the icon lookup has to fall back to the name.
        #expect(decoded.first?.applicationIdentifier == nil)
    }

    /// The name is a label and the identifier is an identity, so the identity has to
    /// survive being written to disk and read back — otherwise every dictation loses its
    /// icon the moment the app is restarted.
    @Test("keeps the application's identifier across a round trip")
    func keepsTheApplicationIdentifier() throws {
        let record = DictationRecord(
            text: "Ship it", when: Date(timeIntervalSinceReferenceDate: 721_692_800),
            applicationName: "Claude", applicationIdentifier: "com.anthropic.claudefordesktop")

        let written = try JSONEncoder().encode([record])
        let read = try JSONDecoder().decode([DictationRecord].self, from: written)

        #expect(read.first?.applicationIdentifier == "com.anthropic.claudefordesktop")
        #expect(read.first?.applicationName == "Claude")
    }
}

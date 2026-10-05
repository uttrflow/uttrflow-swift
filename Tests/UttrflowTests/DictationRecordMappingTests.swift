import Foundation
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline
import Testing

@testable import Uttrflow

@Suite("Dictation outcomes map to history records")
struct DictationRecordMappingTests {
    @Test("an inserted outcome keeps every measured history field")
    func insertedOutcomeMapsEveryField() throws {
        let id = UUID()
        let entryID = UUID()
        let snippetID = UUID()
        let when = Date(timeIntervalSince1970: 1_750_000_000)
        let correction = DictationCorrection(
            heard: "sequel", wrote: "SQL", wordRange: 2..<3, entryID: entryID,
            reason: .seenOnScreen, heardConfidence: 0.72, writtenWordIndex: 1)
        let snippet = SnippetUse(snippetID: snippetID, matched: "my signoff", expansion: "Regards")
        let outcome = DictationOutcome(
            text: "Use SQL and Regards", method: .pasteboard, cleanedBy: .rules,
            insertedInto: "Editor", insertedIntoIdentifier: "com.example.editor",
            spokenFor: .seconds(12),
            changes: AppliedChanges(
                corrections: [correction], snippets: [snippet], spokenWords: 5))

        let record = try #require(
            DictationRecordMapping.record(for: .inserted(outcome), when: when, id: id))

        #expect(record.id == id)
        #expect(record.text == "Use SQL and Regards")
        #expect(record.when == when)
        #expect(record.applicationName == "Editor")
        #expect(record.applicationIdentifier == "com.example.editor")
        #expect(record.spokenFor == .seconds(12))
        #expect(record.isFlagged == false)
        #expect(record.arrival == .notReported)
        let changes = try #require(record.changes)
        #expect(changes.spokenWords == 5)
        #expect(changes.corrections.count == 1)
        let storedCorrection = try #require(changes.corrections.first)
        #expect(storedCorrection.heard == "sequel")
        #expect(storedCorrection.wrote == "SQL")
        #expect(storedCorrection.wordRange == (2..<3))
        #expect(storedCorrection.entryID == entryID)
        #expect(storedCorrection.reason == .seenOnScreen)
        #expect(storedCorrection.heardConfidence == 0.72)
        #expect(storedCorrection.writtenWordIndex == 1)
        #expect(storedCorrection.isUndone == false)
        #expect(
            changes.snippets == [
                RecordedSnippet(
                    snippetID: snippetID, matched: "my signoff", expansion: "Regards")
            ])
    }

    @Test("a failure keeps salvageable words without measured metadata")
    func salvagedFailureMapsBasicRecord() throws {
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_750_000_001)
        let failure = DictationFailure(
            message: "Insertion failed", recovery: .retry, severity: .recoverable,
            transcript: "Words to recover")

        let record = try #require(
            DictationRecordMapping.record(for: .failed(failure), when: when, id: id))

        #expect(record.id == id)
        #expect(record.text == "Words to recover")
        #expect(record.when == when)
        #expect(record.applicationName == nil)
        #expect(record.applicationIdentifier == nil)
        #expect(record.spokenFor == nil)
        #expect(record.changes == nil)
        #expect(record.isFlagged == false)
        #expect(record.arrival == .notInserted)
    }

    @Test("an inserted outcome keeps how its arrival was read")
    func insertedOutcomeKeepsItsArrival() throws {
        for arrival in InsertionArrival.allCases {
            let outcome = DictationOutcome(
                text: "Done", method: .pasteboard, cleanedBy: .rules, arrival: arrival)
            let record = try #require(
                DictationRecordMapping.record(for: .inserted(outcome), when: Date(), id: UUID()))
            #expect(record.arrival == RecordedArrival(arrival))
        }
    }

    @Test("a failure with no transcript creates no record")
    func failureWithoutTranscriptMapsNothing() {
        let failure = DictationFailure(
            message: "Nothing heard", recovery: .retry, severity: .recoverable)

        #expect(
            DictationRecordMapping.record(
                for: .failed(failure), when: Date(), id: UUID()) == nil)
    }

    @Test("every state before an outcome creates no record")
    func inProgressStatesMapNothing() {
        let states: [DictationState] = [.idle, .recording, .transcribing, .tidying, .inserting]

        for state in states {
            #expect(
                DictationRecordMapping.record(for: state, when: Date(), id: UUID()) == nil,
                "\(state) must not create a history record")
        }
    }

    @Test("only inserted and failed states have ended")
    func endedStatesAreExhaustive() {
        let states: [(DictationState, Bool)] = [
            (.idle, false), (.recording, false), (.transcribing, false), (.tidying, false),
            (.inserting, false),
            (.inserted(DictationOutcome(text: "Done", method: .accessibility, cleanedBy: .rules)), true),
            (.failed(DictationFailure(message: "Failed", recovery: .retry, severity: .recoverable)), true),
        ]

        for (state, expected) in states {
            #expect(state.hasEnded == expected, "Unexpected ended status for \(state)")
        }
    }

    @Test("a dictation into a listed app writes no history record")
    func listedAppWritesNoRecord() {
        let outcome = DictationOutcome(
            text: "Private note", method: .pasteboard, cleanedBy: .rules,
            insertedInto: "Records", insertedIntoIdentifier: "com.example.records")
        let keeping = HistoryKeeping(excludedApplications: ["com.example.records"])

        #expect(
            DictationRecordMapping.record(
                for: .inserted(outcome), when: Date(), id: UUID(), keeping: keeping) == nil)
        #expect(
            DictationRecordMapping.record(
                for: .inserted(outcome), when: Date(), id: UUID(), keeping: .everything) != nil)
    }
}

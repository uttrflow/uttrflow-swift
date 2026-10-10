import Testing
import UttrflowCore
import UttrflowInput

@Suite("Undo probe")
struct UndoProbeTests {
    private func field(_ value: String, at location: Int, selecting length: Int = 0) -> UndoFieldReading {
        UndoFieldReading(value: value, selectionLocation: location, selectionLength: length)
    }

    @Test("A field back to its old value is one step, with no selection to restore")
    func oneStepAtCaret() {
        let report = UndoProbe.classify(
            before: field("ab", at: 1), afterInsert: field("aXYb", at: 3), afterUndo: field("ab", at: 1))
        #expect(report == UndoReport(steps: .oneStep, selectionRestored: nil))
    }

    @Test("A replaced selection that comes back is reported restored")
    func selectionRestored() {
        let report = UndoProbe.classify(
            before: field("one two", at: 4, selecting: 3), afterInsert: field("one six", at: 7),
            afterUndo: field("one two", at: 4, selecting: 3))
        #expect(report == UndoReport(steps: .oneStep, selectionRestored: true))
    }

    @Test("The old text with the selection collapsed is one step, selection not restored")
    func selectionLost() {
        let report = UndoProbe.classify(
            before: field("one two", at: 4, selecting: 3), afterInsert: field("one six", at: 7),
            afterUndo: field("one two", at: 7))
        #expect(report == UndoReport(steps: .oneStep, selectionRestored: false))
    }

    @Test("A field unchanged by ⌘Z undoes nothing")
    func undoesNothing() {
        let report = UndoProbe.classify(
            before: field("ab", at: 1), afterInsert: field("aXYb", at: 3), afterUndo: field("aXYb", at: 3))
        #expect(report.steps == .undoesNothing)
    }

    @Test("Part of the insertion gone with its surroundings intact is several steps")
    func several() {
        let report = UndoProbe.classify(
            before: field("ab", at: 1), afterInsert: field("aXYb", at: 3), afterUndo: field("aXb", at: 2))
        #expect(report.steps == .several)
    }

    @Test("Text the field held before the insertion changing undoes more than the dictation")
    func undoesMore() {
        let report = UndoProbe.classify(
            before: field("ab", at: 1), afterInsert: field("aXYb", at: 3), afterUndo: field("", at: 0))
        #expect(report.steps == .undoesMore)
    }

    @Test("A prefix kept but the text after the insertion changed undoes more")
    func tailChanged() {
        let report = UndoProbe.classify(
            before: field("ab", at: 1), afterInsert: field("aXYb", at: 3), afterUndo: field("aXYc", at: 3))
        #expect(report.steps == .undoesMore)
    }

    @Test("A field that will not report at any reading is unreadable")
    func unreadable() {
        let readings: [(UndoFieldReading?, UndoFieldReading?, UndoFieldReading?)] = [
            (nil, field("a", at: 1), field("", at: 0)),
            (field("", at: 0), nil, field("", at: 0)),
            (field("", at: 0), field("a", at: 1), nil),
        ]
        for (before, afterInsert, afterUndo) in readings {
            let report = UndoProbe.classify(before: before, afterInsert: afterInsert, afterUndo: afterUndo)
            #expect(report == UndoReport(steps: .unreadable, selectionRestored: nil))
        }
    }

    @Test("A run reads, inserts, settles, reads, undoes, settles and reads in that order")
    func runOrder() async throws {
        var log: [String] = []
        var readings = [field("ab", at: 1), field("aXYb", at: 3), field("ab", at: 1)]
        let report = try await UndoProbe.run(
            read: {
                log.append("read")
                return readings.removeFirst()
            },
            insert: { log.append("insert") },
            undo: { log.append("undo") },
            settle: { log.append("settle") })
        #expect(report.steps == .oneStep)
        #expect(log == ["read", "insert", "settle", "read", "undo", "settle", "read"])
    }

    @Test("A refused ⌘Z stops the run before the last reading")
    func undoRefused() async {
        var reads = 0
        await #expect(throws: TextInsertionError.accessibilityDenied) {
            _ = try await UndoProbe.run(
                read: {
                    reads += 1
                    return nil
                },
                insert: {}, undo: { throw TextInsertionError.accessibilityDenied }, settle: {})
        }
        #expect(reads == 2)
    }
}

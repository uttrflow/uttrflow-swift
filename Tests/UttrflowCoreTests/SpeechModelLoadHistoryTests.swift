import Foundation
import Testing

@testable import UttrflowCore

@Suite("The speech model's kept loads")
struct SpeechModelLoadHistoryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func history(
        _ seconds: [Double], build: String = "25A100", revision: String = "abc"
    ) -> SpeechModelLoadHistory {
        var history = SpeechModelLoadHistory()
        for (index, value) in seconds.enumerated() {
            history.append(
                date: start.addingTimeInterval(Double(index)), seconds: value, parts: nil, systemBuild: build,
                modelRevision: revision)
        }
        return history
    }

    @Test("The first load kept expects to be slow, and a repeat on the same build does not.")
    func firstAndUnchanged() {
        let loads = history([90, 2]).records
        #expect(loads.map(\.change) == [.firstRecorded, .unchanged])
        #expect(loads[0].change.expectsSlowLoad)
        #expect(!loads[1].change.expectsSlowLoad)
    }

    @Test("A load after a macOS build change is marked expected-slow.")
    func systemUpdateExpectsSlowLoad() {
        var loads = history([2, 2])
        let record = loads.append(
            date: start.addingTimeInterval(10), seconds: 80, parts: nil, systemBuild: "25B200",
            modelRevision: "abc")
        #expect(record.change == .systemUpdated)
        #expect(record.change.expectsSlowLoad)
    }

    @Test("A load after a model revision change is marked expected-slow.")
    func modelChangeExpectsSlowLoad() {
        #expect(history([2]).change(systemBuild: "25A100", modelRevision: "def") == .modelChanged)
    }

    @Test("A load more than five times the earlier median is a likely recompile; one under it is not.")
    func likelyRecompile() {
        var loads = history([2, 3, 2, 100])
        #expect(loads.medianSeconds == 2.5)
        let slow = loads.append(
            date: start, seconds: 13, parts: nil, systemBuild: "25A100", modelRevision: "abc")
        let usual = loads.append(
            date: start, seconds: 2, parts: nil, systemBuild: "25A100", modelRevision: "abc")
        #expect(slow.isLikelyRecompile)
        #expect(!usual.isLikelyRecompile)
        #expect(!history([90]).records[0].isLikelyRecompile)
    }

    @Test("Only the last ten loads are kept, oldest dropped first.")
    func keepsTen() {
        let loads = history((1...14).map(Double.init)).records
        #expect(loads.count == SpeechModelLoadHistory.capacity)
        #expect(loads.first?.seconds == 5)
        #expect(
            SpeechModelLoadHistory(records: history((1...14).map(Double.init)).records + loads).records.count
                == 10)
    }

    @Test("The log keeps loads across reads and judges a new build against the last one on disk.")
    func logRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "loads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = SpeechModelLoadLog(file: folder.appending(path: LocalStoreEntry.speechModelLoads.name))
        #expect(log.history().records.isEmpty)
        let parts = SpeechModelLoadParts(
            prewarm: 1, specialiseEncoder: 2, specialiseDecoder: 3, loadEncoder: 4, loadDecoder: 5,
            tokenizer: 6)
        try log.record(seconds: 2, parts: parts, modelRevision: "abc", systemBuild: "25A100", at: start)
        let after = try log.record(
            seconds: 70, parts: nil, modelRevision: "abc", systemBuild: "25B200", at: start)
        #expect(after.change == .systemUpdated)
        #expect(after.isLikelyRecompile)
        #expect(log.history().records.map(\.parts) == [parts, nil])
        #expect(SpeechModelLoadLog.defaultFile(in: folder).lastPathComponent == "speech-model-loads.v1.json")
    }

    @Test("An unreadable log is set aside and starts again rather than failing the load.")
    func unreadableLogStartsAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "loads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: LocalStoreEntry.speechModelLoads.name)
        try Data("not json".utf8).write(to: file)
        let record = try SpeechModelLoadLog(file: file).record(seconds: 3, parts: nil, modelRevision: "abc")
        #expect(record.change == .firstRecorded)
        #expect(LocalStore.hasSetAside(file))
    }

    @Test("This Mac's macOS build is read from the kernel.")
    func systemBuildIsRead() {
        #expect(SpeechModelLoadLog.currentSystemBuild != "unknown")
        #expect(!SpeechModelLoadLog.currentSystemBuild.isEmpty)
    }
}

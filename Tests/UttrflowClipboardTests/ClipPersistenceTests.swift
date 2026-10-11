// Synthetic clipboard moves exercise committed snapshots without file I/O.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Executing clipboard index transitions")
struct ClipPersistenceTests {
    private let historyFile = URL(fileURLWithPath: "/synthetic/clipboard.v1.json")
    private let savedFile = URL(fileURLWithPath: "/synthetic/saved.v1.json")

    private func clip(_ text: String) -> Clip {
        Clip(text: text, kind: .text, copiedAt: noon, source: "FixtureEditor")
    }

    @Test("a cross-pool move writes the bridge before history and then settles saved clips")
    func writeOrder() throws {
        let departing = clip("Synthetic departing").with { $0.isPinned = true }
        let history = departing.with { $0.isPinned = false }
        let arriving = clip("Synthetic arriving").with { $0.isPinned = true }
        let current = [history, arriving]
        var snapshot = ClipIndexSnapshot(savedOnDisk: [departing], historyOnDisk: [], wholeList: current)
        var files: [URL] = []
        var records: [[Clip]] = []
        try ClipPersistence(historyFile: historyFile).write(current, updating: &snapshot) { clips, file in
            files.append(file)
            records.append(clips)
        }
        #expect(files == [savedFile, historyFile, savedFile])
        #expect(records == [[departing, arriving], [history], [arriving]])
        #expect(snapshot.savedOnDisk == [arriving])
        #expect(snapshot.historyOnDisk == [history])
        #expect(snapshot.wholeList == current)
    }

    @Test(
        "a refused write retains precisely the snapshots of earlier successful writes", arguments: [0, 1, 2])
    func partialWriteFailure(refusedIndex: Int) {
        let departing = clip("Synthetic departing").with { $0.isPinned = true }
        let history = departing.with { $0.isPinned = false }
        let arriving = clip("Synthetic arriving").with { $0.isPinned = true }
        let current = [history, arriving]
        var snapshot = ClipIndexSnapshot(savedOnDisk: [departing], historyOnDisk: [], wholeList: current)
        var files: [URL] = []
        var refusal: ClipboardStoreError?
        do {
            try ClipPersistence(historyFile: historyFile).write(current, updating: &snapshot) {
                _, file throws(ClipboardStoreError) in
                files.append(file)
                if files.count - 1 == refusedIndex { throw .couldNotWrite }
            }
        } catch {
            refusal = error
        }
        #expect(refusal == .couldNotWrite)
        #expect(files == Array([savedFile, historyFile, savedFile].prefix(refusedIndex + 1)))
        #expect(snapshot.savedOnDisk == (refusedIndex == 0 ? [departing] : [departing, arriving]))
        #expect(snapshot.historyOnDisk == (refusedIndex == 2 ? [history] : []))
        #expect(snapshot.wholeList == current)
    }

    @Test("an unchanged disk snapshot requires no writes")
    func unchangedSnapshot() throws {
        let saved = clip("Synthetic saved").with { $0.isPinned = true }
        let history = clip("Synthetic history")
        var snapshot = ClipIndexSnapshot(savedOnDisk: [saved], historyOnDisk: [history])
        var writes = 0
        try ClipPersistence(historyFile: historyFile).write([saved, history], updating: &snapshot) { _, _ in
            writes += 1
        }
        #expect(writes == 0)
        #expect(snapshot.savedOnDisk == [saved])
        #expect(snapshot.historyOnDisk == [history])
    }
}

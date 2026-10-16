import Foundation
import Testing
import UttrflowHistory

@Suite("scratch scale probe")
struct ScratchScaleProbeTests {
    @Test("append cost grows with history")
    func appendCost() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DictationHistoryStore(file: dir.appending(path: "h.json"), capacity: 1_000)
        let retention = Retention(days: 36_500, now: Date())
        let text = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 40)
        var t0 = ContinuousClock.now
        for i in 1...5_000 {
            _ = try await store.append(DictationRecord(text: text, when: Date()), keeping: retention)
            if i % 1000 == 0 {
                let d = ContinuousClock.now - t0
                print("PROBE n=\(i) last1000=\(d)")
                t0 = ContinuousClock.now
            }
        }
        let c = ContinuousClock.now
        _ = await store.records(keeping: retention)
        print("PROBE read=\(ContinuousClock.now - c)")
    }
}

import Foundation
import Testing
import UttrflowDictionary

@Suite("scratch dict probe")
struct ScratchDictProbeTests {
    @Test("dictionary scale")
    func scale() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PersonalDictionaryStore(file: dir.appending(path: "d.json"))
        var t0 = ContinuousClock.now
        let syl = ["ka","lo","mi","ven","dra","qui","zor","tal","bem","shu"]
        for i in 0..<4_000 {
            let w = "Zq" + String(i).map { syl[Int(String($0))!] }.joined()
            _ = try await store.add(word: w, pronunciation: "", at: Date())
            if (i + 1) % 1000 == 0 {
                print("PROBE dict add n=\(i+1) last1000=\(ContinuousClock.now - t0)")
                t0 = ContinuousClock.now
            }
        }
        let c = ContinuousClock.now
        _ = await store.index()
        print("PROBE dict index build=\(ContinuousClock.now - c)")
        let c2 = ContinuousClock.now
        _ = try await store.add(word: "Extraordinaryname", pronunciation: "", at: Date())
        print("PROBE dict one more add=\(ContinuousClock.now - c2)")
    }
}

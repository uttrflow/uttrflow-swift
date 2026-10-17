import Foundation
import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowPipeline
import UttrflowTestSupport

struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 } 
  mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(n,1))) } }

@Suite("scratch fuzz")
struct ScratchFuzzTests {
    static func words(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init)
    }
    static func diff(_ a: [String], _ b: [String]) -> [String] {
        var c: [String: Int] = [:]; for w in b { c[w, default: 0] += 1 }
        var out: [String] = []
        for w in a { if let n = c[w], n > 0 { c[w] = n - 1 } else { out.append(w) } }
        return out
    }
    func run(_ parts: [String]) async -> String {
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: ScenarioCleaners.rules,
            context: FakeContextEngine(), inserter: FakeTextInserter())
        let heard = parts.map { Transcription(text: $0, detectedLanguage: DetectedLanguage(code: .english, confidence: 1)) }
        return await pipeline.clean(heard, seeing: AppContext()).text ?? "<nil>"
    }

    @Test func fuzz() async throws {
        let dir = "Sources/UttrflowEval/Resources/Corpus/"
        var spoken: [String] = []
        for f in ["everyday", "grammar", "contextual", "homophone", "multilingual", "hinglishReply", "multilingual.codeMixing", "secondLanguage", "notARequest.commandMention", "longInput", "technical"] {
            let url = URL(fileURLWithPath: dir + f + ".json")
            guard let data = try? Data(contentsOf: url), let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for c in arr { if let s = c["spoken"] as? String, c["context"] == nil { spoken.append(s) } }
        }
        var rng = LCG(s: UInt64(ProcessInfo.processInfo.environment["FUZZ_SEED"] ?? "7") ?? 7)
        var report: [String] = []
        let n = Int(ProcessInfo.processInfo.environment["FUZZ_N"] ?? "300") ?? 300
        for i in 0..<n {
            let a = spoken[rng.below(spoken.count)]
            let b = spoken[rng.below(spoken.count)]
            let kind = ProcessInfo.processInfo.environment["KIND"].flatMap { Int($0) } ?? (i % 4)
            var parts: [String]
            switch kind {
            case 0: parts = [a]
            case 1: parts = [a.lowercased().filter { !",.?!;:".contains($0) }]
            case 2:
                let ws = a.split(separator: " ").map(String.init)
                if ws.count < 3 { parts = [a] } else {
                    let cut = 1 + rng.below(ws.count - 1)
                    parts = [ws[..<cut].joined(separator: " "), ws[cut...].joined(separator: " ")]
                }
            case 4:
                parts = (0..<(8 + rng.below(12))).map { _ in spoken[rng.below(spoken.count)] }
            case 5:
                var ws: [String] = []
                for _ in 0..<(10 + rng.below(20)) { ws += spoken[rng.below(spoken.count)].split(separator: " ").map(String.init) }
                parts = []
                var k = 0
                while k < ws.count { let n = 3 + rng.below(12); parts.append(ws[k..<min(k+n, ws.count)].joined(separator: " ")); k += n }
            default: parts = [a, b]
            }
            let out = await run(parts)
            var input = parts.joined(separator: " ")
            if kind == 4 {
                var pieces: [String] = []
                for p in parts { pieces.append(await run([p])) }
                input = pieces.joined(separator: " ")
            } else if kind == 5 {
                input = await run([parts.joined(separator: " ")])
            }
            let lost = Self.diff(Self.words(input), Self.words(out))
            let added = Self.diff(Self.words(out), Self.words(input))
            var flags: [String] = []
            if !lost.isEmpty { flags.append("LOST \(lost)") }
            if !added.isEmpty { flags.append("ADDED \(added)") }
            if kind < 2 {
                let again = await run([out])
                if again != out { flags.append("NONIDEM -> \(again)") }
            }
            if !flags.isEmpty { report.append("K\(kind) \(parts) => \(out)\n    \(flags.joined(separator: " | "))") }
        }
        try report.joined(separator: "\n").write(toFile: ProcessInfo.processInfo.environment["FUZZ_OUT"] ?? "/tmp/fuzz.txt", atomically: true, encoding: .utf8)
    }
}

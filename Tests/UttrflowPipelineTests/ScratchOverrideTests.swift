import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI
@testable import UttrflowPipeline
import UttrflowTestSupport

@Suite("scratch override")
struct ScratchOverrideTests {
    static let terms = ["Priya","Kubernetes","Nginx","Sarah","Lee","Bhatt","Mason","Wren","Kate","Aaron","Oleg","Jira","Rust","Swift","Reid","Nate","Aiden","Jon","Stephen","Dana","Ravi","Clark","Marc","Rhea","Ellis","Gita","Anna","Tom","Sue","Pierce","Ward","Nic","Zoe","Postgres","Redis","Terraform","Grafana","Okta","Figma","Notion","Slack","Zendesk","Vercel","Supabase","Prisma","Kafka","Hadoop","Spark","Flink","Tableau","Looker","Mira","Devansh","Anirudh","Kavita","Rohan","Meera","Sanjay","Tanvi","Harsh","Neha","Vikram","Isha","Arjun","Lakshmi","Pranav","Deepa","Imran","Fatima","Chen","Wei","Yuki","Hiro","Olga","Ivan","Pavel","Greta","Lars","Sven","Bjorn","Elena","Marco","Luca","Chloe","Hugh","Ines","Jose","Noel"]
    @Test func overrides() async throws {
        let dir = "Sources/UttrflowEval/Resources/Corpus/"
        var spoken: [String] = []
        for f in ["everyday", "grammar", "contextual", "homophone", "technical", "longInput"] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + f + ".json")), let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for c in arr { if let s = c["spoken"] as? String, c["context"] == nil { spoken.append(s) } }
        }
        let entries = Self.terms.map { DictionaryEntry(word: $0, pronunciation: nil, origin: .added, firstSeen: Date()) }
        let index = PhoneticIndex(entries: entries.filter { PhoneticIndex.supports(word: $0.word, pronunciation: nil) })
        var report: [String] = []
        let mode = ProcessInfo.processInfo.environment["WIDTH"].flatMap { Int($0) } ?? 1
        for s in spoken {
            let words = s.split(separator: " ").map(String.init)
            if words.count < 2 { continue }
            for i in 0..<words.count {
                if i + mode > words.count { break }
                let scored = words.enumerated().map {
                    TranscribedWord(text: $1, confidence: ($0 >= i && $0 < i + mode) ? 0.3 : 1)
                }
                let t = Transcription(text: s, segments: [TranscriptionSegment(text: s, start: .zero, end: .zero, words: scored)])
                let plain = DictationPipeline(capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: ScenarioCleaners.rules, context: FakeContextEngine(), inserter: FakeTextInserter())
                let with = DictationPipeline(capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: ScenarioCleaners.rules, context: FakeContextEngine(), inserter: FakeTextInserter(), corrector: DictionaryCorrections { _ in index })
                let a = await plain.clean([t], seeing: AppContext()).text ?? ""
                let b = await with.clean([t], seeing: AppContext()).text ?? ""
                if a.lowercased() != b.lowercased() { report.append("IN  \(s)  [doubt \(words[i..<(i+mode)].joined(separator: " "))]\nOFF \(a)\nON  \(b)") }
            }
        }
        try report.joined(separator: "\n\n").write(toFile: ProcessInfo.processInfo.environment["FUZZ_OUT"] ?? "/tmp/ov.txt", atomically: true, encoding: .utf8)
        print("OVERRIDES \(report.count) of \(spoken.count)")
    }
}

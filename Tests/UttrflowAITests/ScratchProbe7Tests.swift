import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe7")
struct ScratchProbe7Tests {
    static let words = ["API", "SQL", "URL", "XML", "CSS", "GPU", "CPU", "JSON", "HTML", "AWS", "IAM", "VPC", "SSO", "K8s", "OKR", "KPI", "ETA", "PR", "CI", "CD", "ML", "NLP", "OCR", "gRPC", "iOS", "macOS", "iPhone", "eBay", "PostgreSQL", "MySQL", "NoSQL", "TypeScript", "JavaScript", "GitHub", "LinkedIn", "YouTube", "WhatsApp", "OpenAI", "DeepMind", "Rust", "Swift", "Linear", "Notion", "Slack", "Jira", "Mira", "Kafka", "Ishaan", "Priya", "Nginx", "Figma", "Ollama", "Pytest", "Gemma", "Prometheus", "Bazel", "Vercel", "Supabase", "Tailwind", "Zoe", "Ansible", "Helm", "Istio", "Envoy", "Ray", "Dask", "Pandas", "Flask", "Django", "Express", "Cursor", "Arc", "Loom", "Stripe", "Okta", "Hugo", "Prisma", "Sentry", "Cobra", "Hive", "Spark", "Jenkins", "Atlas", "Chroma", "Julia", "Ruby", "Scala", "Ada", "Go", "Zig", "Bun", "Dart"]
    static let index = PhoneticIndex(entries: words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })

    @Test func corpus() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/UttrflowEval/Resources/Corpus")
        let e = WordCorrectionEngine()
        var total = 0
        var byEntry: [String: [String]] = [:]
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where f.pathExtension == "json" {
            guard let arr = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [[String: Any]] else { continue }
            for c in arr {
                guard (c["language"] as? String ?? "en") == "en", let s = c["expected"] as? String else { continue }
                let text = s.replacingOccurrences(of: "\n", with: " ")
                if text.split(separator: " ").count > 14 || text.hashValue % 3 != 0 && false { continue }; if total > 60000 { continue }
                let u = CorrectionFixtures.doubting(text)
                for w in ["iOS","macOS","iPhone","eBay","Istio","Ada","Zoe","Okta","Dart","Bun","Hive","Spark","Cobra","Mira","Ray","Go","Ruby","Julia","Arc","Zig"] {
                    total += 1
                    let p = e.proposals(for: u, against: Self.index, seeing: CorrectionFixtures.showing("notes about \(w)"))
                    for x in p where x.heard.lowercased().filter(\.isLetter) != x.replacement.lowercased().filter(\.isLetter) {
                        byEntry[x.replacement, default: []].append("\(x.heard) | \(text.prefix(60))")
                    }
                }
            }
        }
        print("ENTRYTOTAL runs=\(total) falseChanges=\(byEntry.values.map(\.count).reduce(0,+))")
        for (k, v) in byEntry.sorted(by: { $0.value.count > $1.value.count }).prefix(25) { print("ENTRY \(k) \(v.count) e.g. \(v.prefix(3))") }
    }
}

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe")
struct ScratchProbeTests {
    static let words = [
        "Rust", "Swift", "Linear", "Notion", "Slack", "Jira", "Mira", "Kafka", "Ishaan", "Priya",
        "Nginx", "Figma", "Ollama", "Pytest", "Gemma", "Prometheus", "Bazel", "Vercel", "Supabase",
        "Tailwind", "Deepak Rao", "Zoe", "Ansible", "Helm", "Istio", "Envoy", "Ray", "Dask", "Pandas",
        "Flask", "Django", "Express", "Next.js", "OAuth", "gRPC", "GraphQL", "Mongo", "Cursor", "Arc",
        "Loom", "Stripe", "Twilio", "Okta", "Snowflake", "Databricks", "Hugo", "Jekyll", "Gatsby",
    ]
    static let entries = words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) }
    static let index = PhoneticIndex(entries: entries)
    let engine = WordCorrectionEngine()

    static let correct = [
        "The rust on the old gate flaked away in the rain",
        "She is a swift runner and a linear thinker",
        "I had a notion that the slack in the rope was too much",
        "Please jira the ticket later and call Mira tomorrow",
        "A kafka novel sat next to the helm of the ship",
        "The arc of the story and the ray of light were lovely",
        "Express delivery of the flask and the pandas arrived",
        "The hugo award went to a jekyll and hyde retelling",
        "The cursor blinked while the loom clicked in the corner",
        "He has a mongo sized appetite for stripe patterns",
        "Dask the envoy about the istio of the matter",
        "My gemma is a prime example of ansible reasoning",
        "The tailwind helped the vessel past the snowflake storm",
        "Zoe and Priya met Ishaan near the arc de triomphe",
        "Deepak and Rao went to the bazel market",
        "The django reinhardt record was on the vercel shelf",
        "We stripe the lawn and then okta the grass",
        "The next jay s file was a graph ql of troubles",
    ]

    @Test func probeCorrect() {
        for s in Self.correct {
            for ctx in [AppContext?.none, CorrectionFixtures.showing(Self.words.joined(separator: " "))] {
                let u = CorrectionFixtures.doubting(s)
                let p = engine.proposals(for: u, against: Self.index, seeing: ctx ?? .unknown)
                let bad = p
                if !bad.isEmpty { print("CHANGE ctx=\(ctx != nil) | \(s) -> \(bad.map { "\($0.heard)=>\($0.replacement)" })") }
            }
        }
    }

    static let misheard: [(String, String, String)] = [
        ("we deploy with engine x on the edge", "Nginx", "Nginx"),
        ("ask pry a about the report", "Priya", "Priya"),
        ("the pie test suite is green", "Pytest", "Pytest"),
        ("open the fig ma file", "Figma", "Figma"),
        ("run oh llama locally", "Ollama", "Ollama"),
        ("push it to ver sell", "Vercel", "Vercel"),
        ("the super base table", "Supabase", "Supabase"),
        ("use tail wind classes", "Tailwind", "Tailwind"),
        ("o auth token expired", "OAuth", "OAuth"),
        ("graph q l query", "GraphQL", "GraphQL"),
        ("ping ee shaan about it", "Ishaan", "Ishaan"),
        ("the prom ethius dashboard", "Prometheus", "Prometheus"),
        ("ask deep ack rao", "Deepak Rao", "Deepak Rao"),
        ("g rpc stubs", "gRPC", "gRPC"),
        ("data bricks cluster", "Databricks", "Databricks"),
        ("snow flake warehouse", "Snowflake", "Snowflake"),
    ]

    @Test func probeMissed() {
        for (s, _, entry) in Self.misheard {
            let u = CorrectionFixtures.doubting(s)
            let ctx = CorrectionFixtures.showing(entry + " notes")
            let p = engine.proposals(for: u, against: Self.index, seeing: ctx)
            print("MISHEAR \(s) | want \(entry) | got \(p.map { "\($0.heard)=>\($0.replacement)" })")
        }
    }
}

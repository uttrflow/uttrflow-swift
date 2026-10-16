import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe4")
struct ScratchProbe4Tests {
    static let words = ["Rust", "Swift", "Arc", "Ray", "Zig", "Bun", "Dart", "Go", "Spring", "Rails", "Phoenix", "Express", "Flask", "Linear", "Slack", "Cursor", "Loom", "Notion", "Mango", "Gem", "Cobra", "Hive", "Pig", "Storm", "Spark", "Flink", "Beam", "Airflow", "Luigi", "Jenkins", "Jade", "Pearl", "Ruby", "Julia", "Scala", "Haskell", "Erlang", "Lua", "Perl", "Pascal", "Ada", "Kite", "Atlas", "Chroma", "Weaviate", "Milvus", "Qdrant"]
    static let index = PhoneticIndex(entries: words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })
    static let sentences = [
        "The rays of the sun and the arcs of the bridge",
        "He rusts quickly and she swifts along the path",
        "Two bunned buns and three slacks and cursors",
        "Rubies and pearls and jades and gems were stored",
        "The storms sparked beams and hives of angry bees",
        "Julia and Ruby and Pearl and Jade are sisters",
        "Jenkins went to Atlas Chroma and Kite",
        "Julia's rays and Ruby's arcs shone brightly",
        "The dart flew past the pig and the cobra",
        "Her spring flask expressed a linear notion of mangoes",
        "Lua and Perl and Pascal and Ada were friends of Scala",
        "We went going to goes and goer",
        "He zigs and zags while the loomed lights flickered",
        "Springs and flasks and notions and looms",
        "Pascal's theorem and Haskell's brother Erlang",
        "I rayed the sun and arced the ball",
    ]
    @Test func inflect() {
        let e = WordCorrectionEngine()
        for s in Self.sentences {
            for (n, ctx) in [("none", AppContext.unknown), ("screen", CorrectionFixtures.showing(Self.words.joined(separator: " ")))] {
                let p = e.proposals(for: CorrectionFixtures.doubting(s), against: Self.index, seeing: ctx)
                let real = p.filter { $0.heard != $0.replacement }
                if !real.isEmpty { print("INFL \(n) | \(s) -> \(real.map { "\($0.heard)=>\($0.replacement) [\($0.reason)]" })") }
            }
        }
    }
}

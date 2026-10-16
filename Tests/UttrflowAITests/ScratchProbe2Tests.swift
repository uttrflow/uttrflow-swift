import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe2")
struct ScratchProbe2Tests {
    static let words = ["Mira", "Ishaan", "Priya", "Zoe", "Ray", "Deepak Rao", "Nikhil", "Sanvi", "Rohit", "Anita Desai", "Kavita", "Aarav", "Neha", "Siddharth", "Grafana", "Kestrel", "Valkey", "Redis", "Kubernetes", "Tomas", "Lena", "Omar", "Yusuf", "Leila", "Marek", "Stefan", "Irina"]
    static let index = PhoneticIndex(entries: words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })
    static let heard = ["Meera", "Ishan", "Preeya", "Zoey", "Rae", "Deepa", "Rao", "Desai", "Nikhill", "Sunvi", "Rohan", "Rohith", "Kavya", "Arav", "Neeha", "Siddarth", "Tomasz", "Lenna", "Omer", "Yousef", "Layla", "Marc", "Stephan", "Irena", "Anitha", "Kavitha", "Raj", "Rhea", "Mirra", "Zoya", "Aaron", "Kestrol", "Grafanna", "Valkyrie", "Reddis", "Kubernets", "Tomás", "Lina", "Owen", "Yusef", "Leela", "Mario"]
    @Test func names() {
        let e = WordCorrectionEngine()
        for h in Self.heard {
            for conf in [0.95, 0.3] {
                let u = CorrectionFixtures.spoken("Please ask \(h) about the report today", unsure: conf, sure: 0.95)
                let u2 = Utterance(words: ["Please", "ask", h, "about", "the", "report", "today"].map { SpokenWord(text: $0, confidence: $0 == h ? conf : 0.95) })
                _ = u
                let p = e.proposals(for: u2, against: Self.index, seeing: .unknown)
                if !p.isEmpty { print("NAME conf=\(conf) \(h) -> \(p.map { "\($0.heard)=>\($0.replacement) [\($0.reason)]" })") }
            }
        }
    }
}

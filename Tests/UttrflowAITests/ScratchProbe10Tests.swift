import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe10")
struct ScratchProbe10Tests {
    @Test func odd() {
        let e = WordCorrectionEngine()
        let pairs: [(String, String)] = [
            ("O'Brien", "please ask O Brien about it"), ("O'Brien", "please ask O'Brian about it"), ("O'Brien", "please ask obrien about it"),
            ("Jean-Luc", "please ask Jean Luc about it"), ("Jean-Luc", "please ask jean-luke about it"),
            ("Node.js", "we run node js on it"), ("Node.js", "we run node dot js on it"), ("Next.js", "we run next js on it"),
            ("S3", "upload it to s three please"), ("S3", "upload it to s 3 please"), ("EC2", "launch an e c two box"), ("EC2", "launch an ec2 box"),
            ("José", "please ask Jose about it"), ("José", "please ask josé about it"), ("Zoë", "please ask Zoe about it"),
            ("Müller", "please ask Mueller about it"), ("Müller", "please ask Muller about it"),
            ("Dr. Patel", "please ask doctor patel about it"), ("Mr. Chen", "please ask mister chen about it"),
            ("St. John", "please ask saint john about it"),
            ("McDonald", "please ask mick donald about it"), ("McDonald", "please ask Macdonald about it"),
            ("Siobhán", "please ask shiv awn about it"), ("Nguyen", "please ask win about it"),
            ("Xiaoming", "please ask shaw ming about it"), ("Oluwaseun", "please ask olu was shay oon about it"),
            ("Wojciech", "please ask voy check about it"), ("Aoife", "please ask ee fa about it"),
            ("Saoirse", "please ask sear sha about it"), ("Niamh", "please ask neev about it"),
            ("kubectl", "run cube control now"), ("kubectl", "run cube cuddle now"), ("nginx", "run engine x now"),
            ("PostgreSQL", "run post gress sequel now"), ("SQLite", "run sequel lite now"), ("pgvector", "run p g vector now"),
            ("Kubernetes", "run kubernetes now"), ("kubernetes", "run Kubernetes now"),
        ]
        for (entry, said) in pairs {
            let idx = PhoneticIndex(entries: [DictionaryEntry(word: entry, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))])
            for (lbl, u) in [("doubt", CorrectionFixtures.doubting(said)), ("sure", CorrectionFixtures.spoken(said))] {
                let p = e.proposals(for: u, against: idx, seeing: CorrectionFixtures.showing("\(entry) notes"))
                print("P10 [\(entry)] \(lbl) | \(said) -> \(p.map { "\($0.heard)=>\($0.replacement)" })")
            }
        }
    }
}

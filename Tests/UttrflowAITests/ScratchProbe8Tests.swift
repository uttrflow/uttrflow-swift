import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe8")
struct ScratchProbe8Tests {
    @Test func probe() {
        let e = WordCorrectionEngine()
        let idx = PhoneticIndex(entries: ["Ada", "iOS", "Istio", "Okta", "Mira"].map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })
        for (s, ctx) in [("I said I'd go.", AppContext.unknown), ("It is a good idea.", CorrectionFixtures.showing("notes about iOS")), ("That is it.", CorrectionFixtures.showing("notes about Istio")), ("It was a good point", CorrectionFixtures.showing("Okta notes")), ("I wanted to buy a record as a present.", CorrectionFixtures.showing("iOS"))] {
            let p = e.proposals(for: CorrectionFixtures.doubting(s), against: idx, seeing: ctx)
            print("P8 \(s) -> \(p.map { "\($0.heard)=>\($0.replacement) [\($0.reason)] ev=\(String(describing: $0.evidence))" })")
        }
    }
}

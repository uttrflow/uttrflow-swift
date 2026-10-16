import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe5")
struct ScratchProbe5Tests {
    static let words = ["API", "SQL", "URL", "XML", "CSS", "GPU", "CPU", "JSON", "HTML", "AWS", "IAM", "VPC", "SSO", "K8s", "OKR", "KPI", "ETA", "PR", "CI", "CD", "ML", "NLP", "OCR", "gRPC", "iOS", "macOS", "iPhone", "eBay", "PostgreSQL", "MySQL", "NoSQL", "TypeScript", "JavaScript", "GitHub", "LinkedIn", "YouTube", "WhatsApp", "OpenAI", "DeepMind"]
    static let index = PhoneticIndex(entries: words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })
    static let said = [
        "call the a p i with the u r l",
        "run the s q l query on the g p u",
        "the c s s and h t m l are ready",
        "open the j son file in x m l",
        "ask i am about the v p c and s s o",
        "check the o k r and k p i for the e t a",
        "merge the p r after c i and c d",
        "the m l and n l p team uses o c r",
        "type script and java script on git hub",
        "post gres q l and my s q l and no s q l",
        "i phone and mac o s and i o s",
        "you tube and linked in and whats app",
        "open a i and deep mind",
        "the e bay listing on a w s",
        "we use k eight s on a w s",
        "the apparatus is a pie of the cpu",
        "there is a pr in the pipeline and ci is red",
        "ask the eta of the okr",
        "that is a cool api for the url",
        "the sequel to the movie and the cd player",
        "I saw the iam of the sso",
        "please iam me later about it",
    ]
    @Test func acro() {
        let e = WordCorrectionEngine()
        for s in Self.said {
            for (n, ctx) in [("none", AppContext.unknown), ("screen", CorrectionFixtures.showing("notes about " + Self.words.prefix(40).joined(separator: " ")))] {
                for (label, u) in [("doubt", CorrectionFixtures.doubting(s)), ("sure", CorrectionFixtures.spoken(s))] {
                    let p = e.proposals(for: u, against: Self.index, seeing: ctx)
                    print("ACRO \(n) \(label) | \(s) -> \(p.map { "\($0.heard)=>\($0.replacement) [\($0.reason)]" })")
                }
            }
        }
    }
}

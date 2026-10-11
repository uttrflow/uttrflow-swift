// The structural correction gate on invented accent confusions and invented rewrites.

import Testing

@testable import UttrflowDictionary

@Suite("Correction gate: respellings against rewrites")
struct CorrectionGateTests {
    static let confusions: [(String, String)] = [
        ("Bikram", "Vikram"), ("Jubair", "Zubair"), ("Sreya", "Shreya"),
        ("Takur", "Thakur"), ("Pranab", "Pranav"), ("Chitij", "Kshitij"), ("Bijay", "Vijay"),
        ("Jeenat", "Zeenat"), ("Sweta", "Shweta"), ("Dhruba", "Dhruva"), ("Varun", "Barun"),
        ("Kubernets", "Kubernetes"), ("pee gee vector", "pgvector"),
        ("Nikkel", "Nikhil"), ("utter flow", "Uttrflow"), ("Pratik", "Prateek"),
        ("Sanjiv", "Sanjeev"), ("Venkat", "Wenkat"),
    ]
    static let rewrites: [(String, String)] = [
        ("kubectl", "pgvector"), ("Uttrflow build", "Uttrflow ship"), ("Ravi", "Kubernetes"),
        ("Postgres", "Redis"), ("Nikhil", "Pranav"), ("Jira", "Linear"), ("Zubair", "Shweta"),
        ("deploy", "rollback"), ("Vikram", "Vijay"), ("Thakur", "Takeshi"),
    ]

    /// Invented accent confusions the English sound code refused (14 of 20 before; "Vadva" to "Wadhwa", three edits in six letters, is still refused), learnt without one rewrite.
    @Test("Learns accent respellings and refuses every rewrite")
    func learnsAccentRespellings() {
        let refused = Self.confusions.filter { LearnableWords.corrected(over: $0.0, wrote: $0.1) == nil }
        let rewritten = Self.rewrites.filter { LearnableWords.corrected(over: $0.0, wrote: $0.1) != nil }
        #expect(refused.isEmpty, "\(refused)")
        #expect(LearnableWords.corrected(over: "Vadva", wrote: "Wadhwa") == nil)
        #expect(rewritten.isEmpty, "\(rewritten)")
    }
}

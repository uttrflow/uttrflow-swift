import Foundation
import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("scratch probe")
struct ScratchProbe {
    @Test func probe() {
        let cases: [(String, String, String)] = [
            ("my email", "avery@example.com", "send it to my email please"),
            ("my email", "avery@example.com", "my email is my email"),
            ("my email", "avery@example.com", "What is my email?"),
            ("my email", "avery@example.com", "my emails are many"),
            ("sig", "Best regards,\nAvery", "thanks sig"),
            ("sig", "Best regards,\nAvery", "Thanks. sig."),
            ("addr", "12 Example Road", "ship to addr, thanks"),
            ("addr", "12 Example Road", "ship to addr, then addr again"),
            ("my number", "555-0100", "call my number now"),
            ("my number", "555-0100", "My Number"),
            ("O K R", "objectives", "the o k r doc"),
            ("brb", "be right back", "brb"),
            ("brb", "be right back", "I'll brb."),
            ("brb", "be right back", "brb! see you"),
            ("brb", "be right back", "brb? really"),
            ("brb", "be right back", "brb and brb"),
            ("dr smith", "Dr. Alexandra Smith", "meeting with dr smith tomorrow"),
            ("dr smith", "Dr. Alexandra Smith", "meeting with doctor smith tomorrow"),
            ("t and c", "terms & conditions", "see t and c"),
            ("t and c", "terms & conditions", "see t & c"),
            ("my link", "https://example.com/a?b=1&c=2", "open my link then"),
            ("gm", "good morning", "gm everyone"),
            ("gm", "good morning", "the gm of the company"),
        ]
        for (t, e, said) in cases {
            let ex = SnippetExpander(snippets: [Snippet(id: UUID(), trigger: t, expansion: e, created: Date())], in: nil)
            print("PROBE [\(t)] \"\(said)\" -> \"\(ex.expand(said).text.replacingOccurrences(of: "\n", with: "⏎"))\"")
        }
    }
}

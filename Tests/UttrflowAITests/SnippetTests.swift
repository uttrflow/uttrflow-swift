import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAI

/// A fixed instant shared by every snippet test; nothing in this feature reads the real clock.
let snippetEpoch = Date(timeIntervalSince1970: 1_700_000_000)

/// A snippet's derived words, usability, use counting and encoding.
@Suite("A snippet, as it is stored")
struct SnippetTests {
    @Test(
        "reduces a trigger to the words a speaker could actually say",
        arguments: [
            ("my address", ["my", "address"]),
            ("My Address", ["my", "address"]),
            ("  my   address  ", ["my", "address"]),
            // Everything typed that speech cannot produce is dropped, so the listed trigger is the real one.
            ("my address:", ["my", "address"]),
            (";addr", ["addr"]),
            ("sign-off", ["sign", "off"]),
            ("v2 notes", ["v2", "notes"]),
            ("", []),
            ("!!!", []),
        ]
    )
    func triggerWords(trigger: String, expected: [String]) {
        #expect(makeSnippet(trigger: trigger).triggerWords == expected)
    }

    @Test(
        "knows whether it could ever fire",
        arguments: [
            ("my address", "Flat 402", true),
            // A trigger with no words would match at every position.
            ("", "Flat 402", false),
            ("???", "Flat 402", false),
            // An expansion with nothing in it would replace words with silence.
            ("my address", "", false),
            ("my address", "   \n  ", false),
        ]
    )
    func usability(trigger: String, expansion: String, expected: Bool) {
        #expect(makeSnippet(trigger: trigger, expansion: expansion).isUsable == expected)
    }

    @Test("counting a use advances the counter and the clock, and changes nothing else")
    func recordingAUse() {
        let snippet = makeSnippet(trigger: "sign off", expansion: "Thanks, Naveen")
        let later = snippetEpoch.addingTimeInterval(3_600)

        let used = snippet.used(at: later).used(at: later)

        #expect(used.timesUsed == 2)
        #expect(used.lastUsed == later)
        #expect(used.id == snippet.id)
        #expect(used.trigger == snippet.trigger)
        #expect(used.expansion == snippet.expansion)
        #expect(used.created == snippet.created)
    }

    @Test("a snippet that has never fired says so")
    func neverUsed() {
        #expect(makeSnippet(trigger: "sign off").lastUsed == nil)
        #expect(makeSnippet(trigger: "sign off").timesUsed == 0)
    }

    /// The file is the only copy, so a field that does not survive the round trip is lost on quit.
    @Test("survives being written down and read back")
    func codableRoundTrip() throws {
        let snippet = makeSnippet(trigger: "standup", expansion: "Yesterday:\nToday:\nBlockers:")
            .used(at: snippetEpoch)
        let decoded = try JSONDecoder().decode(
            Snippet.self, from: JSONEncoder().encode(snippet))
        #expect(decoded == snippet)
    }
}

// MARK: - Fixtures

/// A snippet with defaults for everything but the trigger.
func makeSnippet(
    id: UUID = UUID(), trigger: String, expansion: String = "the text", created: Date = snippetEpoch
) -> Snippet {
    Snippet(id: id, trigger: trigger, expansion: expansion, created: created)
}

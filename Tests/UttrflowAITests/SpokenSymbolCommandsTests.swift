import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// Symbols said by name are written in every destination, and a mention or an ordinary use of the words stays as said.
@Suite("Spoken ellipsis and symbol commands", .bug(id: 3618))
struct SpokenSymbolCommandsTests {
    private func clean(_ text: String, in destination: Destination = .plain) async throws -> String {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let request = TransformationRequest(
            transcription: .fixture(text: text, language: .english), situation: situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test("writes each symbol in prose, a document and a message")
    func writesSymbols() async throws {
        for destination in [Destination.plain, .document, .messaging] {
            for (spoken, expected) in [
                ("well dot dot dot maybe not", "Well\u{2026} maybe not."),
                ("sales grew by forty percent sign this year", "Sales grew by 40% this year."),
                ("ping me at sign sam on the thread", "Ping me @sam on the thread."),
                ("tag it hash sign launch day", "Tag it #launch day."),
                ("we hired smith ampersand jones", "We hired smith & jones."),
            ] {
                let cleaned = try await clean(spoken, in: destination)
                // A message carries no closing full stop, so only that differs between the destinations.
                let written = destination == .messaging ? String(expected.dropLast()) : expected
                #expect(cleaned == written, "\(destination): \(cleaned)")
            }
        }
    }

    @Test("keeps the words where they are named or used as words")
    func keepsOrdinaryUses() async throws {
        for (spoken, expected) in [
            ("type an ampersand there", "Type an ampersand there."),
            ("the at sign is on the two key", "The at sign is on the two key."),
            ("we made a hash of it", "We made a hash of it."),
            ("the percent sign key is stuck", "The percent sign key is stuck."),
            ("look at the sign by the door", "Look at the sign by the door."),
            ("connect the dot to the next dot", "Connect the dot to the next dot."),
        ] {
            let cleaned = try await clean(spoken)
            #expect(cleaned == expected, "\(cleaned)")
        }
    }

    @Test("a symbol written onto the next word opens no quotation")
    func leadingSymbolOpensNoQuotation() async throws {
        let cleaned = try await clean("he wrote open quote thanks at sign sam close quote and left")
        #expect(cleaned == "He wrote \"thanks @sam\" and left.", "\(cleaned)")
    }
}

import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// "at Sam" opening a chat message or one of its clauses is written as the mention "@Sam", and nowhere else.
@Suite("Spoken at-mentions", .bug(id: 2264))
struct AtMentionTests {
    private func clean(
        _ text: String, in destination: Destination = .messaging, after precedingText: String? = nil
    ) async throws -> String {
        let app = AppContext(precedingText: precedingText)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let request = TransformationRequest(
            transcription: .fixture(text: text, language: .english), situation: situation)
        let cleaned = try await RuleBasedTransformer().transform(request).text
        return cleaned
    }

    @Test("a message or clause opened by \"at\" and a name mentions that name")
    func writesMention() async throws {
        #expect(try await clean("at Sam can you take a look") == "@Sam, can you take a look?")
        #expect(
            try await clean("at Sam can you take a look", after: "sounds good, ")
                == "@Sam, can you take a look?")
        #expect(try await clean("thanks. at Priya can you review") == "Thanks. @Priya, can you review?")
    }

    @Test("\"at\" stays a word outside a chat, inside a clause, before a possessive or a calendar word")
    func keepsTheWord() async throws {
        #expect(
            try await clean("at Sam can you take a look", in: .document) == "At Sam, can you take a look?")
        for spoken in ["let's meet at Sam's place", "I'm at home", "at Sam's place now", "at Monday we ship"]
        {
            let cleaned = try await clean(spoken)
            #expect(!cleaned.contains("@"), "\(spoken) -> \(cleaned)")
        }
        #expect(try await clean("ping me at Sam") == "Ping me at Sam")
    }
}

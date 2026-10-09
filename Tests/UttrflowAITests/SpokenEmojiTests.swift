import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// An emoji said by name is written only once the user switches emoji on, never in code or a terminal.
@Suite("Spoken emoji names", .bug(id: 3618))
struct SpokenEmojiTests {
    private let emojiOn = CleaningSteps.default.setting(.spokenEmoji, isOn: true)

    private func clean(
        _ text: String, in destination: Destination = .plain, steps: CleaningSteps
    ) async throws -> String {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let request = TransformationRequest(
            transcription: .fixture(text: text, language: .english), situation: situation)
        return try await RuleBasedTransformer(steps: steps).transform(request).text
    }

    @Test("writes the emoji in prose, a document, an email and a message when switched on")
    func writesEmoji() async throws {
        for destination in [Destination.plain, .document, .email, .messaging] {
            let cleaned = try await clean("great work thumbs up emoji", in: destination, steps: emojiOn)
            #expect(cleaned.hasPrefix("Great work \u{1F44D}"), "\(destination): \(cleaned)")
        }
        let waved = try await clean("see you soon waving hand emoji", steps: emojiOn)
        // An emoji ends the message itself, so no full stop follows it.
        #expect(waved == "See you soon \u{1F44B}", "\(waved)")
        #expect(try await clean("heart emoji thanks", steps: emojiOn) == "\u{2764}\u{FE0F} thanks.")
    }

    @Test("is off until switched on")
    func offByDefault() async throws {
        #expect(!CleaningSteps.default.runs(.spokenEmoji))
        let cleaned = try await clean("great work thumbs up emoji", steps: .default)
        #expect(cleaned == "Great work thumbs up emoji.")
    }

    @Test("leaves the name in code and a terminal")
    func keepsNameInCode() async throws {
        for destination in [Destination.codeEditor, .terminal, .sqlEditor] {
            let cleaned = try await clean("thumbs up emoji", in: destination, steps: emojiOn)
            #expect(!cleaned.contains("\u{1F44D}"), "\(destination): \(cleaned)")
        }
    }

    @Test("keeps ordinary uses of the words")
    func keepsOrdinaryUses() async throws {
        for (spoken, expected) in [
            ("she gave me a thumbs up", "She gave me a thumbs up."),
            ("the fire alarm went off", "The fire alarm went off."),
            ("just say heart emoji there", "Just say heart emoji there."),
            ("put a laughing emoji at the end", "Put a laughing emoji at the end."),
        ] {
            let cleaned = try await clean(spoken, steps: emojiOn)
            #expect(cleaned == expected, "\(cleaned)")
        }
    }

    @Test("every emoji row ends in its marker word and stays out of code and terminals")
    func rowsAreGuarded() {
        #expect(SpokenCommands.emoji.count >= 20)
        for row in SpokenCommands.emoji {
            #expect(row.words.last == "emoji", "\(row.id)")
            for destination in [Destination.codeEditor, .terminal, .sqlEditor] {
                #expect(!row.isEnabled(in: destination), "\(row.id)")
            }
        }
    }

    @Test("an opt-in step survives storage and a preset")
    func optInStepIsKept() throws {
        let stored = try JSONDecoder().decode(CleaningSteps.self, from: JSONEncoder().encode(emojiOn))
        #expect(stored.runs(.spokenEmoji))
        #expect(QualityPreset.verbatim.applied(to: emojiOn).runs(.spokenEmoji))
        #expect(!emojiOn.setting(.spokenEmoji, isOn: false).runs(.spokenEmoji))
    }
}

import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// A listed name said as letters and number words is written as the lexicon writes it, before either pass splits it.
@Suite("Spelled names with a number word", .bug(id: 4074))
struct SpelledNamePassTests {
    private func clean(_ text: String, in destination: Destination = .plain) async throws -> String {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let request = TransformationRequest(
            transcription: .fixture(text: text, language: .english), situation: situation)
        return try await RuleBasedTransformer().transform(request).text
    }

    @Test(
        "each listed name is written whole at a sentence start, mid-sentence, before a unit and in a list",
        arguments: [
            ("e c two", "EC2"), ("s three", "S3"), ("k eight s", "k8s"), ("i eighteen n", "i18n"),
            ("a eleven y", "a11y"), ("x eighty six", "x86"), ("m p three", "MP3"), ("i p v six", "IPv6"),
            ("i p v four", "IPv4"), ("o auth two", "OAuth2"), ("l ten n", "L10n"), ("e two e", "E2E"),
            ("b two b", "B2B"), ("p two p", "P2P"), ("w three c", "W3C"), ("m p four", "MP4"),
        ])
    func writesWhole(spoken: String, written: String) async throws {
        let midSentence = try await clean("we moved it to \(spoken) last week")
        #expect(midSentence.contains(" \(written) "), "\(midSentence)")
        let start = try await clean("\(spoken) is down")
        #expect(start.contains("\(written) is down"), "\(start)")
        let list = try await clean("\(spoken) and docs")
        #expect(list.contains("\(written) and docs"), "\(list)")
    }

    @Test("a name before a unit keeps its digits apart from the quantity")
    func beforeUnit() async throws {
        let cleaned = try await clean("the e c two box has sixteen gigabytes")
        #expect(cleaned.contains("EC2 box has 16"), "\(cleaned)")
    }

    @Test("a name absent from the lexicon, and plain letters then a number, stay as today")
    func unlisted() async throws {
        let expected = [
            "plan b two": "See plan B2 today.", "a one": "See a one today.", "i two": "See i two today.",
        ]
        for (spoken, cleaned) in expected {
            #expect(try await clean("see \(spoken) today") == cleaned)
        }
    }

    @Test("a name the lexicon lists is not rewritten when the words are not adjacent")
    func notAdjacent() async throws {
        let cleaned = try await clean("e c then two")
        #expect(!cleaned.contains("EC2"), "\(cleaned)")
    }

    @Test("does not state keepsDigits, because a number word becomes a digit")
    func writesADigitSoDoesNotKeepDigits() {
        let written = SpelledNamePass().apply(Draft(text: "s three")).text
        #expect(written == "S3")
        #expect(!SpelledNamePass.laws.contains(.keepsDigits))
    }
}

import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A letter's greeting name and signature name take their capitals")
struct LetterNamesPassTests {
    private static func cleaned(
        _ text: String, destination: Destination = .email, vocabulary: [String] = []
    ) -> String {
        let app = AppContext(accessibilityRole: "AXTextArea", isMultiline: true)
        let situation = Situation(app: app, insertion: .unknown, destination: destination)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.message(for: formatter, situation: situation, vocabulary: vocabulary)
            .run(Draft(text: text)).text
    }

    @Test("a title and a surname after dear, and a signed name, are cased")
    func titleAndSurname() {
        #expect(
            Self.cleaned("dear ms alvarez, thank you for the call. yours sincerely, asha verma")
                == "Dear Ms Alvarez,\n\nThank you for the call.\n\nYours sincerely, Asha Verma")
        #expect(Self.cleaned("dear ms alvarez, thanks. yours sincerely asha verma").hasSuffix("Asha Verma"))
    }

    @Test("a greeting with no sign-off in an email is cased too")
    func greetingAlone() {
        #expect(Self.cleaned("hi priya, can you send the deck").hasPrefix("Hi Priya,"))
    }

    @Test("a name particle keeps the case it was said in")
    func particleKept() {
        #expect(
            Self.cleaned("dear pieter van berg, thanks. best regards ana").hasPrefix("Dear Pieter van Berg,"))
    }

    @Test("an everyday word in the name slot is not capitalised")
    func everydayWordKept() {
        #expect(Self.cleaned("hi team, can you send the deck").hasPrefix("Hi team,"))
    }

    @Test("a name already cased, and a Hindi honorific after a name, keep their case")
    func castKept() {
        #expect(Self.cleaned("dear McAllister, thanks. best regards ana").hasPrefix("Dear McAllister,"))
        #expect(Self.cleaned("dear asha ji, thanks. best regards ana").hasPrefix("Dear Asha ji,"))
    }

    @Test("milliseconds in the body stay a unit and only the name slot is read")
    func unitKept() {
        let text = Self.cleaned("dear ms alvarez, the delay is forty ms. best regards ana")
        #expect(text.contains("forty ms."))
    }

    @Test("a document is read only when it is a letter, and a chat never")
    func scope() {
        #expect(Self.cleaned("hi priya, the deck is ready", destination: .document).hasPrefix("Hi priya,"))
        #expect(
            Self.cleaned("hi priya, can you send the deck", destination: .messaging).hasPrefix("Hi priya,"))
    }

    @Test("it adds no word and is idempotent")
    func idempotent() {
        let pass = LetterNamesPass()
        let once = pass.apply(Draft(text: "Dear ms alvarez, thanks.\n\nYours sincerely,\nasha verma"))
        #expect(pass.apply(once).text == once.text)
        #expect(
            once.words.count
                == Draft(text: "Dear ms alvarez, thanks.\n\nYours sincerely,\nasha verma").words.count)
    }
}

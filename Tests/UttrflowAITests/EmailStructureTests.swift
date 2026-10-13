import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("An email body sets its greeting and sign-off on their own lines")
struct EmailStructureTests {
    private static func cleaned(
        _ text: String, destination: Destination = .email, multiline: Bool = true
    ) -> String {
        let app = AppContext(accessibilityRole: "AXTextArea", isMultiline: multiline)
        let situation = Situation(app: app, insertion: .unknown, destination: destination)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: text)).text
    }

    @Test(
        "a comma-closed greeting and an explicit sign-off each take a paragraph",
        arguments: [
            (
                "hi sam, can you send the deck. thanks, ana",
                "Hi sam,\n\nCan you send the deck.\n\nThanks, ana"
            ),
            (
                "dear dr jones, please send the deck. best regards ana",
                "Dear Dr Jones,\n\nPlease send the deck.\n\nBest regards ana"
            ),
        ])
    func laysOut(spoken: String, expected: String) {
        #expect(Self.cleaned(spoken) == expected)
    }

    @Test("the greeting alone, a greeting with no comma and a plain sentence stay as spoken")
    func leavesOthers() {
        #expect(Self.cleaned("hi sam") == "Hi sam")
        #expect(
            Self.cleaned("hi sam can you send the deck") == "Hi sam, can you send the deck?")
        #expect(Self.cleaned("send the deck to sam, please") == "Send the deck to sam, please.")
    }

    @Test("a chat message keeps its greeting inline")
    func chatUnchanged() {
        let chat = Self.cleaned("hi sam, can you send the deck", destination: .messaging)
        #expect(!chat.contains("\n"))
    }

    @Test("a one-line email field is never split")
    func oneLineUnchanged() {
        #expect(Self.cleaned("hi sam, can you send the deck", multiline: false).contains("\n") == false)
    }

    @Test("it adds and drops no word, and is idempotent")
    func keepsWords() {
        let pass = EmailStructurePass()
        let draft = Draft(text: "Hi Sam, can you send the deck. Thanks, Ana")
        let once = pass.apply(draft)
        #expect(once.text == "Hi Sam,\n\ncan you send the deck.\n\nThanks, Ana")
        #expect(pass.apply(once).text == once.text)
    }

    @Test("a letter in a document is laid out like an email, and other document text is not")
    func documentLetter() {
        #expect(
            Self.cleaned("hi sam, can you send the deck. thanks, ana", destination: .document)
                == "Hi sam,\n\nCan you send the deck.\n\nThanks, ana")
        #expect(
            Self.cleaned("hi sam, the deck is ready", destination: .document)
                == "Hi sam, the deck is ready.")
    }
}

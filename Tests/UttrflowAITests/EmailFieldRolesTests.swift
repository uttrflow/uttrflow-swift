import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A mail composer's subject, body and unlabelled fields are each formatted for what they hold")
struct EmailFieldRolesTests {
    private static func cleaned(
        _ text: String, destination: Destination = .email, label: String?, multiline: Bool
    ) -> String {
        let app = AppContext(
            accessibilityRole: multiline ? "AXTextArea" : "AXTextField", isMultiline: multiline,
            fieldLabel: label)
        let situation = Situation(app: app, insertion: .unknown, destination: destination)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: text)).text
    }

    @Test(
        "a subject starts with a capital and gets no stop and no line break",
        arguments: [
            ("meeting moved to friday", "Meeting moved to Friday"),
            ("quarterly report attached", "Quarterly report attached"),
            ("lunch at noon", "Lunch at noon"),
            ("question about the invoice", "Question about the invoice"),
            ("see you at the office", "See you at the office"),
            ("budget review for next week", "Budget review for next week"),
            ("follow up on our call", "Follow up on our call"),
            ("please review the draft", "Please review the draft"),
            ("notes at example dot com", "Notes at example.com"),
            ("welcome to the team", "Welcome to the team"),
            ("agenda for monday", "Agenda for Monday"),
            ("thanks for your help", "Thanks for your help"),
            ("travel plans for march", "Travel plans for march"),
            ("new hire paperwork", "New hire paperwork"),
            ("reminder about the offsite", "Reminder about the offsite"),
            ("update on the launch date", "Update on the launch date"),
            ("running late today", "Running late today"),
            ("photos from the trip", "Photos from the trip"),
            ("feedback on the proposal", "Feedback on the proposal"),
            ("invitation to the party", "Invitation to the party"),
        ]
    )
    func subject(spoken: String, written: String) {
        #expect(Self.cleaned(spoken, label: "Subject", multiline: false) == written)
    }

    @Test(
        "a body keeps at as a word and ends its sentence with a stop",
        arguments: [
            "meet sam at example dot com",
            "lunch at noon",
            "see you at the office",
            "notes at example dot com",
            "i am at the airport",
            "call me at five",
            "we start at nine",
            "look at the report",
            "the meeting is at three",
            "he is good at maths",
            "stay at home today",
            "arrive at the gate early",
            "she was at the shop",
            "aim at the target",
            "come at once",
            "at least try it",
            "we met at the bank",
            "wait at the door",
            "i will be at my desk",
            "dinner is at eight",
        ]
    )
    func body(spoken: String) {
        let written = Self.cleaned(spoken, label: "Message body", multiline: true)
        #expect(!written.contains("@"))
        #expect(written.hasSuffix("."))
        #expect(written.first?.isUppercase == true)
    }

    @Test(
        "an unlabelled one-line field is plain text, not an email body",
        arguments: [
            "hi sam, can you send the deck",
            "thanks, ana",
            "sam at example dot com",
            "best regards ana",
        ]
    )
    func unlabelledOneLine(spoken: String) {
        let email = Self.cleaned(spoken, label: nil, multiline: false)
        let plain = Self.cleaned(spoken, destination: .plain, label: nil, multiline: false)
        #expect(email == plain)
    }
}

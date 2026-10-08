import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A mail composer's fields and spoken addresses")
struct RecipientFieldAddressTests {
    private static func cleaned(_ text: String, label: String, multiline: Bool) -> String {
        let app = AppContext(accessibilityRole: "AXTextField", isMultiline: multiline, fieldLabel: label)
        let situation = Situation(app: app, insertion: .unknown, destination: .email)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: text)).text
    }

    @Test(
        "a recipient field writes a plain-word mailbox as its address, with no stop and no added space",
        arguments: [
            ("sam at example dot com", "sam@example.com"),
            ("priya at example dot org", "priya@example.org"),
            ("jo dot lee at example dot com", "jo.lee@example.com"),
            ("ops at mail dot example dot com", "ops@mail.example.com"),
            ("billing at example dot net", "billing@example.net"),
            ("team underscore lead at example dot com", "team_lead@example.com"),
            ("ravi at example dot co dot uk", "ravi@example.co.uk"),
            ("help at example dot io", "help@example.io"),
            ("anna at sub dot example dot com", "anna@sub.example.com"),
            ("max at example dot de", "max@example.de"),
            ("lena at example dot com", "lena@example.com"),
            ("tom at example dot com and kim at example dot com", "tom@example.com and kim@example.com"),
            ("hr at example dot com", "hr@example.com"),
            ("sales at example dot in", "sales@example.in"),
            ("omar dot khan at example dot org", "omar.khan@example.org"),
            ("news at example dot com", "news@example.com"),
            ("dev at example dot dev", "dev@example.dev"),
            ("info at example dot com", "info@example.com"),
            ("maya at example dot edu", "maya@example.edu"),
            ("admin at example dot com", "admin@example.com"),
        ]
    )
    func recipient(spoken: String, written: String) {
        for label in ["To", "Cc", "Bcc"] {
            #expect(Self.cleaned(spoken, label: label, multiline: false) == written, "\(label)")
        }
    }

    @Test(
        "a subject or a body keeps a plain word before at as a word",
        arguments: [
            "meet sam at example dot com",
            "lunch at noon",
            "see you at the office",
            "notes at example dot com",
        ]
    )
    func subjectAndBody(spoken: String) {
        #expect(!Self.cleaned(spoken, label: "Subject", multiline: false).contains("@"))
        #expect(!Self.cleaned(spoken, label: "Message body", multiline: true).contains("@"))
    }
}

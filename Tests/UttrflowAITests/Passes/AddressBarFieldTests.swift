import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A browser's address bar takes a web address or a query as the field expects")
struct AddressBarFieldTests {
    private func written(_ spoken: String, label: String = "Address and search bar") -> String {
        let app = AppContext(
            precedingText: "", accessibilityRole: "AXTextField", isMultiline: false, fieldLabel: label)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .plain)
        return CleaningPipeline.standard(
            for: DestinationFormatter.standard(for: situation), situation: situation
        ).run(Draft(text: spoken)).text
    }

    @Test(
        "writes a spoken web address as the address",
        arguments: [
            ("example dot com", "example.com"),
            ("example dot com slash docs", "example.com/docs"),
            ("docs dot example dot org", "docs.example.org"),
            ("example dot com slash docs slash intro", "example.com/docs/intro"),
            ("example dot co dot uk", "example.co.uk"),
            ("example dot dev", "example.dev"),
            ("go to example dot com", "go to example.com"),
        ])
    func writesAddress(spoken: String, expected: String) {
        #expect(written(spoken) == expected)
    }

    @Test(
        "keeps a query as the words said, in lower case with no stop",
        arguments: [
            "weather in lisbon tomorrow", "how to bake bread", "best pizza near me",
            "what time is it in tokyo",
            "cheap flights to rome", "translate hello to french", "convert ten miles to kilometres",
            "the end of the world", "red dot reflex sight reviews", "who won the match last night",
            "recipe for dal", "capital of australia",
        ])
    func keepsQuery(spoken: String) {
        let out = written(spoken)
        #expect(!out.contains("://") && !out.contains(".com"))
        #expect(out.first?.isLowercase == true)
        #expect(out.last?.isPunctuation != true)
    }
}

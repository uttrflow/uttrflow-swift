import Testing

@testable import UttrflowCore

@Suite("Recognition context eligibility")
struct RecognitionContextTests {
    private func context(
        _ text: String, destination: Destination = .plain, document: String? = nil, secure: Bool = false
    ) -> String? {
        let app = AppContext(documentName: document, precedingText: text, isSecure: secure)
        return Situation(app: app, insertion: app.insertionPoint, destination: destination).recognitionContext
    }

    @Test("prose passes through unchanged")
    func prosePasses() {
        #expect(context("We met on Tuesday. Then we left.") == "We met on Tuesday. Then we left.")
    }

    @Test("list, quote and heading markers are stripped")
    func markersStripped() {
        #expect(context("- buy milk and eggs") == "buy milk and eggs")
        #expect(context("3. call the dentist") == "call the dentist")
        #expect(context("> thanks for the update") == "thanks for the update")
        #expect(context("## Plans for next week") == "Plans for next week")
        #expect(context("-5 degrees tonight") == "-5 degrees tonight")
    }

    @Test("terminal, spreadsheet and query destinations give nothing")
    func nonProseDestinations() {
        for destination in [Destination.terminal, .spreadsheet, .sqlEditor] {
            #expect(context("Please send the report.", destination: destination) == nil)
        }
    }

    @Test("code is excluded, a comment's words are kept without its opener")
    func codeAndComments() {
        let code = "let total = items.map { $0.price }"
        #expect(context(code, destination: .codeEditor, document: "Cart.swift") == nil)
        #expect(
            context("// Reads the cart total", destination: .codeEditor, document: "Cart.swift")
                == "Reads the cart total")
        #expect(context("Some words here", destination: .codeEditor) == nil)
    }

    @Test("prompts, formulas and call syntax are dropped line by line")
    func nonProseLines() {
        #expect(context("$ git status\nThe build is green.") == "The build is green.")
        #expect(context("=SUM(A1:A4)") == nil)
        #expect(context("Then call run(x) twice") == nil)
        #expect(context("user@host ~$ ls") == nil)
    }

    @Test("a secure field and secret-shaped runs give nothing")
    func secrets() {
        #expect(context("Hello there.", secure: true) == nil)
        #expect(context("key ASIAY34FZKBOKMUTVV7A now") == "key now")
    }
}

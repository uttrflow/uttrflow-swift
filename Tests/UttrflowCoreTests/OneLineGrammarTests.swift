import Testing

@testable import UttrflowCore

@Suite("A one-line field keeps its words as spoken", .bug(id: 4453))
struct OneLineGrammarTests {
    @Test("a document's text field and an email's subject do not repair grammar")
    func oneLineFieldsKeepGrammar() {
        let field = AppContext(documentName: "Notes", accessibilityRole: "AXTextField")
        let document = Situation(app: field, insertion: field.insertionPoint, destination: .document)
        #expect(DestinationFormatter.standard(for: document).grammar == .asSpoken)
        let subject = AppContext(fieldLabel: "Subject")
        let mail = Situation(app: subject, insertion: subject.insertionPoint, destination: .email)
        #expect(DestinationFormatter.standard(for: mail).grammar == .asSpoken)
        let body = AppContext(documentName: "Draft")
        let message = Situation(app: body, insertion: body.insertionPoint, destination: .email)
        #expect(DestinationFormatter.standard(for: message).grammar == .repair)
    }
}

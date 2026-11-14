import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A one-line form field is written as the value its label asks for")
struct FormFieldKindTests {
    private func written(_ spoken: String, label: String) -> String {
        let app = AppContext(
            precedingText: "", accessibilityRole: "AXTextField", isMultiline: false, fieldLabel: label)
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    @Test(
        "writes an email, a phone number, a postal code, a date and a number as the value",
        arguments: [
            ("Email", "neha dot rao at example dot com", "neha.rao@example.com"),
            ("Phone", "five five five zero one two three", "5550123"),
            ("Phone", "plus four four seven nine one one", "+447911"),
            ("Postal code", "four one zero zero zero one", "410001"),
            ("Postal code", "s w one a one a a", "SW1A1AA"),
            ("Date of birth", "twelve march twenty twenty six", "12 March 2026"),
            ("Quantity", "twenty five", "25"),
            ("Quantity", "five", "5"),
            ("Quantity", "two hundred and fifty", "250"),
            ("Website", "example dot com slash docs", "example.com/docs"),
        ])
    func writesValue(label: String, spoken: String, expected: String) {
        #expect(written(spoken, label: label) == expected)
    }

    @Test(
        "keeps a name or an address as the words were said, with no capital the speaker did not give",
        arguments: [
            ("First name", "john smith", "john smith"),
            ("Name", "neha rao", "neha rao"),
            ("Full name", "John Smith", "John Smith"),
            ("Street address", "twelve baker street flat four", "12 baker street flat four"),
            ("Address line 1", "forty two example road", "42 example road"),
        ])
    func keepsWords(label: String, spoken: String, expected: String) {
        #expect(written(spoken, label: label) == expected)
    }

    @Test(
        "writes a sentence said into a name field as the sentence",
        arguments: [
            ("my name is john smith", "my name is john smith"),
            ("it is john smith from the office", "it is john smith from the office"),
        ])
    func sentenceInNameField(spoken: String, expected: String) {
        #expect(written(spoken, label: "Full name") == expected)
    }
}

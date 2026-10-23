import Testing
import UttrflowCore

@testable import UttrflowAI

/// Prose places write every spoken number as a numeral, as cells and editors do. See `Docs/cleanup.md`.
@Suite("Prose number forms")
struct ProseNumberFormsTests {
    static let prose: [Destination] = [.plain, .document, .email, .messaging]

    private static func cleaned(_ text: String, into destination: Destination) -> String {
        let situation = Situation(app: AppContext(), insertion: .unknown, destination: destination)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: text)).text
    }

    @Test("every prose place writes a spoken number as a numeral", arguments: prose)
    func proseTakesEveryNumeral(destination: Destination) {
        #expect(DestinationFormatter.standard(for: destination).numbers == .always)
    }

    @Test(
        "a spoken number in prose is a numeral, zero to nine included",
        arguments: [
            ("I paid five dollars for three apples and twelve oranges", "I paid $5 for 3 apples and 12 oranges"),
            ("we raised two point five million dollars from nine investors", "we raised $2.5 million from 9 investors"),
            ("eight percent of fifty is four", "8% of 50 is 4"),
            ("meet me at five", "meet me at 5"),
            ("the taxi cost five dollars", "the taxi cost $5"),
            ("we have two kids", "we have 2 kids"),
            ("take the four o'clock bus", "take the 4 o'clock bus"),
            ("add one row", "add 1 row"),
            ("zero errors", "0 errors"),
            ("from ten to one", "from 10 to 1"),
            ("one litre and one chopped onion", "1 litre and 1 chopped onion"),
            ("seven days", "7 days"),
            ("six feet", "6 feet"),
            ("two seconds", "2 seconds"),
            ("about fifteen people", "about 15 people"),
            ("three hundred forty-five people", "345 people"),
            ("nine thousand rupees", "₹9,000"),
            ("forty-five thousand", "45,000"),
            ("two thirty pm", "2:30 pm"),
            ("the third of June", "the 3rd of June"),
        ]
    )
    func numberForms(input: String, expected: String) {
        for destination in Self.prose {
            let output = Self.cleaned(input, into: destination)
            #expect(Self.stripped(output) == Self.stripped(expected), "\(destination): \(output)")
        }
    }

    @Test(
        "a spoken amount in prose is a currency symbol and digits",
        arguments: [
            ("it costs five dollars", "it costs $5"),
            ("it costs twelve dollars", "it costs $12"),
            ("nine dollars ninety nine", "$9.99"),
            ("two dollars fifty", "$2.50"),
            ("a five dollar bill", "a $5 bill"),
            ("twelve thousand five hundred dollars", "$12,500"),
            ("three euros", "€3"),
            ("forty euros for the ticket", "€40 for the ticket"),
            ("two hundred rupees", "₹200"),
            ("we raised ten million dollars", "we raised $10,000,000"),
            ("he paid two dollars and sixty cents", "he paid $2 and 60 cents"),
            ("five dollars, please", "$5, please"),
        ]
    )
    func currencyForms(input: String, expected: String) {
        for destination in Self.prose {
            let output = Self.cleaned(input, into: destination)
            #expect(Self.stripped(output) == Self.stripped(expected), "\(destination): \(output)")
        }
    }

    @Test("code and terminal places keep the currency word beside the digits", arguments: [Destination.codeEditor, .sqlEditor, .terminal])
    func codePlacesKeepTheWord(destination: Destination) {
        #expect(Self.stripped(Self.cleaned("it costs five dollars", into: destination)).hasSuffix("5 dollars"))
    }

    @Test(
        "a word that is not a count stays a word in prose",
        arguments: [
            ("no one knows", "no one knows"),
            ("which one is it", "which one is it"),
            ("they help one another", "they help one another"),
            ("just my two cents", "just my two cents"),
            ("open twenty four seven", "open twenty four seven"),
            ("give me a second", "give me a second"),
            ("about a hundred users", "about a hundred users"),
            ("pick the blue one", "pick the blue one"),
            ("we need a new one", "we need a new one"),
            ("two thirds of the team", "two thirds of the team"),
            ("return four thirteen when it is too large", "return four thirteen when it is too large"),
            ("ten minus three is seven", "10 minus 3 is 7"),
            ("it weighs five pounds", "it weighs 5 pounds"),
            ("one or two", "one or two"),
        ]
    )
    func exceptions(input: String, expected: String) {
        for destination in Self.prose {
            let output = Self.cleaned(input, into: destination)
            #expect(Self.stripped(output) == Self.stripped(expected), "\(destination): \(output)")
        }
    }

    /// The pass under test is the number's form; the first capital and the stop are the place's own.
    private static func stripped(_ text: String) -> String {
        var text = text
        if text.hasSuffix(".") || text.hasSuffix("?") { text.removeLast() }
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}

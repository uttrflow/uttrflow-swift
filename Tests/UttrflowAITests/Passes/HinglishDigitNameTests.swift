import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("English digit names inside a Hindi sentence")
struct HinglishDigitNameTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard.run(Draft(text: text)).text
    }

    @Test(
        "are written as digits after the Hindi copula",
        arguments: [
            (
                "mera number hai nine eight seven six five four three two one zero",
                "Mera number hai 9876543210."
            ),
            ("mera pin hai one two three four", "Mera pin hai 1234."),
            ("otp hai four five six seven", "Otp hai 4567."),
            ("yeh number tha one two three four", "Yeh number tha 1234."),
        ])
    func digitRunAfterCopula(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "are written as digits before the Hindi time-of-day word",
        arguments: [
            ("main kal five baje aaunga", "Main kal 5 baje aaunga."),
            ("meeting hai at five baje", "Meeting hai at 5 baje."),
        ])
    func numberBeforeHindiMeasure(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "stay words where no measure or digit cue follows",
        arguments: [
            ("i have five kids", "I have five kids."),
            ("mere paas five dost hain", "Mere paas five dost hain."),
            ("three din se baarish ho rahi hai", "Three din se baarish ho rahi hai."),
        ])
    func plainCountStaysWords(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("the English reading of the same run is unchanged")
    func englishRunUnchanged() {
        #expect(
            cleaned("my number is nine eight seven six five four three two one zero")
                == "My number is 9876543210.")
    }
}

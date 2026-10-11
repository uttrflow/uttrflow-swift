import Testing

@testable import UttrflowCore

@Suite("One spelling per listed Hindi word")
struct RomanisedVariantsTests {
    @Test("Two pieces from different engines leave with one spelling of each word")
    func twoEnginesAgree() {
        let rules = RomanisedVariants.canonicalised("Mujhe nahi pata kya hua.")
        let model = RomanisedVariants.canonicalised("Muje nhi pta kya huwa.")
        #expect(rules == "Mujhe nahi pata kya hua.")
        #expect(model == rules)
    }

    @Test(
        "A variant that is another word is never rewritten",
        arguments: [
            "Main ghar mein hoon aur woh kya kar raha hai.",
            "Mujhe to nahi pata ki he kya hai.",
            "Woh kal kahan the aur kya kar rahe the.",
        ])
    func collidingVariantsStay(_ hindi: String) {
        #expect(RomanisedVariants.canonicalised(hindi) == hindi)
    }

    @Test(
        "English text is byte-identical",
        arguments: [
            "I use the door to get in. Is it me or them?",
            "Are you going to the main hall with them, or not?",
            "Kya is a name, and so is Pata.",
        ])
    func englishUntouched(_ english: String) {
        #expect(RomanisedVariants.canonicalised(english) == english)
    }

    @Test("Only the clearly Hindi sentence is respelled, capital kept")
    func onlyHindiSentence() {
        let text = "Muje bhot kaam hai, kya karna hai? Call me abi."
        #expect(RomanisedVariants.canonicalised(text) == "Mujhe bahut kaam hai, kya karna hai? Call me abi.")
        #expect(RomanisedVariants.canonicalised("Nhi, mujhe nahi pata.") == "Nahi, mujhe nahi pata.")
    }
}

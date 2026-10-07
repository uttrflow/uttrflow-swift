import ApplicationServices
import Testing

@testable import UttrflowContext

struct AXFailedNamesReadTests {
    @Test("A missing role in the names batch refuses the field text read.")
    func missingRoleFailsClosed() {
        var fetched = Array(
            repeating: kCFNull as AnyObject, count: FocusedFieldReader.Answers.attributes.count)
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXTitleAttribute)!] =
            "private field title" as CFString
        let answers = FocusedFieldReader.Answers(AXUIElementCreateSystemWide(), fetched: fetched)

        #expect(answers.isSecure)
        #expect(answers.text == nil)
    }

    @Test("An unreadable subrole in the names batch refuses the field text read.")
    func unreadableSubroleFailsClosed() throws {
        var cannotComplete = AXError.cannotComplete
        let errorValue = try #require(AXValueCreate(.axError, &cannotComplete))
        var fetched = Array(
            repeating: kCFNull as AnyObject, count: FocusedFieldReader.Answers.attributes.count)
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXRoleAttribute)!] =
            "AXTextField" as CFString
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXSubroleAttribute)!] = errorValue
        fetched[FocusedFieldReader.Answers.attributes.firstIndex(of: kAXTitleAttribute)!] =
            "private field title" as CFString
        let answers = FocusedFieldReader.Answers(AXUIElementCreateSystemWide(), fetched: fetched)

        #expect(answers.isSecure)
        #expect(answers.text == nil)
    }
}

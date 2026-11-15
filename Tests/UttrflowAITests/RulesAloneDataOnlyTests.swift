import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Requests the rules reduce to a few prose words skip the model", .bug(id: 4067))
struct RulesAloneDataOnlyTests {
    private func request(_ text: String) -> TransformationRequest {
        TransformationRequest(transcription: Transcription(text: text))
    }

    @Test(
        "a request that is only data goes to the rules alone",
        arguments: [
            "call me on nine eight seven six five four three two one zero",
            "my code is a b c one two three four five six",
            "the version is two point three point one",
            "one four seven eight main street",
            "the pin is four four seven one nine nine",
        ])
    func dataOnlyGoesToRules(text: String) {
        #expect(RulesAlone.shortReplies.covers(request(text)), "\(text)")
    }

    @Test(
        "a sentence of prose still reaches the model",
        arguments: [
            "call me on friday at nine",
            "can you send the report to the team before lunch",
            "i think we should move the meeting to next week",
            "please remind me to buy milk and bread tomorrow",
            "she said the weather was lovely on thursday",
            "tell him i will be there in ten minutes",
            "we need to talk about the budget for the third quarter",
            "the quick brown fox jumps over the lazy dog",
            "let me know if you want to meet on tuesday morning",
            "thanks for sending the files over yesterday",
        ])
    func proseGoesToModel(text: String) {
        #expect(!RulesAlone.shortReplies.covers(request(text)), "\(text)")
    }

    @Test("a document that repairs grammar still asks the model about a slip next to a numeral")
    func documentKeepsTheModel() {
        let app = AppContext(documentName: "Notes")
        let document = TransformationRequest(
            transcription: Transcription(text: "she have fifteen cats"), context: app,
            situation: Situation(app: app, insertion: app.insertionPoint, destination: .document))
        #expect(!RulesAlone.shortReplies.covers(document))
    }

    @Test("a long request never skips the model when routing is off")
    func neverStaysOff() {
        #expect(!RulesAlone.never.covers(request("nine eight seven six five four three two one zero")))
    }
}

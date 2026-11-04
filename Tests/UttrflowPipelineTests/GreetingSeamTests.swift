// A pause cut between an email's greeting word and the name it greets leaves no stop after the greeting.

import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A greeting cut from its name keeps no stop")
struct GreetingSeamTests {
    private func pipeline() -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]),
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }

    @Test(
        "an email greeting cut before the name reads as the whole greeting does",
        arguments: [
            ["hi", "priya comma thanks for getting in touch"],
            ["hello", "priya comma thanks for getting in touch"],
            ["dear", "priya comma thanks for getting in touch"],
            ["hi", "priya thanks for getting in touch"],
            ["good morning", "priya comma thanks for getting in touch"],
        ])
    func greetingBeforeName(parts: [String]) async {
        let context = AppContext(
            applicationName: "Mail", bundleIdentifier: "com.apple.mail", precedingText: "")
        let whole = await pipeline().clean(
            [Transcription(text: parts.joined(separator: " "))], seeing: context
        ).text
        let joined = await pipeline().clean(parts.map { Transcription(text: $0) }, seeing: context).text
        #expect(joined == whole)
    }
}

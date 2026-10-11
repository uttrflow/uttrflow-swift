import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// The applications the pipeline asked its dictionary and snippets for, in order.
private actor AskedApplications {
    private(set) var asked: [String?] = []
    func note(_ application: String?) { asked.append(application) }
}

/// The scoped snippets on file, matched by the shipping matcher, noting where each dictation asked from.
private struct ScopedSnippets: SnippetExpanding {
    let asked: AskedApplications

    func expand(_ text: String, in application: String?) async -> ExpandedTranscript {
        await asked.note(application)
        let snippet = Snippet(
            trigger: "sign off", expansion: "Kind regards", created: .distantPast,
            applications: ["com.example.Mail"])
        let expansion = SnippetExpander(snippets: [snippet], in: application).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            })
    }
}

@Suite("Cleaning for the application in front")
struct ScopedCleaningTests {
    private func pipeline(noting asked: AskedApplications) -> DictationPipeline {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies)
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(), speechWords: { _ in [] },
            corrector: DictionaryCorrections { application in
                await asked.note(application)
                return PhoneticIndex(entries: [])
            },
            snippets: ScopedSnippets(asked: asked))
    }

    @Test(
        "the dictionary and the snippets are read for the front application, so a scoped snippet fires only there"
    )
    func readsForTheFrontApplication() async {
        let asked = AskedApplications()
        let mail = await pipeline(noting: asked).clean(
            [Transcription(text: "sign off")], seeing: AppContext(bundleIdentifier: "com.example.Mail"))
        let chat = await pipeline(noting: asked).clean(
            [Transcription(text: "sign off")], seeing: AppContext(bundleIdentifier: "com.example.Chat"))

        #expect(mail.text?.hasPrefix("Kind regards") == true)
        #expect(chat.text?.lowercased().hasPrefix("sign off") == true)
        #expect(Set(await asked.asked) == ["com.example.Mail", "com.example.Chat"])
    }
}

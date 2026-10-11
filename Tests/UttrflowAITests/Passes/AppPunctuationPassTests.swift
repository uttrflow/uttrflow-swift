import Testing

@testable import UttrflowAI
@testable import UttrflowCore

@Suite("A final stop and first letter fixed for one app, run through the passes")
struct AppPunctuationPassTests {
    private func run(_ text: String, _ punctuation: AppPunctuation) -> String {
        let bundle = "com.example.search"
        let overrides = DestinationOverrides.none.setting(
            punctuation: punctuation, for: bundle, named: nil, fallback: .document)
        let situation = SituationResolver.resolve(
            app: AppContext(bundleIdentifier: bundle), insertion: .unknown, overrides: overrides)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.message(for: formatter, situation: situation).run(Draft(text: text)).text
    }

    @Test("never drops only the final full stop, and the words stay")
    func neverDropsStop() {
        let never = AppPunctuation(finalStop: .never)
        #expect(run("meet me at noon.", never) == "Meet me at noon")
        #expect(run("It is late. Meet me at noon.", never) == "It is late. Meet me at noon")
    }

    @Test("never keeps a question mark")
    func neverKeepsQuestion() {
        #expect(run("are you free at noon?", AppPunctuation(finalStop: .never)) == "Are you free at noon?")
    }

    @Test("automatic keeps the destination's stop and capital")
    func automaticUnchanged() {
        #expect(run("meet me at noon", .automatic) == "Meet me at noon.")
    }

    @Test("never capital keeps the first word as heard, and always stop adds the stop")
    func neverCapital() {
        let lower = AppPunctuation(firstLetter: .never)
        #expect(run("meet me at noon", lower) == "meet me at noon.")
        #expect(
            run("meet me at noon", AppPunctuation(finalStop: .always, firstLetter: .never))
                == "meet me at noon.")
    }
}

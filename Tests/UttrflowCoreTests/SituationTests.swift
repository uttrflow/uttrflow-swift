import Testing

@testable import UttrflowCore

@Suite("Situation")
struct SituationTests {
    private let slack = AppContext(
        applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", documentName: "#ops")

    @Test("resolves the destination from the app and keeps the caret it was given")
    func resolvesFromParts() {
        let caret = InsertionPoint(precedingText: "so ", followingText: nil)
        let situation = SituationResolver.resolve(app: slack, insertion: caret)
        #expect(situation.app == slack)
        #expect(situation.insertion == caret)
        #expect(situation.destination == .messaging)
    }

    @Test("resolves from a context read, taking the caret text the read carried")
    func resolvesFromContext() {
        let read = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.apple.Notes",
            precedingText: "Because ", followingText: " later")
        let situation = SituationResolver.resolve(from: read)
        #expect(situation.destination == .document)
        #expect(situation.insertion == InsertionPoint(precedingText: "Because ", followingText: " later"))
        #expect(situation.insertion.sentenceState == .midSentence)
    }

    @Test("reads the table it is handed, not the shipped one")
    func honoursCustomRules() {
        let rules = [DestinationRule(bundlePrefixes: ["com.tinyspeck"], destination: .email)]
        #expect(
            SituationResolver.resolve(app: slack, insertion: .unknown, rules: rules).destination == .email)
    }

    @Test("knows nothing when the screen said nothing")
    func unknown() {
        #expect(Situation.unknown.app == .unknown)
        #expect(Situation.unknown.insertion == .unknown)
        #expect(Situation.unknown.destination == .plain)
        #expect(SituationResolver.resolve(from: .unknown) == .unknown)
    }

    @Test("a context with no caret text has an unknown insertion point")
    func contextWithoutCaret() {
        #expect(AppContext.unknown.insertionPoint == .unknown)
        #expect(AppContext(precedingText: "").insertionPoint.sentenceState == .startOfText)
    }
}

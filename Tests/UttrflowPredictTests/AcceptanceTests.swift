import Testing

@testable import UttrflowPredict

@Suite("What accepting actually inserts")
struct AcceptanceTests {
    @Test("Only the tail, because the head is already on screen in front of the caret.")
    func onlyTheTail() {
        #expect(Acceptance.remainder(of: "git commit", after: "git com") == "mit")
    }

    @Test("An empty field takes the whole suggestion.")
    func everythingFromNothing() {
        #expect(Acceptance.remainder(of: "git commit", after: "") == "git commit")
    }

    @Test("A suggestion already fully typed adds nothing.")
    func nothingLeftToAdd() {
        #expect(Acceptance.remainder(of: "git commit", after: "git commit") == nil)
    }

    @Test("A suggestion that does not continue what was typed cannot be accepted at all.")
    func mustContinueWhatWasTyped() {
        #expect(Acceptance.remainder(of: "git commit", after: "svn ci") == nil)
        #expect(Acceptance.remainder(of: "git commit", after: "Git com") == nil)
    }

    @Test("The prefix is counted in characters, so an emoji in the field does not shift the cut.")
    func countedInCharacters() {
        #expect(Acceptance.remainder(of: "🚀 launch now", after: "🚀 launch") == " now")
    }
}

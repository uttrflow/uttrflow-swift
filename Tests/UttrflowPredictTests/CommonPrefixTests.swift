import Testing

@testable import UttrflowPredict

@Suite("What a set of candidates agrees on")
struct CommonPrefixTests {
    @Test("Nothing agrees on nothing.")
    func empty() {
        #expect(CommonPrefix.of([]).isEmpty)
    }

    @Test("One string agrees with itself entirely.")
    func single() {
        #expect(CommonPrefix.of(["git commit"]) == "git commit")
    }

    @Test("Three commands agree on the part that is safe to insert.")
    func agreement() {
        let shared = CommonPrefix.of(["git commit -m", "git commit --amend", "git commit -a"])
        #expect(shared == "git commit -")
    }

    @Test("Candidates that share nothing agree on nothing.")
    func disagreement() {
        #expect(CommonPrefix.of(["alpha", "beta"]).isEmpty)
    }

    @Test("One string being a prefix of another is the whole agreement.")
    func containment() {
        #expect(CommonPrefix.of(["git", "git commit"]) == "git")
    }

    @Test("An empty string among them leaves nothing agreed.")
    func emptyMember() {
        #expect(CommonPrefix.of(["git commit", ""]).isEmpty)
    }

    @Test("Agreement is by character, so a shared emoji is not cut in half.")
    func unicode() {
        #expect(CommonPrefix.of(["🙂 ship it", "🙂 ship out"]) == "🙂 ship ")
    }
}

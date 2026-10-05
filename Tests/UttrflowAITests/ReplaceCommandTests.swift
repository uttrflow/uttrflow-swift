import Testing

@testable import UttrflowAI

@Suite("Replace X with Y plans an edit of the last insertion by word sequence")
struct ReplaceCommandTests {
    private func replace(_ find: String, _ replacement: String, in text: String) -> ReplaceOutcome {
        ReplaceCommand.apply(ReplaceRequest(find: find, replacement: replacement), to: text)
    }

    @Test("an utterance names the words to find and the words to write, without the recogniser's stop")
    func readsTheRequest() {
        #expect(
            ReplaceCommand.request(from: "Replace Aaron with Aarav.")
                == ReplaceRequest(find: "Aaron", replacement: "Aarav"))
        #expect(
            ReplaceCommand.request(from: "replace next week with the week after")
                == ReplaceRequest(find: "next week", replacement: "the week after"))
    }

    @Test("an utterance with nothing on either side of the separator is not a request")
    func refusesAnIncompleteUtterance() {
        #expect(ReplaceCommand.request(from: "replace with Aarav") == nil)
        #expect(ReplaceCommand.request(from: "replace Aaron with") == nil)
        #expect(ReplaceCommand.request(from: "please replace Aaron with Aarav") == nil)
    }

    @Test("a single match is replaced")
    func singleMatch() {
        #expect(
            replace("Aaron", "Aarav", in: "Ask Aaron about the build.")
                == .replaced(text: "Ask Aarav about the build.", matches: 1))
    }

    @Test("of two matches the one nearest the end is replaced, and the count says there were two")
    func nearestMatchWins() {
        #expect(
            replace("the build", "the release", in: "The build failed, so rerun the build.")
                == .replaced(text: "The build failed, so rerun the release.", matches: 2))
    }

    @Test("a word that only looks like the one asked for is not a match, so nothing is edited")
    func noMatchRefuses() {
        #expect(replace("Aarav", "Aaron", in: "Ask Aaron about it.") == .notFound)
        #expect(replace("run", "walk", in: "The runs are done.") == .notFound)
        #expect(replace("Aaron", "Aarav", in: "") == .notFound)
    }

    @Test("a match spans a punctuation mark between its words")
    func spansPunctuation() {
        #expect(
            replace("five then", "six", in: "Meet at five, then lunch.")
                == .replaced(text: "Meet at six lunch.", matches: 1))
    }

    @Test("a match at a sentence start keeps the capital; one mid-sentence takes the words as said")
    func casePreservedAtSentenceStart() {
        #expect(
            replace("tomorrow", "on friday", in: "Done. Tomorrow we ship.")
                == .replaced(text: "Done. On friday we ship.", matches: 1))
        #expect(
            replace("Tomorrow", "on friday", in: "We ship Tomorrow.")
                == .replaced(text: "We ship on friday.", matches: 1))
    }

    @Test("a dictionary term keeps its written case, even at a sentence start")
    func dictionaryTermKeepsItsCase() {
        #expect(
            replace("iowa", "iOS", in: "Iowa build is green.")
                == .replaced(text: "iOS build is green.", matches: 1))
    }
}

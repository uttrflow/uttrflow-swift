import Testing

@testable import UttrflowCore

/// The words of `text` as the passes see them.
private func shapes(_ text: String) -> [WordShape] {
    text.split(separator: " ").map { WordShape(String($0)) }
}

@Suite("QuestionShape")
struct QuestionShapeTests {
    @Test(
        "reads an inversion around a quantifier as a question",
        arguments: [
            "are both builds green", "is every test passing", "are all checks done", "is each step clear",
            "is either option fine", "is neither branch merged",
        ])
    func asksAroundAQuantifier(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test(
        "reads a direct question from its word order",
        arguments: [
            "where did you put the keys", "which branch should I merge into",
            "what time is the meeting tomorrow", "what time is it", "how many people are coming",
            "how are you", "can you send it", "did you see the email", "is it ready",
            "what's the status of the release", "can you review the pull request", "did the build go green",
            "is anyone using the room", "do you have a minute", "have you seen the numbers",
            "Would you like some coffee", "it's a long weekend isn't it",
            "you know the answer don\u{2019}t you",
            "so did you finish the slides", "okay can we start the call", "I sent the file, did you get it",
            "did the tests pass should i merge it now",
            "papa did you take your medicine",
            "didi can you ask jiju if he's free on saturday",
            "hey quick question do we support ios sixteen or only seventeen and above",
            "is the meeting at ten or eleven do we need the projector",
            "where did you park the car i cannot find it anywhere",
            "what happens if the call fails", "what changed", "what broke the build", "who made the change",
            "who owns the notification service",
            "the meeting is at three right", "you sent the invoice right", "the file is saved right",
            "we leave at noon right",
            "I'm blocked on the credentials for the sandbox account can someone help",
            "I think this will break if the array is empty can you add a check",
            "who owns the service that is down", "what about the release",
            "This duplicates the logic in the helper class can we reuse that instead",
            "I don't have access to the production database can someone grant it",
            "kya tum aa rahe ho", "kab tak ho jayega", "tum aa rahe ho kya", "report bhej di kya",
            "report bhej diya kya", "report karoge kya", "kaunsa option better hai", "kaunsi file chahiye",
            "kaunse option sahi hain", "kya hua", "meeting kab hai", "tum kyun nahi aaye",
            "tum kal aa rahe ho na",
            "may i come in", "may we leave early", "do they know", "had you heard about it",
            "were you there when it happened", "did it work",
            "how many of you are coming", "how much of it is left", "how about you",
            "how old are you", "what a mess is this",
        ])
    func asks(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test(
        "leaves a statement, an indirect question and a command alone",
        arguments: [
            "how nice of you to come", "how beautiful it is here", "what a day i am so tired",
            "what an idea you had", "what a lovely surprise", "what a mess this is", "what a day",
            "I wonder if the build passed", "what we need is more time", "what we need is more tests",
            "what works for you is fine", "who owns the house is unclear",
            "what I mean is we should wait",
            "the person who owns the notification service is unclear",
            "where I put the keys is a mystery",
            "I don't know why the build failed", "when the build finishes we ship",
            "do the dishes before you leave",
            "papa did the shopping",
            "papa are you around yet i should be there in ten",
            "have a great weekend", "tell me what you think", "that's right", "turn right at the station",
            "turn right", "you should turn right", "everything is right", "it feels right", "I have no right",
            "you got the answer right", "I think it is right",
            "if it rains, we stay in", "", "kya baat hai", "sunno na ek baat",
            "woh kya hai na yaani mujhe time chahiye",
            "the printer is jammed again who used it last",
            "please close the door will you be home tonight",
            "are you around yet i should be there in ten",
            "the report is late, which is annoying",
            "we moved the launch, which has upset the client",
            "the server crashed twice, which can happen",
            "the plan is simple, which does not help",
            "I forgot my umbrella again, which is really annoying",
            "the memory usage keeps growing, which looks like a leak in the cache layer",
            "the author, whose work I had admired, retired last year",
            "the man, whom I met yesterday, sent a follow-up note",
            "do it now", "do it yourself", "have it ready by friday", "have it your way",
            "may the force be with you", "may the best team win", "may he rest in peace",
            "may all your dreams come true", "had i known i would have come", "do this before lunch",
            "have a seat", "do your best",
        ])
    func leaves(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
    }

    @Test(
        "reads a positive tag after a subject and predicate as a question",
        arguments: [
            "the build passed is it", "you sent it did you", "the build is green is it",
            "they fixed the bug did they", "so you finished the slides have you", "she said yes did she",
        ])
    func positiveTag(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test(
        "leaves an agreement or a predicate pronoun after a statement alone",
        arguments: [
            "I finished the slides and so did you", "she failed the test and so did he",
            "the best part is it", "the answer is it", "what I need is it", "here it is",
            "that is all there is", "he is taller than I am", "you got it so did I",
        ])
    func positiveTagLeaves(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
    }

    @Test(
        "keeps a comma-led determiner \"which\" as a question opener",
        arguments: [
            "I sent it, which one do you want",
            "I have three, which is it",
            "Which version are you running",
            "i forgot my umbrella, which one do you want",
        ])
    func commaLedWhichAsks(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test(
        "keeps reported content inside an inverted question",
        arguments: [
            "did she say that", "did she say we're late", "did she really say we're late",
            "did you know we lost", "did he say she was coming", "do you think we should wait",
            "can you tell me they arrived",
        ])
    func reportedContent(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test("leaves an unrelated declarative run-on unpunctuated")
    func unrelatedRunOn() {
        #expect(!QuestionShape.asks(shapes("are you around yet i should be there")))
    }

    @Test(
        "does not read a subject pronoun or demonstrative as an address",
        arguments: [
            "that is it", "it is a good idea", "this is a really good idea for us",
            "that was a good point", "it is my two cents", "i am a hundred percent sure",
            "these are a few good reasons", "those were a few good days", "we are a hundred percent sure",
            "he is a very good doctor", "she is a very good nurse", "they are a very good team",
            "it is good", "she is a nurse", "the report is a good idea", "it is not a good idea",
            "here is the list: apples and pears", "here are the files: a and b",
            "there is a list: one two three", "here is what we need: milk and eggs", "here is the plan",
            "you are the best person for this", "everything is the way it should be",
            "nothing is the same as before", "nobody is the right person for this",
            "none are the right size for this", "someone is the next person in line",
        ])
    func declarativePronounOpeners(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes(text)) == nil)
    }

    @Test("still reads a name before an inverted question as an address")
    func namedAddressOpensQuestion() {
        #expect(QuestionShape.asks(shapes("papa are you around")))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes("papa are you around")) == 0)
    }

    @Test(
        "reads a name before a verb that can take a noun phrase as a statement",
        arguments: [
            "ravi is the owner of the account", "maria is the one who called",
            "siobhan is the lead on the ferrovia launch", "priya has the keys to the office",
            "dhruv was the one who fixed it", "papa does the dishes every night",
            "maria is the manager", "maria is my sister", "maria is happy with the results",
            "maria is the lead",
        ])
    func namedStatementBeforeNounPhrase(text: String) {
        #expect(!QuestionShape.asks(shapes(text)))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes(text)) == nil)
    }

    @Test("still reads a name before a modal and a noun phrase as an address")
    func namedAddressBeforeModal() {
        #expect(QuestionShape.asks(shapes("priya can the build go out today")))
        #expect(QuestionShape.leadingQuestionOpenerIndex(in: shapes("priya can the build go out today")) == 0)
    }

    @Test(
        "keeps dependent clauses inside an inverted question",
        arguments: [
            "is it okay if i leave at five", "is it fine if we start late", "is it okay when i call later",
        ])
    func dependentClauses(text: String) {
        #expect(QuestionShape.asks(shapes(text)))
    }

    @Test("reads Hindi question words in a subject-first clause")
    func subjectFirstHindiQuestions() {
        for text in [
            "tum kab aaoge", "tum kab milenge", "tum kyun aaye", "aaj kaun aayega",
            "tumhara naam kya hai", "yeh kya hai", "tum kya karoge", "tum kya chahte ho",
            "tum kaisa feel kar rahe ho", "tumne khana khaya kya", "chalega kya", "tum kaisi ho",
        ] {
            #expect(QuestionShape.asks(shapes(text)), "Expected a question: \(text)")
        }
    }

    @Test("leaves Hindi embedded questions as statements")
    func embeddedHindiQuestions() {
        for text in [
            "mujhe nahi pata ye kya hai", "mujhe pata nahi tum kab aaoge",
            "mujhe nahi pata ki tum kab aaoge", "maine kaha tum kab aaoge", "I don't know ye kya hai",
            "kya baat hai", "woh kya hai na yaani mujhe time chahiye",
            "mujhe nahi pata woh kahan hai", "usne bataya meeting kab hai",
            "mujhe yaad nahi kitna paisa diya",
            "main dekh raha hoon kaise hota hai", "mujhe pata hai tum kyun nahi aaye",
        ] {
            #expect(!QuestionShape.asks(shapes(text)), "Expected a statement: \(text)")
        }
    }
}

@Suite("ReviewTag")
struct ReviewTagTests {
    @Test(
        "reads a review label said first only where it heads a clause",
        arguments: [
            ("nit spelling mistake here", true), ("minor we should log it", true),
            ("question is this needed", true), ("question is that needed", false),
            ("minor changes only", false), ("question is whether we ship", false),
            ("question for you all", false), ("nit: done here", false), ("nit done", false),
            ("we have one nit", false),
        ])
    func leads(text: String, expected: Bool) {
        #expect(ReviewTag.leads(shapes(text)) == expected)
    }

    @Test("judges the clause after a colon on its own")
    func clauseAfterColon() {
        #expect(QuestionShape.asks(shapes("question: why is this async")))
        #expect(!QuestionShape.asks(shapes("note: we ship today")))
    }
}

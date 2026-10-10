import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// A written notation mark must stand for a name said for it; a mark nothing said names is invented. See Docs/adapters.md, section 4.
@Suite("Notation aligned through the spoken-command table")
struct NotationAlignmentTests {
    private func unsourced(_ spoken: String, _ written: String) -> [String] {
        NotationAlignment.align(spoken: spoken, written: written).unsourced
    }

    @Test("every notation row written as its mark, apart or joined, leaves nothing unexplained")
    func everyRowAligns() {
        for row in NotationAlignment.notationRows {
            let spoken = "alpha " + row.words.joined(separator: " ") + " beta"
            for written in ["alpha \(row.text) beta", "alpha\(row.text)beta"] {
                #expect(unsourced(spoken, written).isEmpty, "\(row.id): \(spoken) -> \(written)")
            }
        }
    }

    @Test("a spoken name kept as words, or a mark the draft already holds, is no invention")
    func keptAsSaid() {
        #expect(unsourced("x equals y", "x equals y").isEmpty)
        #expect(unsourced("x = y", "x = y").isEmpty)
        #expect(unsourced("cat log | grep error", "cat log | grep error").isEmpty)
    }

    @Test("prose punctuation is the prose checks' to judge, so a stop or comma added here is not counted")
    func prosePunctuationIsNotNotation() {
        #expect(unsourced("we shipped it then we rested", "We shipped it; then, we rested.").isEmpty)
        #expect(unsourced("a well known name", "a well-known name").isEmpty)
    }

    @Test("a notation mark with no name said for it is unexplained")
    func inventedMarks() {
        #expect(unsourced("x y", "x = y") == ["="])
        #expect(unsourced("let limit equals twelve", "let limit == 12") == ["=="])
        #expect(unsourced("cat log grep error", "cat log | grep error") == ["|"])
        #expect(unsourced("ls all", "ls --all") == ["--"])
        #expect(unsourced("if ready return", "if ready { return }") == ["{", "}"])
        #expect(unsourced("item next", "item->next") == ["->"])
    }

    @Test("a notation mark the draft holds and the rewrite leaves out is dropped; a prose mark is not judged")
    func droppedMarks() {
        let aligned = { (spoken: String, written: String) in
            NotationAlignment.align(spoken: spoken, written: written).dropped
        }
        #expect(aligned("let limit = 12", "let limit 12") == ["="])
        #expect(aligned("cat log | grep error >> out", "cat log grep error out") == ["|", ">>"])
        #expect(aligned("let limit = 12", "let limit equals 12").isEmpty)
        #expect(aligned("we shipped it; then we rested.", "we shipped it then we rested").isEmpty)
    }

    @Test("an underscore joining two said words into one identifier is no invented mark")
    func underscoreJoinsIdentifier() {
        #expect(unsourced("rename user id to account id", "rename `user_id` to `account_id`").isEmpty)
        #expect(unsourced("call get user", "call get_user") == [])
        #expect(unsourced("user id", "user _ id") == ["_"])
        #expect(unsourced("user id", "user_ id") == ["_"])
    }

    @Test("each name answers for one mark, in the order it was said")
    func oneMarkPerName() {
        #expect(unsourced("x equals y", "x = y = z") == ["="])
        #expect(unsourced("a pipe b c", "a | b | c") == ["|"])
    }

    @Test("the table is the source: a row added to it makes its name a source and its mark notation")
    func tableIsTheSource() throws {
        let row = try JSONDecoder().decode(
            SpokenCommand.self,
            from: Data(#"{"id": "test.star", "words": ["star"], "action": "codeSymbol", "text": "*"}"#.utf8))
        let rows = NotationAlignment.notationRows + [row]
        #expect(NotationAlignment.align(spoken: "x star y", written: "x * y", table: rows).unsourced.isEmpty)
        #expect(NotationAlignment.align(spoken: "x y", written: "x * y", table: rows).unsourced == ["*"])
        #expect(NotationAlignment.align(spoken: "x y", written: "x * y", table: []).unsourced.isEmpty)
    }

    @Test("each spoken name says whether the rewrite writes it, and finds its kept words in order")
    func namesFoundInOrder() {
        let spoken = "call foo open paren bar close paren then paren"
        let aligned = NotationAlignment.align(spoken: spoken, written: "call foo(bar) then")
        #expect(aligned.names.map(\.standing) == [.asMark, .asMark])
        let asSaid = NotationAlignment.align(spoken: "x equals y", written: "x equals")
        #expect(asSaid.names.map(\.standing) == [.asSaid])
        let dropped = NotationAlignment.align(spoken: "x equals y", written: "x y")
        #expect(dropped.names.map(\.standing) == [.dropped])
        let spaced = NotationAlignment.align(spoken: "the test is a period", written: "The test is a.")
        #expect(spaced.names.map(\.standing) == [.dropped], "a stop spaced as prose may be the rewrite's own")
        let joined = NotationAlignment.align(spoken: "example dot com", written: "example.com")
        #expect(joined.names.map(\.standing) == [.asMark])
        let kept = MeaningPreservationGuard.grammarTokens(spoken)
        #expect(aligned.writtenNames(in: kept) == [2, 3, 5, 6])
    }

    @Test("the guard refuses an invented notation mark and accepts one that was said")
    func guardJudgesNotation() {
        let sut = MeaningPreservationGuard()
        let verdict = { (kept: String, written: String) in
            sut.verdict(draft: Draft(text: kept), rewritten: written)
        }
        let invented = GuardVerdict.rejected(
            reason: "the rewrite added a notation mark nothing said names", kind: .inventedSymbol)
        #expect(verdict("let limit equals twelve", "let limit = 12").isAccepted)
        #expect(verdict("cat log pipe grep error", "cat log | grep error").isAccepted)
        #expect(verdict("let limit twelve", "let limit = 12") == invented)
        #expect(!verdict("cat log grep error", "cat log | grep error").isAccepted)
    }

    @Test("a name of several words written as its mark is no lost word")
    func severalWordNamesAreWritten() {
        let sut = MeaningPreservationGuard()
        for (kept, written) in [
            ("call foo open paren bar close paren", "call foo(bar)"),
            ("if ready open brace return close brace", "if ready { return }"),
            ("echo hi greater than out dot txt", "echo hi > out.txt"),
            ("ls dash dash all", "ls --all"),
            ("open bracket zero close bracket", "[0]"),
        ] {
            #expect(
                sut.verdict(draft: Draft(text: kept), rewritten: written).isAccepted, "\(kept) -> \(written)")
        }
    }

    @Test("a clause added, a word dropped or two clauses swapped is refused however the notation reads")
    func mutationsAreRefused() {
        let sut = MeaningPreservationGuard()
        let kept = "select name from users"
        for written in [
            "select name from users where id = 1", "select name from users limit 10",
            "from users select name", "select from users", "select name, email from users",
        ] {
            #expect(!sut.verdict(draft: Draft(text: kept), rewritten: written).isAccepted, "\(written)")
        }
        for written in ["call foo(bar, baz)", "call(foo bar)", "call foo[bar]", "bar(foo)"] {
            let draft = Draft(text: "call foo open paren bar close paren")
            #expect(!sut.verdict(draft: draft, rewritten: written).isAccepted, "\(written)")
        }
    }

    @Test("a percent said without a row stands as its mark only where the mark touches a word")
    func percentByName() {
        let standing = { (spoken: String, written: String) in
            NotationAlignment.align(spoken: spoken, written: written).names.map(\.standing)
        }
        #expect(standing("user percent s logged in", "user %s logged in") == [.asMark])
        #expect(standing("user percent s logged in", "user % s logged in") == [.dropped])
    }
}

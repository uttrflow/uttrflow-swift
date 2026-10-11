import Foundation
import Testing

@testable import UttrflowPredict

private let repeatedJoinExamples = [
    ("we went to THE", "we went to THE the store"),
    ("we went to THE ", "we went to THE the store"),
]

private func repeatedJoinQuery(
    _ session: inout SuggestionSession, typing typed: String
) throws -> SuggestionQuery {
    let turn = session.turn(in: terminal, at: PredictionContext(typed: typed))
    guard case .query(let query) = turn.step else {
        Issue.record("expected a query")
        throw CancellationError()
    }
    return query
}

@Suite("Repeated words at the suggestion join")
struct SuggestionRepeatedJoinTests {
    @Test("A remembered candidate does not repeat the last typed word at the join.", .bug(id: 5335))
    func rememberedCandidateWithRepeatedJoinWordIsNotVerified() throws {
        for (typed, candidate) in repeatedJoinExamples {
            var session = SuggestionSession()
            let query = try repeatedJoinQuery(&session, typing: typed)
            let result = session.resolve(
                [remembered(candidate, count: 40)], for: query,
                now: moment, elapsedMilliseconds: 0)
            guard case .settled(let update) = result else {
                Issue.record("the repeated candidate should not reach verification")
                continue
            }
            #expect(update.suggestion == .silent)
        }
    }

    @Test("A generated continuation does not repeat its last typed word.", .bug(id: 5335))
    func repeatedJoinWordIsNotDrawable() throws {
        for (typed, candidate) in repeatedJoinExamples {
            var session = SuggestionSession()
            let query = try repeatedJoinQuery(&session, typing: typed)
            let update = session.resolveSure(
                [candidate], for: query, elapsedMilliseconds: 0)
            #expect(update?.suggestion == .silent)
        }
    }

    @Test("A first word that only shares letters with the last typed word is drawn.", .bug(id: 5335))
    func continuationThatDoesNotRepeatIsDrawable() throws {
        for (typed, candidate) in [("m", "m -m 'fix'"), ("the", "theme park")] {
            var session = SuggestionSession()
            let query = try repeatedJoinQuery(&session, typing: typed)
            let update = session.resolveSure([candidate], for: query, elapsedMilliseconds: 0)
            #expect(update?.suggestion == .certain(candidate))
        }
    }
}

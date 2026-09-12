// Tests for FallbackRunner.

import Synchronization
import Testing

@testable import UttrflowCore

/// An error naming the candidate that threw it.
private struct StubError: Error, Equatable {
    let candidate: Int
}

@Suite("FallbackRunner")
struct FallbackRunnerTests {
    @Test("returns the first candidate that succeeds and stops there")
    func stopsAtFirstSuccess() async {
        let attempted = Mutex<[Int]>([])

        let outcome = await FallbackRunner.firstSuccess(among: [1, 2, 3]) { candidate in
            attempted.withLock { $0.append(candidate) }
            guard candidate >= 2 else { throw StubError(candidate: candidate) }
            return "candidate \(candidate)"
        }

        #expect(outcome.successValue == "candidate 2")
        #expect(attempted.withLock { $0 } == [1, 2], "must not try candidates after a success")
    }

    @Test("tries candidates in the order given")
    func preservesOrder() async {
        let attempted = Mutex<[Int]>([])

        _ = await FallbackRunner.firstSuccess(among: [3, 1, 2]) { candidate -> String in
            attempted.withLock { $0.append(candidate) }
            throw StubError(candidate: candidate)
        }

        #expect(attempted.withLock { $0 } == [3, 1, 2])
    }

    @Test("collects one error per candidate when all of them fail")
    func exhaustsAndReportsEveryError() async {
        let outcome = await FallbackRunner.firstSuccess(among: [1, 2]) { candidate -> String in
            throw StubError(candidate: candidate)
        }

        let errors = outcome.exhaustedErrors
        #expect(errors?.count == 2)
        #expect(
            errors?.compactMap { $0 as? StubError } == [StubError(candidate: 1), StubError(candidate: 2)])
    }

    @Test("is exhausted with no errors when there is nothing to try")
    func emptyCandidateList() async {
        let outcome = await FallbackRunner.firstSuccess(among: [Int]()) { _ -> String in
            Issue.record("must not run an attempt with no candidates")
            return ""
        }

        #expect(outcome.successValue == nil)
        #expect(outcome.exhaustedErrors?.isEmpty == true)
    }

    @Test("succeeds on the very first candidate without trying any other")
    func immediateSuccess() async {
        let attemptCount = Mutex(0)

        let outcome = await FallbackRunner.firstSuccess(among: ["a", "b"]) { candidate in
            attemptCount.withLock { $0 += 1 }
            return candidate.uppercased()
        }

        #expect(outcome.successValue == "A")
        #expect(attemptCount.withLock { $0 } == 1)
    }
}

/// Small readers so assertions stay legible; the product switches over an outcome exhaustively instead.
extension FallbackOutcome {
    fileprivate var successValue: Success? {
        if case .succeeded(let value, _) = self { value } else { nil }
    }

    fileprivate var failuresBeforeSuccess: [any Error]? {
        if case .succeeded(_, let errors) = self { errors } else { nil }
    }

    fileprivate var exhaustedErrors: [any Error]? {
        if case .exhausted(let errors) = self { errors } else { nil }
    }
}

/// Why the winner won is half the story; a fallback that hides the refusals hides the reason. See #193.
@Suite("What a fallback leaves behind")
struct FallbackFailuresTests {
    @Test("the outcome names what failed before the candidate that worked")
    func carriesEarlierFailures() async {
        struct Refused: Error, Equatable { let which: Int }

        let outcome = await FallbackRunner.firstSuccess(among: [1, 2, 3]) { candidate -> String in
            guard candidate == 3 else { throw Refused(which: candidate) }
            return "third"
        }

        #expect(outcome.successValue == "third")
        let refused = outcome.failuresBeforeSuccess?.compactMap { $0 as? Refused }
        #expect(refused == [Refused(which: 1), Refused(which: 2)])
    }

    @Test("a candidate that works first leaves nothing behind")
    func carriesNothingWhenTheFirstWorks() async {
        let outcome = await FallbackRunner.firstSuccess(among: [1, 2]) { _ -> String in "first" }

        #expect(outcome.failuresBeforeSuccess?.isEmpty == true)
    }
}

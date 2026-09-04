import Foundation
import Testing

@testable import UttrflowPredictCapture

private let start = Date(timeIntervalSince1970: 1_800_000_000)

/// Types one character at a time, which is the only way a real field is ever filled.
private func typing(
    _ text: String, into detector: inout CommitDetector, from moment: Date = start
)
    -> [Commit]
{
    var commits: [Commit] = []
    for (index, _) in text.enumerated() {
        let soFar = String(text.prefix(index + 1))
        let at = moment.addingTimeInterval(Double(index) / 10)
        if let commit = detector.receive(.keystroke(soFar, at: at)) { commits.append(commit) }
    }
    return commits
}

@Suite("Noticing when a value is finished")
struct CommitDetectorTests {
    @Test("Typing on its own never commits anything, however many keys are pressed.")
    func keystrokesAloneCommitNothing() {
        var detector = CommitDetector()
        #expect(typing("git commit -m", into: &detector).isEmpty)
    }

    @Test("Return is the user saying the value is finished.")
    func returnCommits() {
        var detector = CommitDetector()
        _ = typing("git status", into: &detector)
        let commit = detector.receive(.returnPressed(at: start))
        #expect(commit == Commit(text: "git status", reason: .returnPressed))
    }

    @Test("Leaving the field commits what it holds, so a value typed and abandoned is not lost.")
    func focusLeavingCommits() {
        var detector = CommitDetector()
        _ = typing("someone@example.com", into: &detector)
        #expect(detector.receive(.focusLeft(at: start))?.reason == .focusLeft)
    }

    @Test("The application going to the background commits what is in the field.")
    func deactivationCommits() {
        var detector = CommitDetector()
        _ = typing("make verify", into: &detector)
        #expect(detector.receive(.applicationDeactivated(at: start))?.reason == .applicationDeactivated)
    }

    @Test("Three seconds untouched counts as finished, and two seconds does not.")
    func idlenessCommits() {
        var detector = CommitDetector()
        _ = typing("git push", into: &detector)
        let last = start.addingTimeInterval(0.7)
        #expect(detector.receive(.tick(at: last.addingTimeInterval(2))) == nil)
        let commit = detector.receive(.tick(at: last.addingTimeInterval(CommitDetector.idleInterval)))
        #expect(commit == Commit(text: "git push", reason: .wentIdle))
    }

    @Test("A tick before anything has been typed commits nothing.")
    func idleEmptyFieldCommitsNothing() {
        var detector = CommitDetector()
        #expect(detector.receive(.tick(at: start.addingTimeInterval(600))) == nil)
    }

    @Test("A half-typed single token is not learned from an idle, so `gi` and `git` are never stored.")
    func idleDoesNotCommitAFragment() {
        var detector = CommitDetector()
        _ = typing("git", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(600))) == nil)
    }

    @Test("A single token abandoned by Return is still committed, because ending it is explicit.")
    func returnCommitsASingleToken() {
        var detector = CommitDetector()
        _ = typing("git", into: &detector)
        #expect(detector.receive(.returnPressed(at: start.addingTimeInterval(1)))?.text == "git")
    }

    @Test("A single token abandoned by leaving the field is still committed.")
    func focusLeavingCommitsASingleToken() {
        var detector = CommitDetector()
        _ = typing("gif", into: &detector)
        #expect(detector.receive(.focusLeft(at: start.addingTimeInterval(1)))?.text == "gif")
    }

    @Test("A finished, multi-token line is learned from an idle, because it looks like a whole value.")
    func idleCommitsACompleteLine() {
        var detector = CommitDetector()
        _ = typing("git status", into: &detector)
        let commit = detector.receive(.tick(at: start.addingTimeInterval(600)))
        #expect(commit?.text == "git status")
    }

    @Test("An empty field commits nothing whatever ends it.")
    func emptyFieldCommitsNothing() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("   ", at: start))
        #expect(detector.receive(.returnPressed(at: start)) == nil)
        #expect(detector.receive(.focusLeft(at: start)) == nil)
    }

    @Test("Going idle twice over the same value commits it once.")
    func idlenessDoesNotRepeat() {
        var detector = CommitDetector()
        _ = typing("git push", into: &detector)
        let idle = start.addingTimeInterval(60)
        #expect(detector.receive(.tick(at: idle)) != nil)
        #expect(detector.receive(.tick(at: idle.addingTimeInterval(60))) == nil)
    }

    @Test("Return after an idle commit of the same value does not record it a second time.")
    func returnAfterIdleIsNotASecondRecord() {
        var detector = CommitDetector()
        _ = typing("git push", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60))) != nil)
        #expect(detector.receive(.returnPressed(at: start.addingTimeInterval(61))) == nil)
    }

    @Test("Carrying on typing after an idle commit replaces the half-written value rather than adding to it.")
    func continuingSupersedesThePrefix() {
        var detector = CommitDetector()
        _ = typing("git pu", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60)))?.text == "git pu")
        _ = detector.receive(.keystroke("git push --force", at: start.addingTimeInterval(61)))
        let commit = detector.receive(.returnPressed(at: start.addingTimeInterval(62)))
        #expect(commit == Commit(text: "git push --force", supersedes: "git pu", reason: .returnPressed))
    }

    @Test("Replacing an idle draft with something else entirely still retires the draft when the line is finished.")
    func retypingSupersedesTheIdleDraft() {
        var detector = CommitDetector()
        _ = typing("git pu", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60))) != nil)
        _ = detector.receive(.keystroke("make", at: start.addingTimeInterval(61)))
        let commit = detector.receive(.returnPressed(at: start.addingTimeInterval(62)))
        #expect(commit == Commit(text: "make", supersedes: "git pu", reason: .returnPressed))
    }

    @Test("Backspacing over an idle draft and retyping past it retires the draft rather than leaving it standing.")
    func backspacingAndRetypingSupersedesTheIdleDraft() {
        var detector = CommitDetector()
        _ = typing("git pu", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60)))?.text == "git pu")
        _ = detector.receive(.keystroke("git p", at: start.addingTimeInterval(61)))
        _ = detector.receive(.keystroke("git pull", at: start.addingTimeInterval(62)))
        let commit = detector.receive(.focusLeft(at: start.addingTimeInterval(63)))
        #expect(commit == Commit(text: "git pull", supersedes: "git pu", reason: .focusLeft))
    }

    @Test("Return starts the field afresh, so the next command supersedes nothing.")
    func returnStartsAgain() {
        var detector = CommitDetector()
        _ = typing("git", into: &detector)
        #expect(detector.receive(.returnPressed(at: start)) != nil)
        _ = detector.receive(.keystroke("git status", at: start.addingTimeInterval(1)))
        let second = detector.receive(.returnPressed(at: start.addingTimeInterval(2)))
        #expect(second == Commit(text: "git status", supersedes: nil, reason: .returnPressed))
    }

    @Test("Surrounding space is not part of the value.")
    func valuesAreTrimmed() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("  make verify  ", at: start))
        #expect(detector.receive(.returnPressed(at: start))?.text == "make verify")
    }

    @Test("Resetting forgets the field, which is what focusing another one amounts to.")
    func resetForgets() {
        var detector = CommitDetector()
        _ = typing("git push", into: &detector)
        detector.reset()
        #expect(detector.receive(.returnPressed(at: start)) == nil)
        #expect(detector == CommitDetector())
    }

    @Test("Every event carries the moment it happened, which is the only clock there is.")
    func eventsCarryTheirMoment() {
        let events: [CaptureEvent] = [
            .keystroke("a", at: start), .returnPressed(at: start), .focusLeft(at: start),
            .applicationDeactivated(at: start), .tick(at: start),
        ]
        #expect(events.allSatisfy { $0.moment == start })
    }
}

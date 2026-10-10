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

    @Test("A pause as long as the idle interval counts as finished, and a shorter one does not.")
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

    @Test("An empty line after an idle commit retires that line.")
    func emptyLineRetiresIdleCommit() {
        var detector = CommitDetector()
        _ = typing("git status", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60)))?.text == "git status")
        _ = detector.receive(.keystroke("", at: start.addingTimeInterval(61)))

        #expect(
            detector.receive(
                .tick(at: start.addingTimeInterval(61 + CommitDetector.idleInterval))
            ) == Commit(text: "", supersedes: "git status", reason: .wentIdle))
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

    @Test("An accepted extension followed by typing retires the idle draft it extended.")
    func acceptedExtensionFollowedByTypingSupersedesIdleDraft() {
        var detector = CommitDetector()
        _ = typing("foo bar", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60)))?.text == "foo bar")

        #expect(detector.accepted("foo bar baz") == "foo bar")
        _ = detector.receive(.keystroke("foo bar baz!", at: start.addingTimeInterval(61)))

        #expect(
            detector.receive(.returnPressed(at: start.addingTimeInterval(62)))
                == Commit(text: "foo bar baz!", supersedes: "foo bar baz", reason: .returnPressed))
    }

    @Test("An idle the caller will not admit is not remembered, so Return still commits the same value.")
    func refusedIdleLeavesReturnFree() {
        var detector = CommitDetector()
        _ = typing("git status", into: &detector)
        let pause = start.addingTimeInterval(9)
        #expect(detector.receive(.tick(at: pause)) { $0 != .wentIdle } == nil)
        #expect(detector.receive(.tick(at: pause.addingTimeInterval(9))) { $0 != .wentIdle } == nil)
        let commit = detector.receive(.returnPressed(at: pause.addingTimeInterval(10))) { $0 != .wentIdle }
        #expect(commit == Commit(text: "git status", reason: .returnPressed))
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

    @Test(
        "Replacing an idle draft with something else entirely still retires the draft when the line is finished."
    )
    func retypingSupersedesTheIdleDraft() {
        var detector = CommitDetector()
        _ = typing("git pu", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60))) != nil)
        _ = detector.receive(.keystroke("make", at: start.addingTimeInterval(61)))
        let commit = detector.receive(.returnPressed(at: start.addingTimeInterval(62)))
        #expect(commit == Commit(text: "make", supersedes: "git pu", reason: .returnPressed))
    }

    @Test(
        "Backspacing over an idle draft and retyping past it retires the draft rather than leaving it standing."
    )
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

    @Test("Forgetting the last idle commit lets the next eligible tick re-emit the same value.")
    func forgottenIdleCommitIsReEmitted() {
        var detector = CommitDetector()
        _ = typing("git push", into: &detector)
        let first = detector.receive(.tick(at: start.addingTimeInterval(60)))
        #expect(first?.text == "git push")
        #expect(detector.receive(.tick(at: start.addingTimeInterval(120))) == nil)
        detector.forgetLastIdleCommit()
        let second = detector.receive(.tick(at: start.addingTimeInterval(180)))
        #expect(second?.text == "git push")
        #expect(detector.receive(.tick(at: start.addingTimeInterval(240))) == nil)
    }

    @Test("Forgetting the last idle commit keeps the prior supersession, so the next tick still retires it.")
    func forgottenIdleCommitKeepsSupersession() {
        var detector = CommitDetector()
        _ = typing("git pu", into: &detector)
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60)))?.text == "git pu")
        _ = detector.receive(.keystroke("git push", at: start.addingTimeInterval(61)))
        #expect(
            detector.receive(.tick(at: start.addingTimeInterval(120)))?.supersedes == "git pu")
        detector.forgetLastIdleCommit()
        let retry = detector.receive(.tick(at: start.addingTimeInterval(180)))
        #expect(retry?.text == "git push")
        #expect(retry?.supersedes == "git pu")
    }

    @Test("Forgetting an idle commit when nothing has been committed is a no-op.")
    func forgetLastIdleCommitWithoutACommitIsANoOp() {
        var detector = CommitDetector()
        detector.forgetLastIdleCommit()
        #expect(detector == CommitDetector())
    }

    @Test("A line that took a paste or a dictation is not learned, however it ends.")
    func insertedTextIsNotLearned() {
        for ending in [
            CaptureEvent.returnPressed(at: start), .focusLeft(at: start), .applicationDeactivated(at: start),
        ] {
            var detector = CommitDetector()
            _ = typing("see ", into: &detector)
            #expect(detector.receive(.inserted(at: start)) == nil)
            #expect(detector.receive(.keystroke("see can we move the review to thursday?", at: start)) == nil)
            #expect(detector.receive(ending) == nil, "\(ending)")
        }
    }

    @Test("A host-app rewrite that differs from delivered typing is not learned.")
    func appMutatedTextIsNotLearned() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("", at: start))
        _ = detector.receive(.typed("teh ", at: start.addingTimeInterval(1)))
        _ = detector.receive(.keystroke("the ", at: start.addingTimeInterval(2)))
        _ = detector.receive(.typed("meeting", at: start.addingTimeInterval(3)))
        _ = detector.receive(.keystroke("the meeting", at: start.addingTimeInterval(4)))
        #expect(detector.receive(.returnPressed(at: start.addingTimeInterval(5))) == nil)
    }

    @Test("Text matching delivered typing remains eligible for learning.")
    func unmodifiedTypingIsLearned() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("", at: start))
        _ = detector.receive(.typed("team ", at: start.addingTimeInterval(1)))
        _ = detector.receive(.keystroke("team ", at: start.addingTimeInterval(2)))
        _ = detector.receive(.typed("lunch", at: start.addingTimeInterval(3)))
        _ = detector.receive(.keystroke("team lunch", at: start.addingTimeInterval(4)))
        #expect(detector.receive(.returnPressed(at: start.addingTimeInterval(5)))?.text == "team lunch")
    }

    @Test("An idle does not learn a line that took inserted text either.")
    func insertedTextIsNotLearnedFromAnIdle() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("https://example.com/a/long/link", at: start))
        _ = detector.receive(.inserted(at: start))
        #expect(detector.receive(.tick(at: start.addingTimeInterval(60))) == nil)
    }

    @Test("A line emptied by hand, or a field begun afresh, is learned again.")
    func typingAfreshIsLearnedAgain() {
        var detector = CommitDetector()
        _ = detector.receive(.inserted(at: start))
        _ = detector.receive(.keystroke("", at: start))
        _ = typing("on my way", into: &detector)
        #expect(detector.receive(.returnPressed(at: start))?.text == "on my way")
        _ = detector.receive(.inserted(at: start))
        _ = detector.receive(.keystroke("pasted words", at: start))
        #expect(detector.receive(.returnPressed(at: start)) == nil)
        _ = typing("typed words", into: &detector)
        #expect(detector.receive(.returnPressed(at: start))?.text == "typed words")
    }

    @Test("An insertion is marked after the line a turn read and before anything that ends the field.")
    func anInsertionIsMarkedBeforeTheEnding() {
        let read = CaptureEvent.keystroke("line", at: start)
        let sent = CaptureEvent.returnPressed(at: start)
        let mark = CaptureEvent.inserted(at: start)
        #expect(CaptureEvent.marking([read], insertedAt: start) == [read, mark])
        #expect(CaptureEvent.marking([read, sent], insertedAt: start) == [read, mark, sent])
        #expect(CaptureEvent.marking([sent], insertedAt: start) == [mark, sent])
    }

    /// A dictation of `inserted` after `typed`, then a read of the line as `edited` after `typedAfter`, then Return.
    private func editing(
        _ typed: String, inserted: String, edited: String, typedAfter: String?, at moment: Date = start
    ) -> (Commit?, EditedSpan?) {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke(typed, at: moment))
        _ = detector.receive(.keystroke(typed + inserted, at: moment))
        _ = detector.receive(.inserted(at: moment))
        _ = detector.receive(.typed(typedAfter, at: moment.addingTimeInterval(1)))
        _ = detector.receive(.keystroke(edited, at: moment.addingTimeInterval(1)))
        let commit = detector.receive(.returnPressed(at: moment.addingTimeInterval(2)))
        return (commit, detector.takeEditedSpan())
    }

    @Test("A one-word replacement inside dictated text is one edit, and the line is still not learned.")
    func aOneWordReplacementIsOneEdit() {
        let (commit, edit) = editing(
            "see ", inserted: "you on tuesday at noon", edited: "see you on thursday at noon",
            typedAfter: "thursday")
        #expect(commit == nil)
        #expect(edit == EditedSpan(position: 2, old: ["tuesday"], new: ["thursday"]))
    }

    @Test("An edit is handed over once.")
    func anEditIsTakenOnce() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("", at: start))
        _ = detector.receive(.keystroke("meet at noon", at: start))
        _ = detector.receive(.inserted(at: start))
        _ = detector.receive(.typed("ten", at: start))
        _ = detector.receive(.keystroke("meet at ten", at: start))
        _ = detector.receive(.focusLeft(at: start))
        #expect(detector.takeEditedSpan() == EditedSpan(position: 2, old: ["noon"], new: ["ten"]))
        #expect(detector.takeEditedSpan() == nil)
    }

    @Test("A host-app rewrite of dictated text is no edit of the person's.")
    func aProgrammaticRewriteIsNoEdit() {
        let (_, edit) = editing(
            "", inserted: "see you on tuesday", edited: "see you on Tuesday.", typedAfter: nil)
        #expect(edit == nil)
        let (_, unkeyed) = editing(
            "", inserted: "see you on tuesday", edited: "see you on thursday", typedAfter: "x")
        #expect(unkeyed == nil)
    }

    @Test("A read with no key behind it that changes the line leaves no edit.")
    func anUnkeyedChangeIsNoEdit() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("", at: start))
        _ = detector.receive(.keystroke("see you on tuesday", at: start))
        _ = detector.receive(.inserted(at: start))
        _ = detector.receive(.keystroke("see you on thursday", at: start))
        _ = detector.receive(.returnPressed(at: start))
        #expect(detector.takeEditedSpan() == nil)
    }

    @Test("Edits outside the inserted words, too long, too late or absent leave no edit.")
    func boundedEditsOnly() {
        let (_, outside) = editing(
            "hello there ", inserted: "see you soon", edited: "hi there see you soon", typedAfter: "i")
        #expect(outside == nil)
        let (_, long) = editing(
            "", inserted: "one two three four five", edited: "a b c d e", typedAfter: "a b c d e")
        #expect(long == nil)
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("", at: start))
        _ = detector.receive(.keystroke("meet at noon", at: start))
        _ = detector.receive(.inserted(at: start))
        let late = start.addingTimeInterval(CommitDetector.spanEditWindow + 1)
        _ = detector.receive(.typed("ten", at: late))
        _ = detector.receive(.keystroke("meet at ten", at: late))
        _ = detector.receive(.returnPressed(at: late))
        #expect(detector.takeEditedSpan() == nil)
        let (_, unchanged) = editing("", inserted: "meet at noon", edited: "meet at noon", typedAfter: nil)
        #expect(unchanged == nil)
    }

    @Test("Deleting a dictated word with keys is an edit with nothing new.")
    func aDeletionIsAnEdit() {
        let (_, edit) = editing(
            "", inserted: "see you on um tuesday", edited: "see you on tuesday", typedAfter: nil)
        #expect(edit == EditedSpan(position: 3, old: ["um"], new: []))
    }
}

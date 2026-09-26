import Foundation
import Testing

@testable import UttrflowPredictCapture

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("A Return that displaced the last keystroke turn")
struct ReturnCatchUpTests {
    /// Hands the detector every event and keeps what commits.
    private func commits(_ events: [CaptureEvent], into detector: inout CommitDetector) -> [Commit] {
        events.compactMap { detector.receive($0) }
    }

    @Test("A keystroke queued behind a busy turn and then displaced by Return still reaches the commit.")
    func displacedKeystrokeIsCommitted() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("git sta", at: start))
        let events = ReturnCatchUp.events(
            read: "git status", handed: "git sta", at: start.addingTimeInterval(1))
        #expect(commits(events, into: &detector) == [Commit(text: "git status", reason: .returnPressed)])
    }

    @Test("A line that is not the handed one grown is left out, so a cleared prompt commits what was sent.")
    func clearedLineIsNotHanded() {
        var detector = CommitDetector()
        _ = detector.receive(.keystroke("git status", at: start))
        let events = ReturnCatchUp.events(read: "", handed: "git status", at: start)
        #expect(events == [.returnPressed(at: start)])
        #expect(commits(events, into: &detector) == [Commit(text: "git status", reason: .returnPressed)])
    }

    @Test("A line already handed is not handed again.")
    func unchangedLineIsReturnAlone() {
        #expect(
            ReturnCatchUp.events(read: "ls -la ", handed: "ls -la", at: start) == [.returnPressed(at: start)])
    }

    @Test("A line typed entirely during one busy turn is handed from nothing.")
    func lineFromNothingIsHanded() {
        #expect(
            ReturnCatchUp.events(read: "make verify", handed: "", at: start)
                == [.keystroke("make verify", at: start), .returnPressed(at: start)])
    }
}

import Testing
import UttrflowCore

@testable import UttrflowPipeline

@Suite("The wait after key release names its stage once it runs long")
struct WaitLineTests {
    static let waits: [DictationState] = [.transcribing, .tidying, .inserting(into: "Notes")]

    @Test("below the threshold every stage draws the one shared line", arguments: waits)
    func shortWaitIsUnchanged(state: DictationState) {
        let short = DictationPresenter.dock(for: state, waited: WaitLine.stageAfter - .milliseconds(1))

        #expect(short == DictationPresenter.dock(for: .tidying))
        #expect(short.primaryLine == "Tidying up…")
        #expect(WaitLine.announcement(for: state, waited: .seconds(1), alreadyAnnounced: false) == nil)
    }

    @Test("above the threshold each stage has its own line")
    func longWaitNamesTheStage() {
        let lines = Self.waits.map {
            DictationPresenter.dock(for: $0, waited: WaitLine.stageAfter).primaryLine
        }

        #expect(lines == ["Transcribing…", "Tidying…", "Waiting for Notes…"])
        #expect(
            DictationPresenter.dock(for: .inserting(into: nil), waited: WaitLine.stageAfter).primaryLine
                == "Waiting for the app…")
    }

    @Test("the seconds waited appear only past the second threshold, on the same animation")
    func secondsAfterSecondThreshold() {
        let before = DictationPresenter.dock(for: .transcribing, waited: WaitLine.stageAfter)
        let after = DictationPresenter.dock(for: .transcribing, waited: .seconds(83))

        #expect(before.secondaryLine == nil)
        #expect(after.secondaryLine == "1:23")
        #expect(after.showsProgress && after.symbolName == before.symbolName)
    }

    @Test("nothing in the wait claims completion; only inserted draws the tick", arguments: waits)
    func noTickWhileWaiting(state: DictationState) {
        let dock = DictationPresenter.dock(for: state, waited: .seconds(200))

        #expect(dock.showsProgress)
        #expect(dock.symbolName != "checkmark")
        let landed = DictationOutcome(text: "hi", method: .pasteboard, cleanedBy: .rules)
        #expect(DictationPresenter.dock(for: .inserted(landed)).symbolName == "checkmark")
    }

    @Test("VoiceOver hears the stage once, not a stream")
    func announcedOnce() {
        let first = WaitLine.announcement(for: .tidying, waited: .seconds(12), alreadyAnnounced: false)
        let again = WaitLine.announcement(for: .tidying, waited: .seconds(13), alreadyAnnounced: true)

        #expect(first?.text == "Tidying.")
        #expect(again == nil)
    }
}

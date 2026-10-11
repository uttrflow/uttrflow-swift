// Tests the words the dock shows and speaks for every state the presenter can put it in.

import Foundation
import UttrflowCore
import UttrflowPipeline
import Testing

@testable import Uttrflow

@Suite("The dock's wording")
struct DockWordingTests {
    private static let states: [DictationState] = [
        .idle, .recording, .tidying, .failed(DictationFailure(CocoaError(.fileNoSuchFile))),
    ]

    @Test("a state that shows neither the listening nor the working form speaks no value")
    func quietStateSpeaksNothing() {
        #expect(DockWording.spokenValue(for: DictationPresenter.dock(for: .idle)).isEmpty)
    }

    @Test("every state has a hint that starts or stops listening")
    func everyStateHasAHint() {
        for state in Self.states {
            let hint = DockWording.spokenHint(for: DictationPresenter.dock(for: state))
            #expect(hint.hasPrefix(state == .recording ? "Stops listening." : "Starts a dictation."))
        }
    }

    @Test("the hover text joins the line and its detail on two lines")
    func hoverTextJoins() {
        let failed = DictationPresenter.dock(for: .failed(DictationFailure(CocoaError(.fileNoSuchFile))))
        let text = DockWording.hoverText(for: failed, primaryLine: "Line")
        #expect(text.hasPrefix("Line"))
        #expect(text.contains("\n") == (failed.secondaryLine != nil))
    }

    @Test("the blocked notice names the way out")
    func blockedLineNamesPaste() {
        #expect(DockWording.blockedLine == "Typing is blocked — paste it")
    }
}

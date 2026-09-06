// Tests for whether Return will place a clip or only copy it.
import Foundation
import Testing

@testable import UttrflowUX

/// The rule lives in `UttrflowUX` because it is a decision, and coverage cannot see `AppDelegate`.
@Suite("What Return will do")
struct PanelInsertionDecisionTests {
    @Test("with permission and another application in front, the clip goes to the caret")
    func theOrdinaryCase() {
        #expect(
            PanelInsertion.decided(isAccessibilityGranted: true, isSelfFrontmost: false)
                == .atCaret)
    }

    /// Both engines that place text need it, so without it there is nothing to try.
    @Test("without Accessibility, nothing can be typed anywhere")
    func withoutPermission() {
        #expect(
            PanelInsertion.decided(isAccessibilityGranted: false, isSelfFrontmost: false)
                == .clipboardOnly(.accessibilityNotGranted))
        // The permission is the one the user can act on, so it wins even when Uttrflow is also in front.
        #expect(
            PanelInsertion.decided(isAccessibilityGranted: false, isSelfFrontmost: true)
                == .clipboardOnly(.accessibilityNotGranted))
    }

    /// The paste engine refuses outright here, because ⌘V would land in our own window.
    @Test("with Uttrflow itself in front, there is no other caret to paste into")
    func whenUttrflowIsInFront() {
        #expect(
            PanelInsertion.decided(isAccessibilityGranted: true, isSelfFrontmost: true)
                == .clipboardOnly(.uttrflowInFront))
    }

    /// Two facts decide it and neither is about focus; see Docs/ux-panel-insertion.md.
    @Test("nothing but permission and who is in front decides it")
    func onlyTwoQuestions() {
        var seen: [PanelInsertion] = []
        for granted in [true, false] {
            for frontmost in [true, false] {
                seen.append(
                    PanelInsertion.decided(
                        isAccessibilityGranted: granted, isSelfFrontmost: frontmost))
            }
        }

        #expect(seen.filter { $0 == .atCaret }.count == 1, "exactly one combination inserts")
        #expect(
            !seen.contains(.clipboardOnly(.nothingFocused)),
            """
            Focus is the Accessibility engine's question and the coordinator falls through \
            to a paste that does not ask it. A panel that refuses on this promises less \
            than the engine behind it can do, and the user is told to press ⌘V for an \
            application that would have taken the paste.
            """)
    }
}

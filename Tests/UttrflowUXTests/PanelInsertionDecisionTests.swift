import Foundation
import Testing

@testable import UttrflowUX

/// Whether Return will place a clip or only copy it.
///
/// The rule lives in `UttrflowUX` because it is a decision, and because the file it used
/// to live in — `AppDelegate` — is the one place the coverage floor cannot see. That is
/// not an incidental detail: the rule was wrong there for as long as it existed, and
/// nothing could have caught it.
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
        // And it is the answer even when Uttrflow is also in front: the permission is the
        // one the user can act on, and naming the other obstacle would send them to click
        // somewhere instead of to System Settings.
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

    /// The bug this rule was extracted to fix, stated as the property that was violated.
    ///
    /// The old rule also asked whether anything was focused — the Accessibility engine's
    /// precondition, not the paste engine's. Editors that expose no focused element take a
    /// ⌘V perfectly well, and the same precondition had already been removed from the
    /// engine once for exactly that reason. Here it meant the panel announced "Copied —
    /// press ⌘V" and never called the engine that would have pasted.
    ///
    /// Written as an enumeration of the whole input space so that a third question added
    /// later has to be justified against this: two facts decide it, and neither of them is
    /// about focus.
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

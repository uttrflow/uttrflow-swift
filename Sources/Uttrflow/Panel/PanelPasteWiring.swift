import AppKit
import UttrflowCore
import UttrflowInput
import UttrflowUX
import SwiftUI

extension QuickPanelController {
    /// Who holds the caret now the panel has gone, asked once it is off screen. See `Docs/app-quick-panel.md`.
    func caret(
        after captured: InsertionDestination, focus: any AccessibilityFocus
    ) -> InsertionDestination {
        let front = NSWorkspace.shared.frontmostApplication
        return PanelCaret.destination(
            captured: captured,
            frontmost: front.map {
                InsertionDestination(
                    applicationName: $0.localizedName, bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier)
            },
            focused: focus.focusedApplication(),
            ownProcess: ProcessInfo.processInfo.processIdentifier)
    }
}

extension DockPanelController {
    /// Brings the button out for a report, even turned off, or a sighted person would never see it.
    func showForReport(at anchor: DockAnchor) {
        setAnchor(anchor)
        show()
    }
}

extension PanelPasteReport {
    /// How the floating button draws this report.
    var dock: DockPresentation {
        DictationPresenter.dock(
            notice: symbolName, primaryLine: primaryLine, secondaryLine: secondaryLine,
            accessibilityLabel: spoken)
    }

    /// Tells VoiceOver at high priority, since the panel that would have said it has gone.
    func announce() {
        var words = AttributedString(spoken)
        words.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(words).post()
    }
}

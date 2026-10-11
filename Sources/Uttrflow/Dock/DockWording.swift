// The words the dock says and speaks, kept out of the view so each case can be tested.

import Foundation
import UttrflowCore
import UttrflowPipeline
import UttrflowUX

/// What the floating button says, speaks and titles its actions, decided from the presentation alone.
enum DockWording {
    /// What the button is doing, in the value slot where a screen reader expects state rather than a name.
    static func spokenValue(for presentation: DockPresentation) -> String {
        if presentation.isRecording { return "Listening" }
        if presentation.showsProgress { return "Working" }
        return ""
    }

    /// What activating the button does, naming the recovery a failure offers so it is not only in the rotor.
    static func spokenHint(for presentation: DockPresentation) -> String {
        let toggle = presentation.isRecording ? "Stops listening." : "Starts a dictation."
        guard let action = presentation.action else { return toggle }
        return "\(toggle) \(title(for: action, in: presentation)) is available as an action."
    }

    /// The countdown when the presenter has one, otherwise the elapsed time as "0:04".
    static func clockText(for presentation: DockPresentation, startedAt: Date?, now: Date) -> String {
        if let remaining = presentation.secondaryLine { return remaining }
        let seconds = startedAt.map { now.timeIntervalSince($0) } ?? 0
        return DictationPresenter.elapsed(.seconds(max(seconds, 0)))
    }

    /// The one line a failure with a short name shows in place of its sentence, or `nil` for the wide form.
    static func pillLine(for presentation: DockPresentation) -> String? {
        presentation.action == .openSystemSettings(.microphone) ? "Microphone is off" : nil
    }

    /// The words a quiet outcome shows without the pointer over it, or `nil` for a form that shows none.
    static func restingWords(for presentation: DockPresentation) -> String? {
        switch presentation.symbolName {
        case "waveform.slash": presentation.primaryLine
        case "doc.on.clipboard": "Copied, not typed"
        default: nil
        }
    }

    /// What the copied notice says under the pointer when typing was refused.
    static let blockedLine = "Typing is blocked — paste it"

    /// Everything the wide form says, for the pointer, so a shortened line is still readable in full.
    static func hoverText(for presentation: DockPresentation, primaryLine: String) -> String {
        [primaryLine, presentation.secondaryLine].compactMap(\.self).joined(separator: "\n")
    }

    /// The button's words as drawn: the setup form's own, else the recovery's verb.
    static func title(for action: RecoveryAction, in presentation: DockPresentation) -> String {
        presentation.setup?.actionTitle ?? title(for: action)
    }

    /// One verb per recovery, matching the sentence the failure already offered.
    static func title(for action: RecoveryAction) -> String {
        RecoveryActionTitle.title(for: action)
    }
}

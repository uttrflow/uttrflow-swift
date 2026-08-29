import Foundation

/// Why the panel's microphone cannot be used.
public enum PanelDictationObstacle: Sendable, Equatable {
    /// I6 — macOS has not been asked, or was told no.
    case microphoneNotGranted
    /// I7 — the speech model is still arriving.
    ///
    /// Its own case, and not merely "unavailable", because the clipboard is unaffected:
    /// saying which of the two halves is not ready is the difference between "one control
    /// is still downloading" and "this panel is broken".
    case modelNotReady(percent: Int?)
}

/// Whether the panel's microphone can start a dictation.
///
/// Deliberately not a progress state. Pressing it starts the same dictation ⌥Space starts,
/// and the panel closes: the words go to the caret, and *listening*, *transcribing* and
/// "didn't catch that" are already shown on the floating dock, which is built for exactly
/// that and stays visible over whatever the user is typing into.
///
/// A second live transcript inside a panel that has to close before the words can be
/// inserted would be two places reporting one dictation, and the one that could not finish
/// the job would be the more prominent of them.
public enum PanelDictation: Sendable, Equatable {
    case ready
    case unavailable(PanelDictationObstacle)

    public var canStart: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// The microphone, ready to draw.
public struct PanelMicrophone: Sendable, Equatable {
    public let symbolName: String
    /// What a screen reader says. Always states what will happen, or why nothing will —
    /// never just "Microphone".
    public let label: String
    public let isEnabled: Bool
    /// Shown beside it when it cannot be used, because a dimmed button with no reason is
    /// a button the user presses twice and then distrusts.
    public let status: String?

    public init(symbolName: String, label: String, isEnabled: Bool, status: String?) {
        self.symbolName = symbolName
        self.label = label
        self.isEnabled = isEnabled
        self.status = status
    }
}

extension PanelPresenter {
    /// I1, I6, I7.
    public static func microphone(for state: PanelDictation) -> PanelMicrophone {
        switch state {
        case .ready:
            PanelMicrophone(
                symbolName: "mic", label: "Dictate — the words go where your cursor is",
                isEnabled: true, status: nil)

        case .unavailable(.microphoneNotGranted):
            PanelMicrophone(
                symbolName: "mic.slash", label: "Microphone access is off", isEnabled: false,
                status: "Turn on the microphone in System Settings to dictate")

        case .unavailable(.modelNotReady(let percent)):
            PanelMicrophone(
                symbolName: "mic", label: "The speech model is still downloading",
                isEnabled: false,
                status: percent.map { "Speech model \($0)% downloaded" }
                    ?? "Speech model still downloading")
        }
    }
}

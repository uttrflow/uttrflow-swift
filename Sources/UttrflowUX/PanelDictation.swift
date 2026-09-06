// The panel's microphone: why it cannot be used, and what it says about itself.
import Foundation

/// Why the panel's microphone cannot be used.
public enum PanelDictationObstacle: Sendable, Equatable {
    /// macOS has not been asked, or said no.
    case microphoneNotGranted
    /// The speech model is still arriving; its own case, since the clipboard half is unaffected.
    case modelNotReady(percent: Int?)
}

/// Whether the microphone can start a dictation; not a progress state, since the dock shows that.
public enum PanelDictation: Sendable, Equatable {
    /// Pressing it starts a dictation.
    case ready
    /// Pressing it does nothing, for this reason.
    case unavailable(PanelDictationObstacle)

    /// Whether pressing it does anything.
    public var canStart: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// The microphone, ready to draw.
public struct PanelMicrophone: Sendable, Equatable {
    /// The SF Symbol on the button.
    public let symbolName: String
    /// What a screen reader says: what will happen, or why nothing will, never just "Microphone".
    public let label: String
    /// Whether it can be pressed.
    public let isEnabled: Bool
    /// Shown beside it when it cannot be used, since a dimmed button with no reason gets pressed twice.
    public let status: String?

    /// Builds the microphone from its parts.
    public init(symbolName: String, label: String, isEnabled: Bool, status: String?) {
        self.symbolName = symbolName
        self.label = label
        self.isEnabled = isEnabled
        self.status = status
    }
}

extension PanelPresenter {
    /// The microphone as drawn for a state.
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

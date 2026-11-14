// What the panel says when clipboard capture is off or paused, so an empty list is not mistaken for a broken one.
public import Foundation

/// Whether copies are being kept, as the panel needs to say it.
public enum PanelCapture: Sendable, Equatable {
    /// Copies are kept.
    case on
    /// The Clipboard switch in Settings is off.
    case off
    /// Capture is paused until the moment given.
    case paused(until: Date)
}

extension PanelCapture {
    /// What to say from the setting and the pause; preferences that cannot be read hold capture paused with no end, which reads as off.
    public static func decided(isEnabled: Bool, isPaused: Bool, pausedUntil: Date?) -> PanelCapture {
        guard isEnabled else { return .off }
        guard isPaused else { return .on }
        guard let pausedUntil else { return .off }
        return .paused(until: pausedUntil)
    }
}

extension PanelPresenter {
    /// The one nothing that is about capture rather than the list, or `nil` when copies are being kept.
    static func captureEmptyState(for snapshot: PanelSnapshot) -> MainEmptyState? {
        switch snapshot.capture {
        case .on:
            return nil
        case .off:
            return MainEmptyState(
                symbolName: "doc.on.clipboard", title: "Clipboard history is off",
                message: "Copies are not kept while it is off.")
        case .paused(let until):
            return MainEmptyState(
                symbolName: "pause.circle", title: "Clipboard history is paused",
                message:
                    "\(pauseSentence(until: until, now: snapshot.now)) Copies in the meantime are not kept.")
        }
    }

    /// The button beside that empty state or banner: turning capture on, or ending the pause.
    static func captureAction(for snapshot: PanelSnapshot) -> PanelAction? {
        switch snapshot.capture {
        case .on: nil
        case .off: PanelAction(title: "Turn on", symbolName: "power", intent: .turnOnCapture)
        case .paused: PanelAction(title: "Resume", symbolName: "play", intent: .resumeCapture)
        }
    }

    /// The short line over a list that has clips in it, saying the same.
    static func captureBanner(for snapshot: PanelSnapshot) -> PanelNotice? {
        guard let state = captureEmptyState(for: snapshot) else { return nil }
        let message =
            switch snapshot.capture {
            case .paused(let until): pauseSentence(until: until, now: snapshot.now)
            default: state.title
            }
        return PanelNotice(
            symbolName: snapshot.capture == .off ? "doc.on.clipboard" : "pause.circle",
            message: message, action: captureAction(for: snapshot),
            announcementID: PanelCaptureAnnouncement.id(for: snapshot.capture))
    }

    /// What a pause has left, rounded up so it never reads as "0 minutes left".
    static func pauseSentence(until: Date, now: Date) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return "Paused, \(minutes) \(minutes == 1 ? "minute" : "minutes") left."
    }
}

/// A stable identity for each capture state, so a redraw is not announced again.
enum PanelCaptureAnnouncement {
    static func id(for capture: PanelCapture) -> UUID {
        switch capture {
        case .on: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        case .off: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        case .paused: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        }
    }
}

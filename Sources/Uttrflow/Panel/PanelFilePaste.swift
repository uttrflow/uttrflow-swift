// What the panel does with a file clip on Return, Copy and the copy-only path, decided apart from the machine.

import Foundation
import UttrflowClipboard
import UttrflowCore
import UttrflowUX

/// Resolves a file clip and says how a placement ended; the app only supplies the real pasteboard and keystroke.
enum PanelFilePaste {
    /// The files to put back, or the notice for the ones that are gone.
    enum Resolution: Equatable {
        case files([URL])
        case refused(PanelNotice)
    }

    /// What the app does once a placement has ended: a panel effect, a report on the floating button, or both.
    struct Landing: Equatable {
        let effect: PanelEffect?
        let report: PanelPasteResult?
    }

    /// All or nothing: one missing file refuses the whole selection, and the notice names it.
    static func resolve(_ clip: Clip) -> Resolution {
        switch clip.fileResolution {
        case .available(let urls)?: .files(urls)
        case .unavailable(let names)?: .refused(.filesMissing(names))
        case nil: .files([])
        }
    }

    /// How the write and the paste ended; `failure` is what the insertion engine threw, if anything.
    static func landing(
        _ placement: PanelFilePlacement, failure: TextInsertionError?, copyFailed: PanelNotice
    ) -> Landing {
        switch (placement, failure) {
        case (.paste, nil): Landing(effect: nil, report: nil)
        case (.paste, let failure?): Landing(effect: nil, report: report(after: failure))
        case (.copyAndSay(let notice), nil): Landing(effect: .say(notice), report: nil)
        case (.copy, nil): Landing(effect: .close, report: .copied(.files))
        case (_, _?): Landing(effect: .say(copyFailed), report: nil)
        }
    }

    /// Files left on the clipboard are said to be there; a clipboard another copy took over is said to be untouched.
    private static func report(after failure: TextInsertionError) -> PanelPasteResult {
        switch failure {
        case .clipboardUnavailable, .clipboardChanged, .insertionCancelled: .textCouldNotPaste
        default: .filesRefused
        }
    }
}

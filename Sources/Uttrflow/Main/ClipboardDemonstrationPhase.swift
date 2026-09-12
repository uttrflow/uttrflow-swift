// The clipboard demonstration's clock and its choice of arrangement, both pure functions.

import CoreGraphics
import Foundation

/// Everything the demonstration draws at one instant, as a function of the clock alone.
struct ClipboardDemonstrationPhase: Equatable {
    let keysAreDown: Bool
    let returnIsDown: Bool
    /// 0 while the panel is absent, 1 once it is fully there.
    let panel: Double
    let selected: Int
    let highlight: Double
    /// How much of the chosen line has been typed into the document, 0 to 1.
    let typed: Double

    /// How long the whole story takes: long enough to read the pasted line, short enough to see it happen.
    static let loop: Double = 8

    /// The whole animation as a function of the clock, so the page can redraw under it without a stutter.
    static func at(_ date: Date) -> Self {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        func at(
            keys: Bool = false, enter: Bool = false, panel: Double, row: Int,
            highlight: Double, typed: Double = 0
        ) -> Self {
            Self(
                keysAreDown: keys, returnIsDown: enter, panel: panel, selected: row,
                highlight: highlight, typed: typed)
        }
        switch t {
        // Someone is part-way through writing something. Nothing is happening yet.
        case ..<1.0: return at(panel: 0, row: 0, highlight: 0)
        // The keys go down and the panel arrives with them.
        case ..<1.9: return at(keys: true, panel: eased((t - 1.0) / 0.9), row: 0, highlight: 0)
        // It settles, and the first line is under the cursor.
        case ..<2.5: return at(panel: 1, row: 0, highlight: 1)
        // Down, and down again — which is how it is actually used.
        case ..<3.1: return at(panel: 1, row: 1, highlight: 1)
        case ..<3.9: return at(panel: 1, row: 2, highlight: 1)
        // Return. The panel goes.
        case ..<4.3: return at(enter: true, panel: 1, row: 2, highlight: 1)
        case ..<4.9:
            return at(panel: 1 - eased((t - 4.3) / 0.6), row: 2, highlight: 1)
        // And the words land where the cursor was, which is the whole point of the thing.
        case ..<5.9:
            return at(panel: 0, row: 2, highlight: 0, typed: eased((t - 4.9) / 1.0))
        // Long enough to read what arrived before it resets.
        default: return at(panel: 0, row: 2, highlight: 0, typed: 1)
        }
    }

    /// Ease-out, so things arrive rather than snapping.
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}

/// Which of the demonstration's two arrangements a given width can hold. See Docs/app-main-window.md.
enum ClipboardDemonstrationArrangement: Equatable {
    case sideBySide(explanationWidth: CGFloat)
    case stacked
}

/// The card's fixed dimensions, and the width at which it stops being able to stand side by side.
enum ClipboardDemonstrationMetrics {
    /// The card's own inset, inside the surface.
    static let padding: CGFloat = 17

    /// Between the words and the document, in the side-by-side arrangement.
    static let columnSpacing: CGFloat = 22

    /// Wide enough for the pasted line to arrive unwrapped: 373 points of text and ten of padding a side.
    static let documentWidth: CGFloat = 400

    /// Tall enough for the panel to sit over the document without either being clipped.
    static let stageHeight: CGFloat = 172

    /// The narrowest the words may be beside the document before the stacked arrangement reads better.
    static let explanationMinimumWidth: CGFloat = 360

    /// The widest the words are allowed to run, so a long line stays comfortable to read.
    static let explanationMaximumWidth: CGFloat = 460

    /// Chooses the arrangement from the width the card is offered, once, rather than on every frame.
    static func arrangement(forOfferedWidth width: CGFloat) -> ClipboardDemonstrationArrangement {
        let forWords = width - padding * 2 - columnSpacing - documentWidth
        guard forWords >= explanationMinimumWidth else { return .stacked }
        return .sideBySide(explanationWidth: min(forWords, explanationMaximumWidth))
    }
}

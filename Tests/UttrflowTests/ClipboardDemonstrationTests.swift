// Tests for the clipboard demonstration's clock and its choice of arrangement.

import CoreGraphics
import Foundation
import Testing

@testable import Uttrflow

/// The arrangement is settled from the width alone, so no frame of the animation has to measure anything.
@Suite("The clipboard demonstration's arrangement")
struct ClipboardDemonstrationArrangementTests {
    /// Padding both sides, the gap, the document, and the narrowest the words may be beside it.
    private let threshold: CGFloat = 17 * 2 + 22 + 400 + 360

    @Test("stands side by side as soon as the words have their narrowest room")
    func sideBySideAtTheThreshold() {
        let arrangement = ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: threshold)

        #expect(arrangement == .sideBySide(explanationWidth: 360))
    }

    @Test("stacks one point below it")
    func stacksBelowTheThreshold() {
        let arrangement = ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: threshold - 1)

        #expect(arrangement == .stacked)
    }

    @Test("stacks at the minimum window, where reserving the document leaves too little for the words")
    func stacksAtTheMinimumWindow() {
        #expect(ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: 700) == .stacked)
    }

    @Test("stacks before it has been offered a width, rather than guessing one")
    func stacksBeforeItIsMeasured() {
        #expect(ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: 0) == .stacked)
    }

    @Test("never lets the words run wider than is comfortable to read")
    func wordsStopAtTheirMaximum() {
        for width in stride(from: threshold, through: 3000, by: 37.0) {
            guard
                case .sideBySide(let explanationWidth) =
                    ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: width)
            else {
                Issue.record("\(width) points should stand side by side")
                continue
            }
            #expect(explanationWidth <= 460)
            #expect(explanationWidth >= 360)
        }
    }

    @Test("always leaves the document its full width, so the pasted line never wraps")
    func theDocumentKeepsItsWidth() {
        for width in stride(from: threshold, through: 3000, by: 37.0) {
            guard
                case .sideBySide(let explanationWidth) =
                    ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: width)
            else { continue }
            let used = 17 * 2 + explanationWidth + 22 + 400
            #expect(used <= width)
        }
    }
}

/// `ViewThatFits` and a clock are what #100 is about: inside one it is slow, outside one it freezes.
@Suite("The clipboard demonstration's structure")
struct ClipboardDemonstrationStructureTests {
    private var source: String {
        get throws {
            let card = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/Uttrflow/Main/ClipboardDemonstration.swift")
            return try String(contentsOf: card, encoding: .utf8)
        }
    }

    @Test("measures nothing per frame: no ViewThatFits anywhere near the clock")
    func noViewThatFits() throws {
        #expect(!(try source.contains("ViewThatFits")))
    }

    @Test("keeps exactly one clock, and not one per candidate arrangement")
    func oneTimeline() throws {
        #expect(try source.components(separatedBy: "TimelineView").count - 1 == 1)
    }
}

/// The card's whole job is to move, so these say the clock still drives it frame by frame.
@Suite("The clipboard demonstration's clock")
struct ClipboardDemonstrationPhaseTests {
    private func phase(at t: Double) -> ClipboardDemonstrationPhase {
        .at(Date(timeIntervalSinceReferenceDate: t))
    }

    @Test("changes from one display frame to the next while the panel is arriving")
    func movesBetweenAdjacentFrames() {
        #expect(phase(at: 1.5) != phase(at: 1.5 + 1.0 / 120.0))
    }

    @Test("changes from one display frame to the next while the words are landing")
    func movesWhileTyping() {
        #expect(phase(at: 5.2) != phase(at: 5.2 + 1.0 / 120.0))
    }

    @Test("draws hundreds of distinct frames over one loop, which is what a redraw is for")
    func aLoopIsNotAStill() {
        var seen = Set<Double>()
        for step in 0..<960 {
            let moment = phase(at: Double(step) / 120.0)
            seen.insert(moment.panel + moment.typed + moment.highlight + Double(moment.selected))
        }

        #expect(seen.count > 200)
    }

    @Test("tells the whole story: keys, panel, a walk down the rows, return, then the words arriving")
    func theStoryInOrder() {
        #expect(phase(at: 0.5).panel == 0)
        #expect(phase(at: 1.5).keysAreDown)
        #expect(phase(at: 2.2).panel == 1)
        #expect(phase(at: 2.2).selected == 0)
        #expect(phase(at: 2.8).selected == 1)
        #expect(phase(at: 3.5).selected == 2)
        #expect(phase(at: 4.1).returnIsDown)
        #expect(phase(at: 4.95).panel == 0)
        #expect(phase(at: 5.9).typed == 1)
    }

    @Test("repeats every eight seconds, so it is a loop rather than a run")
    func itLoops() {
        for t in stride(from: 0.0, to: 8.0, by: 0.13) {
            let first = phase(at: t)
            let next = phase(at: t + ClipboardDemonstrationPhase.loop)
            #expect(first.keysAreDown == next.keysAreDown)
            #expect(first.returnIsDown == next.returnIsDown)
            #expect(first.selected == next.selected)
            #expect(abs(first.panel - next.panel) < 1e-9)
            #expect(abs(first.highlight - next.highlight) < 1e-9)
            #expect(abs(first.typed - next.typed) < 1e-9)
        }
    }
}

// The measurements the dock is drawn to, and the bar drawing that uses them.

import SwiftUI

/// The measurements the design is drawn to.
enum DockMetrics {
    static let gripWidth: CGFloat = 9
    /// Three dots, so the sliver at the edge of the screen stays small.
    static let gripHeight: CGFloat = 34
    static let gripDotSize: CGFloat = 3
    static let gripDotSpacing: CGFloat = 3
    static let gripDotCount = 3
    /// Invisible, hoverable margin around every form, and the room the shadow needs.
    static let gripHitPadding: CGFloat = 6
    static let hintHeight: CGFloat = 30
    /// How wide the hint grows to say why the shortcut cannot be heard, which wraps over a few lines.
    static let unheardWidth: CGFloat = 240
    static let orbSize: CGFloat = 30
    static let listeningHeight: CGFloat = 32
    /// The running clock beside the meter.
    static let clockSize: CGFloat = 11
    static let workingOrbSize: CGFloat = 40
    /// The disc an insertion is drawn in.
    static let badgeSize: CGFloat = 26
    static let clipboardHeight: CGFloat = 28
    /// The widest a quiet outcome's words run before they wrap to a second line.
    static let quietTextMaxWidth: CGFloat = 200
    /// The width of the one wide form, and of no other.
    static let noticeMaxWidth: CGFloat = 300
    /// The wide form's height with one line of text; it grows when the message wraps.
    static let noticeHeight: CGFloat = 40
    static let noticeHorizontalPadding: CGFloat = 14
    static let noticeVerticalPadding: CGFloat = 8
    static let noticeSpacing: CGFloat = 12
    static let noticeBadgeSize: CGFloat = 22
    /// The blocked form's width, which wraps its line onto two.
    static let blockedWidth: CGFloat = 200
    /// The most lines a message may wrap to; every failure message is measured against it in the tests.
    static let noticeMaxLines = 3
    /// The width the message wraps within, beside the badge.
    static let noticeTextWidth: CGFloat =
        noticeMaxWidth - 2 * noticeHorizontalPadding - noticeBadgeSize - noticeSpacing
    static let bodySize: CGFloat = 13
    static let footnoteSize: CGFloat = 10
}

extension DockMetrics {
    static let meterBarWidth: CGFloat = 2.2
    static let meterBarSpacing: CGFloat = 1.8
    static let meterHeight: CGFloat = 22
    /// Fixed rather than derived from a bar count: the row scrolls, so the width decides how many fit.
    static let meterWidth: CGFloat = 100
    /// How far in from each end the meter fades up from nothing, as a share of its width.
    static let meterFade: CGFloat = 0.2
    /// The tallest a capsule gets, as a share of the meter's height; under one so it never touches the glass.
    static let meterAmplitude: CGFloat = 0.9
    /// How often a bar arrives — the rate the panel polls the microphone at.
    static let meterArrivalInterval: TimeInterval = 0.05
    /// How strongly a quiet bar is drawn; opacity carries the loud threshold. See Docs/app-dock.md.
    static let meterQuietOpacity: CGFloat = 0.62
    /// The inserted disc's return arrow, and its stroke on the arrow's 24-unit grid.
    static let returnGlyphSize: CGFloat = 13
    static let returnGlyphLine: CGFloat = 1.8

    /// The working bars at full height, the same three the idle orb wears.
    static let workingBarHeights: [CGFloat] = [8, 14, 10]
    static let workingBarWidth: CGFloat = 3
    static let workingBarSpacing: CGFloat = 3
    /// How long one bar takes to rise and settle.
    static let workingCycle: TimeInterval = 1
    /// How far behind each bar moves the one to its left.
    static let workingStagger: TimeInterval = 0.15
    /// The share of its height a bar settles to.
    static let workingRest: CGFloat = 0.4

    /// How tall this bar stands as a share of its height: `workingRest` settled, 1 at the top of its rise.
    static func workingStretch(_ elapsed: TimeInterval, _ index: Int) -> CGFloat {
        var phase = ((elapsed - Double(index) * workingStagger) / workingCycle)
            .truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        let rise = (1 - cos(phase * 2 * .pi)) / 2
        return workingRest + (1 - workingRest) * CGFloat(rise)
    }

    /// Draws the live microphone meter as a scrolling row of capsules.
    static func drawBars(
        _ levels: [CGFloat], in context: GraphicsContext, size: CGSize,
        phase: Double, towardsLeading: Bool
    ) {
        let step = meterBarWidth + meterBarSpacing
        let loud = GraphicsContext.Shading.color(.dockMeter)
        let quiet = GraphicsContext.Shading.color(Color.dockMeter.opacity(meterQuietOpacity))
        for (index, level) in levels.enumerated() {
            // One step before the panel starts, so the newest bar enters from beyond the edge.
            let offset = (CGFloat(index) + CGFloat(phase) - 1) * step
            let x = towardsLeading ? size.width - offset - meterBarWidth : offset
            guard x < size.width, x > -step else { continue }
            // A quiet bar is a dot: at this width the cap radius is the whole bar.
            let height = max(meterBarWidth, level * size.height * meterAmplitude)
            let rect = CGRect(
                x: x, y: (size.height - height) / 2, width: meterBarWidth, height: height)
            context.fill(
                Path(roundedRect: rect, cornerRadius: meterBarWidth / 2),
                with: DockBars.isLoud(level) ? loud : quiet)
        }
    }
}

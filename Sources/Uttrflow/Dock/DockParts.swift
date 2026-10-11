// The small views the dock forms are assembled from.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

/// The level as a row of capsules, redrawn up to the motion budget's rate and faded so bars enter and leave softly.
struct LevelMeterView: View {
    let model: DockViewModel
    /// Whether the clock is on the leading edge; sound always flows in from the side away from the clock.
    let towardsLeading: Bool

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: motion.dockFrameInterval,
                paused: !motion.levelMeterMoves)
        ) { timeline in
            Canvas { context, size in
                let phase = motion.levelMeterPhase(
                    elapsedSinceArrival: timeline.date.timeIntervalSince(model.lastArrival))
                DockMetrics.drawBars(
                    model.bars.levels, in: context, size: size,
                    phase: phase, towardsLeading: towardsLeading)
            }
        }
        .frame(width: DockMetrics.meterWidth, height: DockMetrics.meterHeight)
        .clipShape(.rect)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: DockMetrics.meterFade),
                    .init(color: .black, location: 1 - DockMetrics.meterFade),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// The running clock, advanced by the meter's own arrivals so it adds no timer of its own.
struct DockClock: View {
    let model: DockViewModel

    var body: some View {
        Text(
            DockWording.clockText(
                for: model.presentation, startedAt: model.recordingStartedAt, now: model.lastArrival)
        )
        .font(.system(size: DockMetrics.clockSize, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .opacity(0.6)
        .fixedSize()
    }
}

/// Working: three bars rise and settle in turn while work remains.
struct SettlingBars: View {
    /// When the bars appeared, so every bar moves off one clock.
    @State private var began = Date.now

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(minimumInterval: motion.dockFrameInterval, paused: !motion.workingBarsMove)
        ) { timeline in
            let elapsed = timeline.date.timeIntervalSince(began)
            HStack(spacing: DockMetrics.workingBarSpacing) {
                ForEach(Array(DockMetrics.workingBarHeights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(.primary)
                        .frame(width: DockMetrics.workingBarWidth, height: height)
                        .scaleEffect(
                            x: 1, y: motion.workingBarsMove ? DockMetrics.workingStretch(elapsed, index) : 1)
                }
            }
        }
    }
}

/// A return arrow on a 24-unit grid: down the right, round the corner, and left into its head.
struct ReturnArrow: Shape {
    static let grid: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.grid
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: at(20, 4))
        path.addLine(to: at(20, 11))
        path.addArc(tangent1End: at(20, 15), tangent2End: at(4, 15), radius: 4 * scale)
        path.addLine(to: at(4, 15))
        path.move(to: at(9, 10))
        path.addLine(to: at(4, 15))
        path.addLine(to: at(9, 20))
        return path
    }
}

/// Inserted: a teal return arrow drawn on inside the disc's ring, the key that puts words in.
struct InsertedMark: View {
    @State private var drawn = false

    var body: some View {
        ReturnArrow()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(
                Color.dockSetupAccent,
                style: StrokeStyle(
                    lineWidth: DockMetrics.returnGlyphLine * DockMetrics.returnGlyphSize / ReturnArrow.grid,
                    lineCap: .round, lineJoin: .round)
            )
            .frame(width: DockMetrics.returnGlyphSize, height: DockMetrics.returnGlyphSize)
            .task {
                withAnimation(MotionBudget.current().allowing(.easeOut(duration: 0.26))) { drawn = true }
            }
    }
}

/// Nothing heard: a level with a line through it, in no red and with no warning triangle.
struct StruckLevel: View {
    private static let heights: [CGFloat] = [5, 9, 6, 10, 4]

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(Array(Self.heights.enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(.primary.opacity(0.45))
                        .frame(width: 2, height: height)
                }
            }
            Capsule()
                .fill(.primary.opacity(0.62))
                .frame(width: 20, height: 1.5)
                .rotationEffect(.degrees(-34))
        }
    }
}

/// The round mark beside a finished result.
struct Badge: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: DockMetrics.noticeBadgeSize, height: DockMetrics.noticeBadgeSize)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white))
    }
}

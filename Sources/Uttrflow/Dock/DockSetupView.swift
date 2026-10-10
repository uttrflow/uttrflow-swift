// The floating button's forms while the speech model downloads, loads, failed to load, or is not on disk.

import UttrflowCore
import UttrflowPipeline
import SwiftUI

/// One resting form for the speech model's setup: a ring with words, or a warning with its one button.
struct DockSetupView: View {
    let setup: DockModelSetup
    let presentation: DockPresentation
    var onRecovery: (RecoveryAction) -> Void

    var body: some View {
        switch setup {
        case .downloading(let fraction):
            capsule {
                DockSetupRing(fraction: fraction)
                Text(presentation.primaryLine ?? "")
                if let percent = presentation.secondaryLine {
                    Text(percent)
                        .monospacedDigit()
                        .opacity(0.55)
                }
            }
        case .loading(let estimate):
            capsule {
                if let estimate {
                    DockSetupRing(fraction: estimate)
                } else {
                    DockSetupSpinner()
                }
                Text(presentation.primaryLine ?? "")
                if let left = presentation.secondaryLine {
                    Text(left).opacity(0.55)
                }
            }
            .help(presentation.accessibilityLabel)
        case .failed, .broken:
            warning(accent: .dockSetupWarning, badgeOpacity: 0.2, width: DockSetupMetrics.failedWidth)
        case .missing:
            warning(accent: .dockSetupAccent, badgeOpacity: 0.18, width: DockSetupMetrics.missingWidth)
        }
    }

    /// The short glass capsule a ring and its words sit in.
    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .font(.system(size: DockSetupMetrics.capsuleTextSize))
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: DockSetupMetrics.capsuleHeight)
            .glass(cornerRadius: DockSetupMetrics.capsuleHeight / 2)
    }

    /// The warning disc, the line, and the filled button that fixes it.
    private func warning(accent: Color, badgeOpacity: Double, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: DockMetrics.noticeBadgeSize, height: DockMetrics.noticeBadgeSize)
                .background(accent.opacity(badgeOpacity), in: .circle)
            Text(presentation.primaryLine ?? "")
                .font(.system(size: DockSetupMetrics.warningTextSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = presentation.action, let title = setup.actionTitle {
                Button {
                    onRecovery(action)
                } label: {
                    Text(title)
                        .font(.system(size: DockSetupMetrics.warningTextSize, weight: .semibold))
                        .foregroundStyle(Color.dockOnAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: width)
        .glass(cornerRadius: DockSetupMetrics.warningRadius)
        .help(DockWording.hoverText(for: presentation, primaryLine: presentation.primaryLine ?? ""))
    }
}

/// The arc filled clockwise from the top to the share done over a faint track, easing between ticks unless motion is held still.
private struct DockSetupRing: View {
    let fraction: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        ZStack {
            // White at 18%, which the design's light glass swallows, so only the dark button shows a track.
            Circle().stroke(
                scheme == .dark ? Color.white.opacity(DockSetupMetrics.trackOpacity) : .clear,
                lineWidth: DockSetupMetrics.ringLine)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    Color.dockSetupAccent,
                    style: StrokeStyle(lineWidth: DockSetupMetrics.ringLine, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(motion.workingBarsMove ? .linear(duration: 1) : nil, value: fraction)
        }
        .frame(width: DockSetupMetrics.ringDiameter, height: DockSetupMetrics.ringDiameter)
        .frame(width: DockSetupMetrics.ringBox, height: DockSetupMetrics.ringBox)
    }
}

/// A quarter arc turning once every 1.1 seconds; held still under Reduce Motion.
private struct DockSetupSpinner: View {
    /// When the spinner appeared, so the turn starts from the top.
    @State private var began = Date.now

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(.animation(minimumInterval: motion.dockFrameInterval, paused: !motion.workingBarsMove)) {
            timeline in
            let turns = timeline.date.timeIntervalSince(began) / DockSetupMetrics.spinPeriod
            Circle()
                .trim(from: 0, to: DockSetupMetrics.spinnerArc)
                .stroke(
                    Color.dockSetupAccent,
                    style: StrokeStyle(lineWidth: DockSetupMetrics.spinnerLine, lineCap: .round)
                )
                .rotationEffect(
                    .degrees(motion.workingBarsMove ? turns.truncatingRemainder(dividingBy: 1) * 360 : 0))
        }
        .frame(width: DockSetupMetrics.spinnerDiameter, height: DockSetupMetrics.spinnerDiameter)
        .frame(width: DockSetupMetrics.ringBox, height: DockSetupMetrics.ringBox)
    }
}

/// The setup forms' measurements.
enum DockSetupMetrics {
    static let capsuleHeight: CGFloat = 34
    static let capsuleTextSize: CGFloat = 12.5
    static let warningTextSize: CGFloat = 12
    static let warningRadius: CGFloat = 18
    /// The failed form is wider than the missing one, since its line is longer.
    static let failedWidth: CGFloat = 264
    static let missingWidth: CGFloat = 250
    /// The square both rings are centred in.
    static let ringBox: CGFloat = 18
    static let ringDiameter: CGFloat = 15
    static let ringLine: CGFloat = 2.25
    /// How strongly the dark ring's unfilled track is drawn.
    static let trackOpacity: Double = 0.18
    static let spinnerDiameter: CGFloat = 15.75
    static let spinnerLine: CGFloat = 2.6
    /// The share of the circle the spinner's arc covers.
    static let spinnerArc: CGFloat = 0.24
    static let spinPeriod: TimeInterval = 1.1
}

extension Color {
    /// Dictation's teal on the dock's glass, deepened on a light desktop.
    static let dockSetupAccent = Color(nsColor: .orbit(BrandPalette.Redesign.dictationAccent))
    /// The amber of a load that needs a hand, deepened on a light desktop.
    static let dockSetupWarning = Color(nsColor: .orbit(BrandPalette.Redesign.clipboardAccent))
    /// Words on a button filled with an accent.
    static let dockOnAccent = Color(nsColor: .orbit(BrandPalette.Redesign.onAccentInk))
}

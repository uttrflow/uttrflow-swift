// Every form the floating button takes, with its parts, sizes and colours.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

/// What the dock is showing; hover and press live here because AppKit, not SwiftUI, notices them.
@MainActor
@Observable
final class DockViewModel {
    var presentation: DockPresentation
    /// How the shortcut reads on a keycap, for example "⌃⌥".
    var shortcut: String
    /// Why the shortcut cannot be heard right now, shown in place of the keycap when set.
    var shortcutUnheard: String?
    /// Which edge the button is parked on, so the button stays nearest that edge as the form grows.
    var anchor: DockAnchor
    var isHovering = false
    var isPressed = false
    /// Microphone loudness in `0...1` as RMS, written at 20 Hz while recording; not part of the presentation.
    var level: Float = 0
    /// The row of capsules, one per arrival, newest first.
    private(set) var bars = DockBars()
    /// When the newest bar landed, so the view places bars at a fractional offset between arrivals.
    private(set) var lastArrival = Date()

    /// One arrival: the level the microphone reported, and one more capsule.
    func meter(_ level: Float, now: Date = Date()) {
        self.level = level
        bars.arrive(DockLevel.scale(rms: level))
        lastArrival = now
    }
    /// When the current recording started, for the clock; kept across redraws so the clock never restarts.
    private(set) var recordingStartedAt: Date?
    /// Whether the idle button collapses to a grip, from the "Shrink it to a grip" setting.
    var shrinksToGrip = true
    /// Whether the panel is on screen; a hidden button draws nothing, so its meter and spinners stop.
    var isShown = true

    /// The only way the presentation changes; starts the clock on the first recording presentation.
    func show(_ presentation: DockPresentation, now: Date = Date()) {
        if presentation.isRecording {
            // Cleared as a recording begins, not ends, so the working animation settles the last row.
            if recordingStartedAt == nil {
                bars.clear()
                lastArrival = now
            }
            recordingStartedAt = recordingStartedAt ?? now
        } else {
            recordingStartedAt = nil
            level = 0
        }
        self.presentation = presentation
    }

    init(
        presentation: DockPresentation, shortcut: String, anchor: DockAnchor,
        shrinksToGrip: Bool = true
    ) {
        self.presentation = presentation
        self.shortcut = shortcut
        self.anchor = anchor
        self.shrinksToGrip = shrinksToGrip
    }
}

/// The floating button in whichever form the state calls for; every form derives from the presentation.
struct DockView: View {
    let model: DockViewModel
    var onPressBegan: () -> Void = {}
    var onPressEnded: () -> Void = {}
    /// Starts or finishes a dictation in one go, for a caller that cannot hold the button down.
    var onToggle: () -> Void = {}
    var onRecovery: (RecoveryAction) -> Void = { _ in }
    /// The size the current form wants; the panel is resized to match, so a grip claims no more screen.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var body: some View {
        form
            .fixedSize()
            .foregroundStyle(Color.dockInk)
            .scaleEffect(model.isPressed ? 0.96 : 1)
            .animation(MotionBudget.current().allowing(.spring(duration: 0.22)), value: model.isPressed)
            .contentShape(.rect)
            // At the root: the form is replaced when recording starts and would miss the mouse-up.
            .gesture(pressGesture, including: model.presentation.action == nil ? .all : .subviews)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                onDesiredSize($0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Ignored rather than combined: the label below replaces whatever the children would say anyway.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.presentation.accessibilityLabel)
            .accessibilityValue(Self.spokenValue(for: model.presentation))
            .accessibilityHint(Self.spokenHint(for: model.presentation))
            .accessibilityAddTraits(.isButton)
            // A press-and-hold is not a gesture VoiceOver can perform, so activating toggles instead.
            .accessibilityAction { onToggle() }
            .accessibilityActions {
                // The recovery the failure draws, spoken; its own button is inside the ignored children.
                if let action = model.presentation.action {
                    Button(Self.title(for: action, in: model.presentation)) { onRecovery(action) }
                }
            }
    }

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

    // MARK: - Forms

    @ViewBuilder private var form: some View {
        let presentation = model.presentation
        if !model.isShown {
            EmptyView()
        } else if presentation.showsWaveform {
            listening()
        } else if presentation.showsProgress {
            working()
        } else if let setup = presentation.setup {
            DockSetupView(setup: setup, presentation: presentation, onRecovery: onRecovery)
                .padding(DockMetrics.gripHitPadding)
        } else if let line = presentation.primaryLine {
            notice(presentation, primaryLine: line)
        } else if model.isHovering || !model.shrinksToGrip {
            hovered()
        } else {
            resting
        }
    }

    /// Three dots at the edge of the screen, drawn straight onto the desktop with no slab under them.
    private var resting: some View {
        VStack(spacing: DockMetrics.gripDotSpacing) {
            ForEach(0..<DockMetrics.gripDotCount, id: \.self) { _ in
                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: DockMetrics.gripDotSize, height: DockMetrics.gripDotSize)
            }
        }
        .frame(width: DockMetrics.gripWidth, height: DockMetrics.gripHeight)
        // Lifts three points of ink off a pale wallpaper.
        .shadow(color: .black.opacity(0.38), radius: 1.5, y: 0.5)
        // Invisible but hoverable: a nine-point strip is hard to point at.
        .padding(DockMetrics.gripHitPadding)
    }

    /// Pointed at: the keycap hint beside the orb, which keeps the grip's side so it stays under the pointer.
    private func hovered() -> some View {
        let orbLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if orbLeads { orb() }
            if let unheard = model.shortcutUnheard {
                Text(unheard)
                    .font(.system(size: DockMetrics.bodySize))
                    .frame(width: DockMetrics.unheardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .glass(cornerRadius: DockMetrics.hintHeight / 2)
            } else {
                HStack(spacing: 8) {
                    Text("Dictate")
                        .font(.system(size: DockMetrics.bodySize))
                    keycap(model.shortcut)
                }
                .fixedSize()
                .padding(.horizontal, 15)
                .frame(height: DockMetrics.hintHeight)
                .glass(cornerRadius: DockMetrics.hintHeight / 2)
            }
            if !orbLeads { orb() }
        }
        .padding(DockMetrics.gripHitPadding)
    }

    /// The idle orb wears the same three bars the meter is made of, at rest.
    private func orb() -> some View {
        HStack(spacing: 2.5) {
            ForEach([6.0, 11.0, 7.0], id: \.self) { height in
                Capsule()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(width: DockMetrics.orbSize, height: DockMetrics.orbSize)
        .glass(cornerRadius: DockMetrics.orbSize / 2)
    }

    /// Listening: a live meter and a running clock, the clock on the anchored edge.
    private func listening() -> some View {
        let clockLeads = model.anchor == .bottomLeft
        return HStack(spacing: 8) {
            if clockLeads { clock() }
            LevelMeterView(model: model, towardsLeading: clockLeads)
            if !clockLeads { clock() }
        }
        .padding(.horizontal, 12)
        .frame(height: DockMetrics.listeningHeight)
        .glass(cornerRadius: DockMetrics.listeningHeight / 2)
        .padding(DockMetrics.gripHitPadding)
    }

    /// The time since the key went down, or the time left once the cap is near.
    private func clock() -> some View {
        DockClock(model: model)
    }

    /// The countdown when the presenter has one, otherwise the elapsed time as "0:04".
    static func clockText(for presentation: DockPresentation, startedAt: Date?, now: Date) -> String {
        if let remaining = presentation.secondaryLine { return remaining }
        let seconds = startedAt.map { now.timeIntervalSince($0) } ?? 0
        return DictationPresenter.elapsed(.seconds(max(seconds, 0)))
    }

    /// Working: a glass orb whose three bars keep settling for as long as there is work left to do.
    private func working() -> some View {
        SettlingBars()
            .frame(width: DockMetrics.workingOrbSize, height: DockMetrics.workingOrbSize)
            .glass(cornerRadius: DockMetrics.workingOrbSize / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    // MARK: - Notices

    /// Finished: a 26-point disc for an insertion, a small pill with words for the quiet outcomes and short failures, and the wide form for the rest.
    @ViewBuilder
    private func notice(_ presentation: DockPresentation, primaryLine: String) -> some View {
        switch presentation.symbolName {
        case "checkmark":
            badgeForm { InsertedMark() }
        case "waveform.slash":
            quietNotice(Self.restingWords(for: presentation) ?? primaryLine)
        case "doc.on.clipboard":
            clipboardNotice(presentation)
        default:
            if let line = Self.pillLine(for: presentation) {
                pill(presentation, line: line, primaryLine: primaryLine)
            } else {
                blocked(presentation, primaryLine: primaryLine)
            }
        }
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

    /// Nothing heard, or too little: the struck level with the sentence that says so, readable at rest.
    private func quietNotice(_ words: String) -> some View {
        HStack(spacing: 8) {
            StruckLevel()
            Text(words)
                .font(.system(size: DockMetrics.footnoteSize + 1))
                .opacity(0.72)
                .lineLimit(2)
                .frame(maxWidth: DockMetrics.quietTextMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: DockMetrics.clipboardHeight)
        .glass(cornerRadius: DockMetrics.clipboardHeight / 2)
        .padding(DockMetrics.gripHitPadding)
    }

    /// The 26-point disc an insertion is drawn in.
    private func badgeForm(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: DockMetrics.badgeSize, height: DockMetrics.badgeSize)
            .glass(cornerRadius: DockMetrics.badgeSize / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    /// Copied rather than typed: ⌘V and the words saying so at rest, the blocked form with its fix under the pointer.
    @ViewBuilder
    private func clipboardNotice(_ presentation: DockPresentation) -> some View {
        if model.isHovering, presentation.action != nil {
            pill(
                presentation, line: Self.blockedLine, primaryLine: presentation.primaryLine ?? "",
                symbolName: "exclamationmark.triangle", width: DockMetrics.blockedWidth)
        } else {
            HStack(spacing: 8) {
                keycap("⌘V")
                    .foregroundStyle(Color.dockWarningInk)
                if let words = Self.restingWords(for: presentation) {
                    Text(words)
                        .font(.system(size: DockMetrics.footnoteSize + 1))
                        .opacity(0.72)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: DockMetrics.clipboardHeight)
            .glass(cornerRadius: DockMetrics.clipboardHeight / 2)
            .padding(DockMetrics.gripHitPadding)
        }
    }

    /// What the copied notice says under the pointer when typing was refused.
    static let blockedLine = "Typing is blocked — paste it"

    /// The one state with something for the reader to do, and the only wide form; the message wraps rather than truncates.
    private func blocked(_ presentation: DockPresentation, primaryLine: String) -> some View {
        HStack(spacing: DockMetrics.noticeSpacing) {
            Badge(symbolName: presentation.symbolName, tint: .dockWarningFill)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: DockMetrics.bodySize, weight: .medium))
                    .lineLimit(DockMetrics.noticeMaxLines)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = presentation.secondaryLine {
                    Text(secondary)
                        .font(.system(size: DockMetrics.footnoteSize))
                        .opacity(0.58)
                        .lineLimit(1)
                }
                // Under the words, so the button never takes width the message needs.
                if let action = presentation.action {
                    Button(Self.title(for: action)) { onRecovery(action) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DockMetrics.noticeHorizontalPadding)
        .padding(.vertical, DockMetrics.noticeVerticalPadding)
        .frame(width: DockMetrics.noticeMaxWidth)
        .frame(minHeight: DockMetrics.noticeHeight)
        .glass(cornerRadius: DockMetrics.noticeHeight / 2)
        .help(Self.hoverText(for: presentation, primaryLine: primaryLine))
        .padding(DockMetrics.gripHitPadding)
    }

    /// A failure with a short name: the warning disc, the line and a trailing Fix, with the full sentence on hover.
    private func pill(
        _ presentation: DockPresentation, line: String, primaryLine: String, symbolName: String? = nil,
        width: CGFloat? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName ?? presentation.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dockSetupWarning)
                .frame(width: DockMetrics.noticeBadgeSize, height: DockMetrics.noticeBadgeSize)
                .background(Color.dockSetupWarning.opacity(0.2), in: .circle)
            Text(line)
                .font(.system(size: DockSetupMetrics.warningTextSize))
                .fixedSize(horizontal: width == nil, vertical: true)
                .frame(maxWidth: width == nil ? nil : .infinity, alignment: .leading)
            if let action = presentation.action {
                Button {
                    onRecovery(action)
                } label: {
                    Text("Fix")
                        .font(.system(size: DockSetupMetrics.warningTextSize))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.14), in: .rect(cornerRadius: 6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: width)
        .glass(cornerRadius: DockSetupMetrics.warningRadius)
        .help(Self.hoverText(for: presentation, primaryLine: primaryLine))
        .padding(DockMetrics.gripHitPadding)
    }

    /// Everything the wide form says, for the pointer, so a shortened line is still readable in full.
    static func hoverText(for presentation: DockPresentation, primaryLine: String) -> String {
        [primaryLine, presentation.secondaryLine].compactMap(\.self).joined(separator: "\n")
    }

    // MARK: - Pieces

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DockMetrics.footnoteSize, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(.primary.opacity(0.14), in: .rect(cornerRadius: 5))
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !model.isPressed else { return }
                model.isPressed = true
                onPressBegan()
            }
            .onEnded { _ in
                guard model.isPressed else { return }
                model.isPressed = false
                onPressEnded()
            }
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

// MARK: - Sizes

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

// MARK: - Parts

/// The level as a row of capsules, redrawn up to the motion budget's rate and faded so bars enter and leave softly.
private struct LevelMeterView: View {
    let model: DockViewModel
    /// Whether the clock is on the leading edge; sound always flows in from the side away from the clock.
    let towardsLeading: Bool

    var body: some View {
        TimelineView(
            .animation(minimumInterval: MotionBudgetObserver.shared.budget.dockFrameInterval)
        ) { timeline in
            Canvas { context, size in
                let phase = min(
                    max(
                        timeline.date.timeIntervalSince(model.lastArrival)
                            / DockMetrics.meterArrivalInterval, 0), 1)
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
private struct DockClock: View {
    let model: DockViewModel

    var body: some View {
        Text(
            DockView.clockText(
                for: model.presentation, startedAt: model.recordingStartedAt, now: model.lastArrival)
        )
        .font(.system(size: DockMetrics.clockSize, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .opacity(0.6)
        .fixedSize()
    }
}

/// Working: three bars rise and settle in turn while work remains.
private struct SettlingBars: View {
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
private struct ReturnArrow: Shape {
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
private struct InsertedMark: View {
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
private struct StruckLevel: View {
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
private struct Badge: View {
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

// MARK: - Material

extension View {
    /// The tinted glass every form but the resting one is drawn on: violet-black when dark, frosted white when light.
    func glass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(Color.dockGlass, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.dockGlassEdge, lineWidth: 1))
            // Clipped and flattened before the shadow, or the material's rectangular backing leaks a square halo.
            .clipShape(shape)
            .compositingGroup()
            .shadow(color: .dockShadow, radius: 12, y: 7)
    }
}

// MARK: - Colours

extension Color {
    /// Fills that carry text, capped at 29% lightness so white 13-point text clears 4.5:1.
    static let dockAccent = Color(rgb: BrandPalette.Teal.deep)
    /// Controls and graphics with no text on them.
    static let dockAccentLight = Color(rgb: BrandPalette.Teal.light)
    static let dockAccentTint = Color(rgb: BrandPalette.Teal.tint)
    static let dockAccentWash = Color(rgb: BrandPalette.Teal.wash)
    /// Recording and destructive: the main window's critical tone and its destructive buttons.
    static let dockRecording = Color(rgb: BrandPalette.Semantic.recording)
    /// The live accent: what is selected, what is running.
    static let dockActive = Color(rgb: BrandPalette.Teal.primary)
    /// Words and glyphs on the dock's glass: white when dark, ink when light.
    static let dockInk = Color(nsColor: .orbit(BrandPalette.Redesign.textStrong))
    /// The dock's glass tint over the system material.
    static let dockGlass = Color(nsColor: .orbit(BrandPalette.Redesign.dockGlass))
    /// The hairline round the dock's glass.
    static let dockGlassEdge = Color(nsColor: .orbit(BrandPalette.Redesign.dockGlassEdge))
    static let dockShadow = Color(nsColor: .orbit(BrandPalette.Redesign.dockShadow))
    /// The listening meter: white on the dark glass, dictation teal on the light.
    static let dockMeter = Color(nsColor: .orbit(BrandPalette.Redesign.dockMeter))
    static let dockSuccess = Color(rgb: BrandPalette.Semantic.success)
    static let dockWarning = Color(rgb: BrandPalette.Semantic.warning)
    /// The warning as text on the dock's glass, which the bright tone fails on a light desktop.
    static let dockWarningInk = Color(nsColor: .orbit(BrandPalette.Semantic.cautionInk))
    /// The failure disc under a white glyph.
    static let dockWarningFill = Color(rgb: BrandPalette.Semantic.warningFill)

    /// The accent as text on a surface that follows the appearance; `dockAccent` is for fills.
    static let accentInk = Color(nsColor: .orbit(BrandPalette.Teal.ink))
    /// A warning as text; `dockWarning` is for dots, icons and fills.
    static let warningInk = Color(nsColor: .orbit(BrandPalette.Semantic.warningInk))
    /// Success as text; `dockSuccess` is for dots, icons and fills.
    static let successInk = Color(nsColor: .orbit(BrandPalette.Semantic.successInk))
    /// A failure as text; `dockRecording` is for dots, icons and fills.
    static let criticalInk = Color(nsColor: .orbit(BrandPalette.Semantic.criticalInk))
}

extension LinearGradient {
    /// The accent as a filled control, deepened at the top so the fill reads as lit from above.
    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [Color(rgb: BrandPalette.Teal.deepLit), .dockAccent], startPoint: .top, endPoint: .bottom)
    }
}

// Every form the floating button takes, with its parts, sizes and colours.

import AppKit
import UttrflowCore
import UttrflowPipeline
import SwiftUI

/// What the dock is showing; hover and press live here because AppKit, not SwiftUI, notices them.
@MainActor
@Observable
final class DockViewModel {
    var presentation: DockPresentation
    /// How the shortcut reads on a keycap, for example "⌥Space".
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
    var onRecovery: (RecoveryAction) -> Void = { _ in }
    /// The size the current form wants; the panel is resized to match, so a grip claims no more screen.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var body: some View {
        form
            .fixedSize()
            .scaleEffect(model.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.22), value: model.isPressed)
            .contentShape(.rect)
            // At the root: the form is replaced when recording starts and would miss the mouse-up.
            .gesture(pressGesture, including: model.presentation.action == nil ? .all : .subviews)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                onDesiredSize($0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.presentation.accessibilityLabel)
    }

    // MARK: - Forms

    @ViewBuilder private var form: some View {
        let presentation = model.presentation
        if presentation.showsWaveform {
            listening()
        } else if presentation.showsProgress {
            working()
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
                    .fill(.primary.opacity(0.5))
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(width: DockMetrics.orbSize, height: DockMetrics.orbSize)
        .glass(cornerRadius: DockMetrics.orbSize / 2)
    }

    /// Listening: the mark on the anchored edge and a live meter, and the time left once the cap is near.
    private func listening() -> some View {
        compact { towardsLeading in
            // On the far side of the meter from the mark, so the mark stays on the anchored edge.
            if !towardsLeading { remainingTime() }
            LevelMeterView(model: model, towardsLeading: towardsLeading)
            if towardsLeading { remainingTime() }
        }
    }

    /// The countdown to the cap, drawn only once the presenter has one to say.
    @ViewBuilder private func remainingTime() -> some View {
        if let remaining = model.presentation.secondaryLine {
            Text(remaining)
                .font(.system(size: DockMetrics.footnoteSize, weight: .medium))
                .monospacedDigit()
                .fixedSize()
        }
    }

    /// Working: three dots walking left to right, for as long as there is work left to do.
    private func working() -> some View {
        compact { _ in WorkingDots() }
    }

    /// The pill listening and working share: the mark on the anchored edge, `centre` beside it.
    private func compact(
        @ViewBuilder _ centre: (_ towardsLeading: Bool) -> some View
    ) -> some View {
        let weightLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if weightLeads { weight() }
            centre(weightLeads)
            if !weightLeads { weight() }
        }
        .padding(.leading, weightLeads ? 5 : 12)
        .padding(.trailing, weightLeads ? 12 : 5)
        .frame(height: DockMetrics.compactHeight)
        .glass(cornerRadius: DockMetrics.compactHeight / 2)
        .padding(DockMetrics.gripHitPadding)
    }

    /// The mark, on the edge the panel is parked against.
    private func weight() -> some View {
        UttrflowMark()
            .stroke(
                Color.dockWeightInk,
                style: StrokeStyle(
                    lineWidth: UttrflowMark.lineWidth(forHeight: DockMetrics.weightMarkHeight),
                    lineCap: .round, lineJoin: .round)
            )
            .frame(
                width: DockMetrics.weightMarkHeight * UttrflowMark.aspectRatio,
                height: DockMetrics.weightMarkHeight
            )
            .frame(width: DockMetrics.weightSize, height: DockMetrics.weightSize)
            .background(Color.dockActive, in: .circle)
    }

    // MARK: - Notices

    /// Finished: a 26-point disc for an insertion, a small pill with words for the quiet outcomes, and the wide form for the one that needs an action.
    @ViewBuilder
    private func notice(_ presentation: DockPresentation, primaryLine: String) -> some View {
        switch presentation.symbolName {
        case "checkmark":
            badgeForm { MarkTick() }
        case "waveform.slash":
            quietNotice(Self.restingWords(for: presentation) ?? primaryLine)
        case "doc.on.clipboard":
            clipboardNotice(presentation)
        default:
            blocked(presentation, primaryLine: primaryLine)
        }
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

    /// Copied rather than typed: ⌘V and the words saying so at rest, with the reason and the fix under the pointer.
    private func clipboardNotice(_ presentation: DockPresentation) -> some View {
        HStack(spacing: 8) {
            keycap("⌘V")
                .foregroundStyle(Color.dockWarningInk)
            if model.isHovering, let action = presentation.action {
                Text("Typing is blocked — paste it")
                    .font(.system(size: DockMetrics.footnoteSize + 1))
                    .opacity(0.6)
                    .fixedSize()
                Button("Fix") { onRecovery(action) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            } else if let words = Self.restingWords(for: presentation) {
                Text(words)
                    .font(.system(size: DockMetrics.footnoteSize + 1))
                    .opacity(0.72)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: DockMetrics.clipboardHeight)
        .glass(cornerRadius: DockMetrics.clipboardHeight / 2)
        .animation(.spring(duration: 0.26), value: model.isHovering)
        .padding(DockMetrics.gripHitPadding)
    }

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

    /// One verb per recovery, matching the sentence the failure already offered.
    static func title(for action: RecoveryAction) -> String {
        switch action {
        case .openSystemSettings: "Open Settings"
        case .retry: "Try Again"
        case .downloadSpeechModel: "Download"
        case .pasteManually: "Dismiss"
        case .showRecentDictations: "Show Recent"
        case .retryFromRecording: "Retry"
        }
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
    /// Listening and working share this, so the panel cannot change shape when the key is released.
    static let compactHeight: CGFloat = 32
    static let weightSize: CGFloat = 22
    static let weightMarkHeight: CGFloat = 10
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
    /// The most lines a message may wrap to; every failure message is measured against it in the tests.
    static let noticeMaxLines = 3
    /// The width the message wraps within, beside the badge.
    static let noticeTextWidth: CGFloat =
        noticeMaxWidth - 2 * noticeHorizontalPadding - noticeBadgeSize - noticeSpacing
    static let bodySize: CGFloat = 13
    static let footnoteSize: CGFloat = 10
}

// MARK: - Parts

/// The level as a row of capsules, redrawn up to the motion budget's rate and clipped so new bars enter from the edge.
private struct LevelMeterView: View {
    let model: DockViewModel
    /// Whether the mark is on the leading edge; sound always flows in from the side away from the mark.
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
    }
}

/// Working: the row settles level and folds to a tick, once, and stops scrolling.
private struct WorkingDots: View {
    /// When the row appeared, so every dot walks off one clock.
    @State private var began = Date.now

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(minimumInterval: motion.dockFrameInterval, paused: !motion.workingDotsMove)
        ) { timeline in
            let elapsed = timeline.date.timeIntervalSince(began)
            HStack(spacing: DockMetrics.dotSpacing) {
                ForEach(0..<DockMetrics.dotCount, id: \.self) { index in
                    let lift = motion.workingDotsMove ? Self.lift(elapsed, index) : Self.stillLift
                    Circle()
                        .fill(Color.dockActive)
                        .frame(width: DockMetrics.dotSize, height: DockMetrics.dotSize)
                        .scaleEffect(0.72 + 0.28 * lift)
                        .opacity(0.34 + 0.66 * lift)
                }
            }
        }
        .frame(width: DockMetrics.meterWidth, height: DockMetrics.meterHeight)
    }

    /// How lit this dot is, 0 at rest and 1 at its brightest, each one a little behind the last.
    static func lift(_ elapsed: TimeInterval, _ index: Int) -> Double {
        var phase = ((elapsed - Double(index) * Self.stagger) / Self.cycle)
            .truncatingRemainder(dividingBy: 1)
        if phase < 0 { phase += 1 }
        return sin(phase * .pi)
    }

    /// How lit every dot is while Reduce Motion holds them still: fully, so the row still reads as working.
    static let stillLift = 1.0

    /// How long one walk across the three dots takes.
    private static let cycle = 1.05

    /// How far behind each dot follows the one to its left, which is what makes the walk read leftwards.
    private static let stagger = 0.16
}

/// A tick, drawn on the mark's own grid so its weight sits with everything around it.
private struct Tick: Shape {
    /// The mark's own 100-unit grid, which is what makes this stroke the same weight as the mark.
    private static let box = UttrflowMark.gridBox

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let originX = rect.midX - Self.box.midX * scale
        let originY = rect.midY - Self.box.midY * scale
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        // Short arm, a corner rather than a turn, then the long arm: the three points of a check.
        var path = Path()
        path.move(to: at(20, 54))
        path.addLine(to: at(42, 76))
        path.addLine(to: at(82, 26))
        return path
    }
}

/// Inserted: the tick drawn on, so the panel confirms in the one glyph everybody reads as done.
private struct MarkTick: View {
    @State private var drawn = false

    var body: some View {
        Tick()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(
                Color.dockSuccessInk,
                style: StrokeStyle(
                    lineWidth: UttrflowMark.lineWidth(forHeight: DockMetrics.markTickHeight),
                    lineCap: .round, lineJoin: .round)
            )
            .frame(
                width: DockMetrics.markTickHeight * UttrflowMark.aspectRatio,
                height: DockMetrics.markTickHeight
            )
            .task {
                withAnimation(.easeOut(duration: 0.26)) { drawn = true }
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
    static let meterHeight: CGFloat = 18
    /// Fixed rather than derived from a bar count: the row scrolls, so the width decides how many fit.
    static let meterWidth: CGFloat = 56
    /// The tallest a capsule gets, as a share of the meter's height; under one so it never touches the glass.
    static let meterAmplitude: CGFloat = 0.9
    /// How often a bar arrives — the rate the panel polls the microphone at.
    static let meterArrivalInterval: TimeInterval = 0.05
    /// How strongly a quiet bar is drawn; opacity carries the loud threshold. See Docs/app-dock.md.
    static let meterQuietOpacity: CGFloat = 0.62
    /// Where the row settles when the microphone closes; not zero, or the meter reads as broken.
    static let settledLevel: CGFloat = 0.18
    static let markTickHeight: CGFloat = 14

    /// The working dots: three, because that is the shape everybody already reads as "still going".
    static let dotCount = 3
    static let dotSize: CGFloat = 5
    static let dotSpacing: CGFloat = 6

    /// Draws the row for both the live meter and the working animation, so the two cannot drift apart.
    static func drawBars(
        _ levels: [CGFloat], in context: GraphicsContext, size: CGSize,
        phase: Double, towardsLeading: Bool
    ) {
        let step = meterBarWidth + meterBarSpacing
        let loud = GraphicsContext.Shading.color(.dockActive)
        let quiet = GraphicsContext.Shading.color(
            Color.dockWaveform.opacity(meterQuietOpacity))
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
    /// The translucent slab every form but the resting one is drawn on.
    fileprivate func glass(cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
            // Clipped and flattened before the shadow, or the material's rectangular backing leaks a square halo.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .compositingGroup()
            .shadow(color: .black.opacity(0.34), radius: 12, y: 5)
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
    /// The live accent: what is selected, what is running, the weight the meter hangs off.
    static let dockActive = Color(rgb: BrandPalette.Teal.primary)
    /// Ink for the mark inside the weight's disc; fixed, since the disc is the same teal in both appearances.
    static let dockWeightInk = Color(rgb: BrandPalette.Teal.inkOnDisc)
    static let dockSuccess = Color(rgb: BrandPalette.Semantic.success)
    static let dockWarning = Color(rgb: BrandPalette.Semantic.warning)
    /// The warning as text on the dock's glass, which the bright tone fails on a light desktop.
    static let dockWarningInk = Color(nsColor: .orbit(BrandPalette.Semantic.cautionInk))
    /// The failure disc under a white glyph.
    static let dockWarningFill = Color(rgb: BrandPalette.Semantic.warningFill)
    /// The tick on the dock's glass, deepened on a light desktop.
    static let dockSuccessInk = Color(nsColor: .orbit(BrandPalette.Semantic.successInk))

    /// The accent as text on a surface that follows the appearance; `dockAccent` is for fills.
    static let accentInk = Color(nsColor: .orbit(BrandPalette.Teal.ink))
    /// A warning as text; `dockWarning` is for dots, icons and fills.
    static let warningInk = Color(nsColor: .orbit(BrandPalette.Semantic.warningInk))
    /// Success as text; `dockSuccess` is for dots, icons and fills.
    static let successInk = Color(nsColor: .orbit(BrandPalette.Semantic.successInk))
    /// A failure as text; `dockRecording` is for dots, icons and fills.
    static let criticalInk = Color(nsColor: .orbit(BrandPalette.Semantic.criticalInk))

    /// The waveform teal, deepened on a light desktop where the bright one vanishes against the glass.
    static let dockWaveform = Color(nsColor: .orbit(BrandPalette.Teal.waveform))
}

extension LinearGradient {
    /// The accent as a filled control, deepened at the top so the fill reads as lit from above.
    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [Color(rgb: BrandPalette.Teal.deepLit), .dockAccent], startPoint: .top, endPoint: .bottom)
    }
}

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
            HStack(spacing: 8) {
                Text("Dictate")
                    .font(.system(size: DockMetrics.bodySize))
                keycap(model.shortcut)
            }
            .fixedSize()
            .padding(.horizontal, 15)
            .frame(height: DockMetrics.hintHeight)
            .glass(cornerRadius: DockMetrics.hintHeight / 2)
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

    /// Listening: the mark on the anchored edge and a live meter, with no words and no clock.
    private func listening() -> some View {
        compact { LevelMeterView(model: model, towardsLeading: $0) }
    }

    /// Working: the row the voice left behind, combing level and staying there until the words land.
    private func working() -> some View {
        compact { SettleView(bars: model.bars.levels, towardsLeading: $0) }
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

    /// Finished: a 26-point disc for the quiet outcomes, and the wide form for the one that needs an action.
    @ViewBuilder
    private func notice(_ presentation: DockPresentation, primaryLine: String) -> some View {
        switch presentation.symbolName {
        case "checkmark":
            badgeForm { MarkTick() }
        case "waveform.slash":
            badgeForm { StruckLevel() }
        case "doc.on.clipboard":
            clipboardNotice(presentation)
        default:
            blocked(presentation, primaryLine: primaryLine)
        }
    }

    /// The 26-point disc the quiet outcomes are drawn in.
    private func badgeForm(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: DockMetrics.badgeSize, height: DockMetrics.badgeSize)
            .glass(cornerRadius: DockMetrics.badgeSize / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    /// Copied rather than typed: ⌘V at rest, with the reason and the fix under the pointer.
    private func clipboardNotice(_ presentation: DockPresentation) -> some View {
        HStack(spacing: 8) {
            keycap("⌘V")
                .foregroundStyle(Color.dockWarning)
            if model.isHovering {
                Text("Typing is blocked — paste it")
                    .font(.system(size: DockMetrics.footnoteSize + 1))
                    .opacity(0.6)
                    .fixedSize()
                if let action = presentation.action {
                    Button("Fix") { onRecovery(action) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: DockMetrics.clipboardHeight)
        .glass(cornerRadius: DockMetrics.clipboardHeight / 2)
        .animation(.spring(duration: 0.26), value: model.isHovering)
        .padding(DockMetrics.gripHitPadding)
    }

    /// The one state with something for the reader to do, and the only wide form.
    private func blocked(_ presentation: DockPresentation, primaryLine: String) -> some View {
        HStack(spacing: 12) {
            Badge(symbolName: presentation.symbolName, tint: .dockWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: DockMetrics.bodySize, weight: .medium))
                    .lineLimit(1)
                if let secondary = presentation.secondaryLine {
                    Text(secondary)
                        .font(.system(size: DockMetrics.footnoteSize))
                        .opacity(0.58)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = presentation.action {
                Button(Self.title(for: action)) { onRecovery(action) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: DockMetrics.noticeMaxWidth, height: DockMetrics.noticeHeight)
        .glass(cornerRadius: DockMetrics.noticeHeight / 2)
        .padding(DockMetrics.gripHitPadding)
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
        case .pasteManually: "Paste"
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
    static let orbSize: CGFloat = 30
    /// Listening and working share this, so the panel cannot change shape when the key is released.
    static let compactHeight: CGFloat = 32
    static let weightSize: CGFloat = 22
    static let weightMarkHeight: CGFloat = 10
    /// The quiet outcomes — inserted, and nothing heard.
    static let badgeSize: CGFloat = 26
    static let clipboardHeight: CGFloat = 28
    /// The width of the one wide form, and of no other.
    static let noticeMaxWidth: CGFloat = 262
    static let noticeHeight: CGFloat = 40
    static let bodySize: CGFloat = 13
    static let footnoteSize: CGFloat = 10
}

// MARK: - Parts

/// The level as a row of capsules, redrawn every display frame and clipped so new bars enter from the edge.
private struct LevelMeterView: View {
    let model: DockViewModel
    /// Whether the mark is on the leading edge; sound always flows in from the side away from the mark.
    let towardsLeading: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
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
private struct SettleView: View {
    let bars: [CGFloat]
    let towardsLeading: Bool

    /// When this row appeared, so the settle and the bump that follows it share one clock.
    @State private var began = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                DockMetrics.drawBars(
                    levels(after: timeline.date.timeIntervalSince(began)),
                    in: context, size: size, phase: 1, towardsLeading: towardsLeading)
            }
        }
        .frame(width: DockMetrics.meterWidth, height: DockMetrics.meterHeight)
        .clipShape(.rect)
    }

    /// The row the voice left behind, easing level and then carrying a bump for as long as the work runs.
    private func levels(after elapsed: TimeInterval) -> [CGFloat] {
        let settle = min(max(elapsed / Self.settleSeconds, 0), 1)
        let travel = (elapsed / Self.sweepSeconds).truncatingRemainder(dividingBy: 1)
        let crest = travel * Double(bars.count + 2) - 1
        return bars.enumerated().map { index, level in
            let resting = level + (DockMetrics.settledLevel - level) * settle
            let bump = max(0, 1 - abs(Double(index) - crest)) * Self.bumpHeight * settle
            return resting + bump
        }
    }

    /// How long the voice's own row takes to level out.
    private static let settleSeconds = 0.34

    /// How long the bump takes to cross the row, slow enough to read as thinking rather than loading.
    private static let sweepSeconds = 1.15

    /// How far the bump lifts a settled bar, below the level that would read as speech.
    private static let bumpHeight = 0.42
}

/// One stroke that is the mark at 0 and a checkmark at 1; the arms splay open. See Docs/app-dock.md.
private struct MarkCheck: Shape {
    /// 0 is the mark, 1 is the checkmark.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The mark's own 100-unit grid, so both ends of the animation are the identity's geometry.
    private static let box = UttrflowMark.gridBox

    func path(in rect: CGRect) -> Path {
        let t = min(max(progress, 0), 1)
        let scale = min(rect.width / Self.box.width, rect.height / Self.box.height)
        let originX = rect.midX - Self.box.midX * scale
        let originY = rect.midY - Self.box.midY * scale
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }

        // The turn tightens from bowl to vertex and drops, because a check sits lower in its box.
        let radius = lerp(24, 6)
        let centre = CGPoint(x: 50, y: lerp(55, 64))
        let leftFoot = CGPoint(x: centre.x - radius, y: centre.y)
        let rightFoot = CGPoint(x: centre.x + radius, y: centre.y)

        // The arms swing out from vertical; the short one leans further.
        func arm(from foot: CGPoint, length: CGFloat, degrees: CGFloat) -> CGPoint {
            let radians = degrees * .pi / 180
            return CGPoint(
                x: foot.x - sin(radians) * length,
                y: foot.y - cos(radians) * length)
        }
        let leftEnd = arm(from: leftFoot, length: lerp(18, 16), degrees: lerp(0, 44))
        let rightEnd = arm(from: rightFoot, length: lerp(34, 44), degrees: lerp(0, -32))

        var path = Path()
        path.move(to: at(leftEnd.x, leftEnd.y))
        path.addLine(to: at(leftFoot.x, leftFoot.y))
        path.addArc(
            center: at(centre.x, centre.y), radius: radius * scale,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: at(rightEnd.x, rightEnd.y))
        return path
    }
}

/// Inserted: the mark opening into a check, so the brand does the confirming.
private struct MarkTick: View {
    @State private var isTick = false

    var body: some View {
        MarkCheck(progress: isTick ? 1 : 0)
            .stroke(
                isTick ? Color.dockSuccess : Color.dockActive,
                style: StrokeStyle(
                    lineWidth: UttrflowMark.lineWidth(forHeight: DockMetrics.markTickHeight),
                    lineCap: .round, lineJoin: .round)
            )
            .frame(
                width: DockMetrics.markTickHeight * UttrflowMark.aspectRatio,
                height: DockMetrics.markTickHeight
            )
            .task {
                withAnimation(.spring(duration: 0.44, bounce: 0.22)) { isTick = true }
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
            .frame(width: 22, height: 22)
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
            .shadow(color: .black.opacity(0.34), radius: 12, y: 5)
    }
}

// MARK: - Colours

extension Color {
    /// Fills that carry text, capped at 29% lightness so white 13-point text clears 4.5:1.
    static let dockAccent = Color(rgb: 0x12_8077)
    /// Controls and graphics with no text on them.
    static let dockAccentLight = Color(rgb: 0x39_D0C4)
    static let dockAccentTint = Color(rgb: 0x9E_DCD7)
    static let dockAccentWash = Color(rgb: 0xEF_F8F7)
    /// Recording and destructive: the main window's critical tone and its destructive buttons.
    static let dockRecording = Color(rgb: 0xFF_383C)
    /// The live accent: what is selected, what is running, the weight the meter hangs off.
    static let dockActive = Color(rgb: 0x29_C0B4)
    /// Ink for the mark inside the weight's disc; fixed, since the disc is the same teal in both appearances.
    static let dockWeightInk = Color(rgb: 0x04_100F)
    static let dockSuccess = Color(rgb: 0x34_C759)
    static let dockWarning = Color(rgb: 0xFF_8D28)

    /// The waveform teal, deepened on a light desktop where the bright one vanishes against the glass.
    static let dockWaveform = Color(nsColor: .orbit(dark: 0x00_C3D0, light: 0x06_7A87))
}

extension LinearGradient {
    /// The accent as a filled control, deepened at the top so the fill reads as lit from above.
    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [Color(rgb: 0x17_968C), .dockAccent], startPoint: .top, endPoint: .bottom)
    }
}

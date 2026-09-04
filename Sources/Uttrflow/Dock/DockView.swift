import AppKit
import UttrflowCore
import UttrflowPipeline
import SwiftUI

/// What the panel is currently showing, in one place the view can watch.
///
/// Hover and press live here rather than in `@State` because AppKit is what notices
/// them: SwiftUI's own hover tracking is scoped to the active application, and this
/// panel is only ever pointed at while some other app is frontmost.
@MainActor
@Observable
final class DockViewModel {
    var presentation: DockPresentation
    /// How the shortcut reads on a keycap, for example "⌥Space".
    var shortcut: String
    /// Which edge the button is parked on. The view needs it so the button itself
    /// stays nearest that edge as the form around it grows.
    var anchor: DockAnchor
    var isHovering = false
    var isPressed = false
    /// How loud the microphone is right now, in `0...1`, as root mean square.
    ///
    /// Written by the controller at 20 Hz while a recording is open and left at zero
    /// otherwise. It is deliberately not part of ``DockPresentation``: the presentation
    /// is what the pipeline's state *means*, is pure, and is covered by tests that would
    /// have to be rewritten to accommodate a number that changes twenty times a second
    /// and means nothing on its own.
    var level: Float = 0
    /// The row of capsules, one per arrival, newest first.
    private(set) var bars = DockBars()
    /// When the newest bar landed, so the row can be drawn *between* arrivals.
    ///
    /// Twenty arrivals a second drawn on arrival is twenty sideways jumps a second, and
    /// it reads as stepping rather than flowing. Holding the moment lets the view place
    /// the bars at a fractional offset on every display frame instead.
    private(set) var lastArrival = Date()

    /// One arrival: the level the microphone reported, and one more capsule.
    func meter(_ level: Float, now: Date = Date()) {
        self.level = level
        bars.arrive(DockLevel.scale(rms: level))
        lastArrival = now
    }
    /// When the current recording started, for the clock on the pill.
    ///
    /// Stamped here rather than carried in the presentation because it is a fact about
    /// this run of the app rather than about the state: the pipeline knows it is
    /// recording, and the wall clock is the window's business. Kept across redraws so
    /// the clock does not restart every time the presentation is handed over again.
    private(set) var recordingStartedAt: Date?
    /// Whether the idle button collapses to a grip, from "Shrink it to a grip until I
    /// point at it".
    ///
    /// The switch existed and nothing read it: the button always shrank, whichever way it
    /// was set. Somebody who wants the button findable without hunting for a sliver at
    /// the edge of the screen was told they could have that, and could not.
    var shrinksToGrip = true

    /// The only way the presentation changes, so the clock cannot be forgotten.
    ///
    /// It starts on the first presentation that is recording and is cleared by the first
    /// that is not — a run of identical recording presentations, which is what arrives
    /// while somebody holds the key, leaves it exactly where it was.
    func show(_ presentation: DockPresentation, now: Date = Date()) {
        if presentation.isRecording {
            // Cleared as a recording begins rather than as one ends: the working
            // animation settles the row the voice actually left behind, so the bars have
            // to outlive the microphone by exactly one state.
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

/// The floating button, in whichever form the current state calls for.
///
/// Every form is derived from ``DockPresentation`` and nothing else. The view has no
/// opinion about what the pipeline is doing; if two forms could disagree about that,
/// the disagreement would have to be settled here rather than in one testable place.
struct DockView: View {
    let model: DockViewModel
    var onPressBegan: () -> Void = {}
    var onPressEnded: () -> Void = {}
    var onRecovery: (RecoveryAction) -> Void = { _ in }
    /// The size the current form wants. The panel is resized to match, so the resting
    /// grip claims no more of the screen — or of the pointer — than a grip should.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var body: some View {
        form
            .fixedSize()
            .scaleEffect(model.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.22), value: model.isPressed)
            .contentShape(.rect)
            // Held at the root rather than on the button itself: the form changes
            // shape the instant recording starts, and a gesture attached to a view
            // that has just been replaced would never see the mouse come back up.
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

    /// Always there, ignorable: three dots at the edge of the screen.
    ///
    /// Drawn straight onto the desktop, with no slab under them. Every other form is
    /// built on ``glass(cornerRadius:)``, and around a pill that reads as depth — but
    /// around nine points of dots, its hairline and its shadow at radius 12 read as a
    /// box somebody forgot to delete. The hit target does not come from the slab: the
    /// invisible padding below and the `.contentShape(.rect)` at the root are what make
    /// this pointable, and both are still here.
    private var resting: some View {
        VStack(spacing: DockMetrics.gripDotSpacing) {
            ForEach(0..<DockMetrics.gripDotCount, id: \.self) { _ in
                Circle()
                    .fill(.primary.opacity(0.6))
                    .frame(width: DockMetrics.gripDotSize, height: DockMetrics.gripDotSize)
            }
        }
        .frame(width: DockMetrics.gripWidth, height: DockMetrics.gripHeight)
        // The one thing the slab was doing that was worth keeping: three points of ink
        // are invisible on a pale wallpaper without something to lift them off it.
        .shadow(color: .black.opacity(0.38), radius: 1.5, y: 0.5)
        // A nine-point strip is a hard thing to put a pointer on. The padding is
        // invisible but hoverable, which is the whole job of the resting form.
        .padding(DockMetrics.gripHitPadding)
    }

    /// Pointed at: a reminder of the key, and the button itself.
    ///
    /// The orb keeps the side the grip was on, so growing a hint beside it does not
    /// shift the thing the pointer is already over out from under the pointer.
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

    /// Listening: the mark as a weight on the anchored edge, and the level beside it.
    ///
    /// No words and no clock. What somebody holding a key down needs to know is that
    /// they are being heard, and a meter that is actually driven by their voice says
    /// that better than a sentence does — while a red light, seventeen bars, a running
    /// clock and "Let go to finish" all saying it at once is how the old panel came to
    /// need 286 points. The sentence survives in the accessibility label, which is read
    /// by exactly the people who cannot see the meter.
    private func listening() -> some View {
        let weightLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if weightLeads { weight() }
            LevelMeterView(model: model, towardsLeading: weightLeads)
            if !weightLeads { weight() }
        }
        .padding(.leading, weightLeads ? 5 : 12)
        .padding(.trailing, weightLeads ? 12 : 5)
        .frame(height: DockMetrics.compactHeight)
        .glass(cornerRadius: DockMetrics.compactHeight / 2)
        .padding(DockMetrics.gripHitPadding)
    }

    /// Working: the row the voice left behind, combing itself level and folding to a tick.
    ///
    /// Same footprint as listening, deliberately. The old form was a band of light
    /// crossing a track on an infinite loop, which is the animation of a wait with no
    /// end — and this one is about a second and always ends.
    private func working() -> some View {
        let weightLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if weightLeads { weight() }
            SettleView(bars: model.bars.levels, towardsLeading: weightLeads)
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
            .background(Color.dockSecondary, in: .circle)
    }

    // MARK: - Notices

    /// Finished, one way or the other.
    ///
    /// Which form is chosen follows the symbol the presenter picked, the same way the
    /// badge tint already did — so a new state cannot arrive wearing the wrong shape.
    ///
    /// Three of the four are a 26-point disc, because a success needs no words: when the
    /// text has landed in the document, a panel repeating it is narrating something the
    /// reader is already looking at. Only the fourth has something to *do* about it, and
    /// that one stays wide on purpose.
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

    /// Copied rather than typed: the two characters that are the whole instruction,
    /// and the reason only if it is asked for.
    ///
    /// This is a failure wearing a success's clothes — the words exist but nobody typed
    /// them — so it is amber rather than green, and it is the one quiet form that can
    /// still be acted on. Putting the explanation behind the pointer is what lets it be
    /// small: 64 points at rest, and the full sentence and the fix for anybody who goes
    /// looking.
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

    /// The one state with something for the reader to do, and the only wide one left.
    ///
    /// Shrinking this too would spend the contrast the other three just bought: after a
    /// run of 26-point discs, a panel that arrives at 262 points is unmistakably asking
    /// for something.
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
    /// Three dots, not five. Twelve points shorter than it was, and the sliver at the
    /// edge of the screen is a third smaller for it.
    static let gripHeight: CGFloat = 34
    static let gripDotSize: CGFloat = 3
    static let gripDotSpacing: CGFloat = 3
    static let gripDotCount = 3
    /// Invisible, hoverable margin around every form, and the room the shadow needs.
    static let gripHitPadding: CGFloat = 6
    static let hintHeight: CGFloat = 30
    static let orbSize: CGFloat = 30
    /// Listening and working, which must be identical: the panel cannot change shape at
    /// the moment the key is released.
    static let compactHeight: CGFloat = 32
    static let weightSize: CGFloat = 22
    static let weightMarkHeight: CGFloat = 10
    /// The quiet outcomes — inserted, and nothing heard.
    static let badgeSize: CGFloat = 26
    static let clipboardHeight: CGFloat = 28
    /// The one state still allowed to be wide, and the width it is allowed.
    ///
    /// Was `pillWidth`, and was applied to *every* form: listening was 286 points wide
    /// because a 60-character transcript preview and a recovery button need 286 points,
    /// and paid that on every dictation for a state it never entered.
    static let noticeMaxWidth: CGFloat = 262
    static let noticeHeight: CGFloat = 40
    static let bodySize: CGFloat = 13
    static let footnoteSize: CGFloat = 10
}

// MARK: - Parts

/// The level, as a row of capsules walking across the panel.
///
/// Two teals the app already owns and no third: a bar louder than half scale takes the
/// mark's accent, the rest keep the waveform teal. Redrawn every display frame rather
/// than on every arrival — see ``DockViewModel/lastArrival`` for why — and clipped, so
/// the newest bar enters from beyond the edge instead of appearing at it.
private struct LevelMeterView: View {
    let model: DockViewModel
    /// Whether the mark sits on the leading edge. Sound always arrives at the side
    /// *away* from the mark and flows into it, so on the default right-hand anchor that
    /// reads left to right, and on a left-hand anchor it mirrors along with the rest of
    /// the pill rather than becoming a second design.
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

/// Working: the row the voice left behind, combing itself level and folding to a tick.
///
/// It plays once and resolves, which is the whole difference from what it replaces. A
/// loop says *indefinite* — it is the animation of a download with no progress bar — and
/// tidying up a sentence takes about a second and always ends. It also stops scrolling:
/// nothing is arriving any more, and a row still walking would say otherwise.
private struct SettleView: View {
    let bars: [CGFloat]
    let towardsLeading: Bool

    @State private var progress: CGFloat = 0

    var body: some View {
        let settle = min(progress / 0.5, 1)
        let fold = max((progress - 0.5) / 0.5, 0)

        return ZStack {
            Canvas { context, size in
                let levelled = bars.map { $0 + (DockMetrics.settledLevel - $0) * settle }
                DockMetrics.drawBars(
                    levelled, in: context, size: size,
                    phase: 1, towardsLeading: towardsLeading)
            }
            .scaleEffect(x: 1 - fold * 0.92)
            .opacity(1 - Double(fold))

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dockSuccess)
                .scaleEffect(0.2 + fold * 0.8)
                .opacity(Double(fold))
        }
        .frame(width: DockMetrics.meterWidth, height: DockMetrics.meterHeight)
        .clipShape(.rect)
        .task {
            withAnimation(.easeOut(duration: 0.34)) { progress = 0.5 }
            try? await Task.sleep(for: .milliseconds(340))
            withAnimation(.spring(duration: 0.3, bounce: 0.34)) { progress = 1 }
        }
    }
}

/// The mark and a checkmark, and the road between them.
///
/// Both are one round-capped stroke: a short arm, a turn at the bottom, a long arm. The
/// only differences are how wide the turn is and how far the arms are splayed — so the
/// `u` becomes a check by *opening*, and confirming an insertion needs no second glyph.
///
/// Rotating the mark does not do this, which is worth writing down because it is the
/// obvious thing to try and it looks nearly right in a description. The mark's two arms
/// are parallel, and a rotated pair of parallel arms is a hook, not a tick. They have to
/// come apart.
private struct MarkCheck: Shape {
    /// 0 is the mark, 1 is the checkmark.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Drawn on the mark's own 100-unit grid, so both ends of the animation are the
    /// identity's geometry rather than an approximation of it.
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

        // The turn tightens from the mark's bowl to a checkmark's vertex, and drops as
        // it does so, because a check sits lower in its box than a u does.
        let radius = lerp(24, 6)
        let centre = CGPoint(x: 50, y: lerp(55, 64))
        let leftFoot = CGPoint(x: centre.x - radius, y: centre.y)
        let rightFoot = CGPoint(x: centre.x + radius, y: centre.y)

        // And the arms swing out from vertical. The short one leans further: a
        // checkmark's short arm is the steeper of the two.
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

/// Inserted: the mark opening into a check.
///
/// Turning the identity into the confirmation, rather than swapping in a system
/// `checkmark`, is the difference between the brand doing the confirming and an icon
/// doing it — and it costs the same 26 points either way.
private struct MarkTick: View {
    @State private var isTick = false

    var body: some View {
        MarkCheck(progress: isTick ? 1 : 0)
            .stroke(
                isTick ? Color.dockSuccess : Color.dockSecondary,
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

/// Nothing heard: a level with a line through it.
///
/// No red, no warning triangle and no sentence. Nothing went wrong — the microphone was
/// open and there was nothing in it — and drawing that costs the same 26 points as
/// drawing success.
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
    /// Fixed rather than derived from a bar count: the row scrolls, so how many bars fit
    /// is a consequence of the width rather than the other way round.
    static let meterWidth: CGFloat = 56
    /// The tallest a capsule gets, as a share of the meter's height. Under one, so a
    /// loud syllable still has air above and below it rather than touching the glass.
    static let meterAmplitude: CGFloat = 0.9
    /// How often a bar arrives — the rate the panel polls the microphone at.
    static let meterArrivalInterval: TimeInterval = 0.05
    /// How strongly a bar below the accent threshold is drawn.
    ///
    /// The two teals cannot carry the threshold on their own. On a light desktop the
    /// pair is `#067A87` against `#29C0B4` and separates at 2.24:1, which reads. On a
    /// dark one the waveform teal lightens to `#00C3D0` and the pair collapses to
    /// **1.05:1** — and inverts, because the accent is then the fractionally *darker*
    /// of the two. A threshold nobody can see on the ground most desktops actually use
    /// is not a threshold.
    ///
    /// So the hue keeps its job and weight is added beside it: quiet bars sit back,
    /// loud ones come forward. It introduces no colour the app does not already own,
    /// and it works on both grounds because opacity does not depend on either.
    static let meterQuietOpacity: CGFloat = 0.62
    /// Where the row settles to when the microphone closes. Not zero: a row of dots
    /// still reads as a meter, and a row of nothing reads as a panel that has broken.
    static let settledLevel: CGFloat = 0.18
    static let markTickHeight: CGFloat = 14

    /// Draws the row, in the one place both the live meter and the working animation
    /// can reach it — so the panel cannot change shape at the moment the key is released
    /// by the two of them drifting apart.
    static func drawBars(
        _ levels: [CGFloat], in context: GraphicsContext, size: CGSize,
        phase: Double, towardsLeading: Bool
    ) {
        let step = meterBarWidth + meterBarSpacing
        let loud = GraphicsContext.Shading.color(.dockSecondary)
        let quiet = GraphicsContext.Shading.color(
            Color.dockWaveform.opacity(meterQuietOpacity))
        for (index, level) in levels.enumerated() {
            // One step before the panel starts, so the newest bar enters from beyond the
            // edge and is clipped rather than appearing out of nothing at it.
            let offset = (CGFloat(index) + CGFloat(phase) - 1) * step
            let x = towardsLeading ? size.width - offset - meterBarWidth : offset
            guard x < size.width, x > -step else { continue }
            // A quiet bar is a dot rather than a stub: at this width the cap radius is
            // the whole bar, so the floor may as well be the shape it is heading for.
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
    /// Fills that carry text. Capped at 29% lightness so white 13-point text clears
    /// 4.5:1 against it — the mark's own teal is lighter than that and never carries text.
    static let dockAccent = Color(.sRGB, red: 0x12 / 255, green: 0x80 / 255, blue: 0x77 / 255)
    /// Controls and graphics with no text on them.
    static let dockAccentLight = Color(
        .sRGB, red: 0x39 / 255, green: 0xD0 / 255, blue: 0xC4 / 255)
    static let dockAccentTint = Color(
        .sRGB, red: 0x9E / 255, green: 0xDC / 255, blue: 0xD7 / 255)
    static let dockAccentWash = Color(
        .sRGB, red: 0xEF / 255, green: 0xF8 / 255, blue: 0xF7 / 255)
    /// Recording, and destructive. The floating button no longer lights it — the meter
    /// says it is listening better than a red dot beside a meter did — but the main
    /// window's critical tone and its destructive buttons are the same red, and this is
    /// still where the whole app's accent ramp is written down.
    static let dockRecording = Color(
        .sRGB, red: 0xFF / 255, green: 0x38 / 255, blue: 0x3C / 255)
    /// The live one: what is selected, what is running, the weight the meter hangs off.
    ///
    /// Named "secondary" from when the brand was purple and this was the foil to it, but
    /// every one of its uses is a state rather than a counterpoint — so it is the mark's
    /// own teal, lightened until it holds on a dark desktop, and not a second hue. The
    /// identity has one accent, and this is it.
    static let dockSecondary = Color(
        .sRGB, red: 0x29 / 255, green: 0xC0 / 255, blue: 0xB4 / 255)
    /// The mark drawn *inside* the weight, which is a teal disc — so it is the ink, not
    /// the accent. Fixed rather than `.primary`: the disc is the same teal in both
    /// appearances, so ink that followed the appearance would vanish in one of them.
    static let dockWeightInk = Color(.sRGB, red: 0x04 / 255, green: 0x10 / 255, blue: 0x0F / 255)
    static let dockSuccess = Color(.sRGB, red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let dockWarning = Color(.sRGB, red: 0xFF / 255, green: 0x8D / 255, blue: 0x28 / 255)

    /// The bars sit on frosted glass, which takes its lightness from the desktop
    /// behind it. The bright teal vanishes against a light one, so it deepens there.
    static let dockWaveform = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0x00 / 255, green: 0xC3 / 255, blue: 0xD0 / 255, alpha: 1)
                : NSColor(srgbRed: 0x06 / 255, green: 0x7A / 255, blue: 0x87 / 255, alpha: 1)
        })
}

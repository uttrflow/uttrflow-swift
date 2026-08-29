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
            recordingStartedAt = recordingStartedAt ?? now
        } else {
            recordingStartedAt = nil
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
            listening(presentation)
        } else if presentation.showsProgress {
            processing(presentation)
        } else if let line = presentation.primaryLine {
            notice(presentation, primaryLine: line)
        } else if model.isHovering || !model.shrinksToGrip {
            hovered(presentation)
        } else {
            resting
        }
    }

    /// Always there, ignorable: a grip at the edge of the screen.
    private var resting: some View {
        VStack(spacing: DockMetrics.gripDotSpacing) {
            ForEach(0..<DockMetrics.gripDotCount, id: \.self) { _ in
                Circle()
                    .fill(.primary.opacity(0.5))
                    .frame(width: DockMetrics.gripDotSize, height: DockMetrics.gripDotSize)
            }
        }
        .frame(width: DockMetrics.gripWidth, height: DockMetrics.gripHeight)
        .glass(cornerRadius: DockMetrics.gripRadius)
        // A nine-point strip is a hard thing to put a pointer on. The padding is
        // invisible but hoverable, which is the whole job of the resting form.
        .padding(DockMetrics.gripHitPadding)
    }

    /// Pointed at: a reminder of the key, and the button itself.
    ///
    /// The orb keeps the side the grip was on, so growing a hint beside it does not
    /// shift the thing the pointer is already over out from under the pointer.
    private func hovered(_ presentation: DockPresentation) -> some View {
        let orbLeads = model.anchor == .bottomLeft
        return HStack(spacing: 9) {
            if orbLeads { orb(presentation) }
            HStack(spacing: 8) {
                Text("Dictate")
                    .font(.system(size: DockMetrics.bodySize))
                keycap(model.shortcut)
            }
            .fixedSize()
            .padding(.horizontal, 15)
            .frame(height: DockMetrics.hintHeight)
            .glass(cornerRadius: DockMetrics.hintHeight / 2)
            if !orbLeads { orb(presentation) }
        }
        .padding(DockMetrics.gripHitPadding)
    }

    private func orb(_ presentation: DockPresentation) -> some View {
        Image(systemName: presentation.symbolName)
            .font(.system(size: 19, weight: .regular))
            .frame(width: DockMetrics.orbSize, height: DockMetrics.orbSize)
            .glass(cornerRadius: DockMetrics.orbSize / 2)
    }

    /// Listening: the recording light, the bars, how long it has been open, and how to
    /// stop.
    ///
    /// The clock is the one thing here somebody cannot see for themselves. A held key has
    /// no edges — four seconds and fourteen feel the same — and a recording that is
    /// quietly still running is the failure this button exists to make impossible.
    private func listening(_ presentation: DockPresentation) -> some View {
        pill {
            if presentation.isRecording {
                RecordingDot()
            }
            WaveformView()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let startedAt = model.recordingStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                    Text(
                        DictationPresenter.elapsed(
                            .seconds(timeline.date.timeIntervalSince(startedAt)))
                    )
                    .font(.system(size: DockMetrics.bodySize, weight: .medium))
                    .monospacedDigit()
                }
            }
            if let line = presentation.primaryLine {
                Rectangle()
                    .fill(.primary.opacity(0.16))
                    .frame(width: 1, height: 16)
                Text(line)
                    .font(.system(size: DockMetrics.footnoteSize))
                    .opacity(0.55)
                    .fixedSize()
            }
        }
    }

    /// Processing: about a second, so a bar that moves rather than a number.
    private func processing(_ presentation: DockPresentation) -> some View {
        pill {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.dockAccent)
            VStack(alignment: .leading, spacing: 7) {
                if let line = presentation.primaryLine {
                    Text(line)
                        .font(.system(size: DockMetrics.bodySize, weight: .medium))
                }
                ShimmerBar()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Finished, one way or the other: what happened, and what can be done about it.
    private func notice(_ presentation: DockPresentation, primaryLine: String) -> some View {
        pill {
            Badge(symbolName: presentation.symbolName, tint: badgeTint(for: presentation))
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
    }

    // MARK: - Pieces

    private func pill(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 18)
            .frame(width: DockMetrics.pillWidth, height: DockMetrics.pillHeight)
            .glass(cornerRadius: DockMetrics.pillHeight / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DockMetrics.footnoteSize, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(.primary.opacity(0.14), in: .rect(cornerRadius: 5))
    }

    /// The badge follows the symbol the presenter chose, so a new state cannot arrive
    /// wearing the wrong colour.
    private func badgeTint(for presentation: DockPresentation) -> Color {
        switch presentation.symbolName {
        case "checkmark": .dockSuccess
        case "exclamationmark.triangle": .dockWarning
        default: .dockAccent
        }
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
        }
    }
}

// MARK: - Sizes

/// The measurements the design is drawn to.
enum DockMetrics {
    static let gripWidth: CGFloat = 9
    static let gripHeight: CGFloat = 46
    static let gripRadius: CGFloat = 5
    static let gripDotSize: CGFloat = 3
    static let gripDotSpacing: CGFloat = 3
    static let gripDotCount = 5
    /// Invisible, hoverable margin around every form, and the room the shadow needs.
    static let gripHitPadding: CGFloat = 6
    static let hintHeight: CGFloat = 34
    static let orbSize: CGFloat = 44
    static let pillWidth: CGFloat = 286
    static let pillHeight: CGFloat = 52
    static let bodySize: CGFloat = 13
    static let footnoteSize: CGFloat = 10
}

// MARK: - Parts

/// The recording light. Lit, not blinking: a blink in the corner of the eye reads as a
/// warning, and nothing is wrong.
private struct RecordingDot: View {
    var body: some View {
        Circle()
            .fill(Color.dockRecording)
            .frame(width: 9, height: 9)
            .background(
                Circle()
                    .fill(Color.dockRecording.opacity(0.22))
                    .frame(width: 17, height: 17))
    }
}

/// Bars that move while the microphone is live.
///
/// Not driven by the real signal: the level would have to cross an actor boundary
/// sixty times a second to say something the user already knows. What this has to
/// convey is that the app is still listening.
private struct WaveformView: View {
    @State private var isAnimating = false

    private static let heights: [CGFloat] = [
        7, 13, 20, 11, 24, 16, 9, 18, 22, 12, 6, 15, 21, 10, 8, 17, 11,
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(Color.dockWaveform)
                    .frame(width: 3, height: height)
                    .scaleEffect(y: isAnimating ? 0.32 : 1, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.36 + Double(index % 5) * 0.09)
                            .repeatForever(autoreverses: true),
                        value: isAnimating)
            }
        }
        .frame(height: 26)
        .opacity(0.9)
        .onAppear { isAnimating = true }
    }
}

/// A band of light crossing a track, for a wait too short to measure.
private struct ShimmerBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dockAccentLight.opacity(0), .dockAccentLight, .dockSecondary,
                        ],
                        startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: travel * 0.45)
                .offset(x: isAnimating ? travel : -travel * 0.45)
                .animation(
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: false),
                    value: isAnimating)
        }
        .frame(height: 6)
        .background(.primary.opacity(0.16), in: .capsule)
        .clipShape(.capsule)
        .onAppear { isAnimating = true }
    }
}

/// The round mark beside a finished result.
private struct Badge: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white))
    }
}

// MARK: - Material

extension View {
    /// The translucent slab every form is drawn on.
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
    /// The live one: what is selected, what is running, the lit end of the waveform.
    ///
    /// Named "secondary" from when the brand was purple and this was the foil to it, but
    /// every one of its uses is a state rather than a counterpoint — so it is the mark's
    /// own teal, lightened until it holds on a dark desktop, and not a second hue. The
    /// identity has one accent, and this is it.
    static let dockSecondary = Color(
        .sRGB, red: 0x29 / 255, green: 0xC0 / 255, blue: 0xB4 / 255)
    static let dockRecording = Color(
        .sRGB, red: 0xFF / 255, green: 0x38 / 255, blue: 0x3C / 255)
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

// The floating button: its view model and the view that picks which form to draw.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

/// The notice's text and surface strengths follow Increase Contrast together.
struct DockNoticeAppearance: Equatable {
    let increasedContrast: Bool

    var usesOpaqueGlass: Bool { increasedContrast }

    func textOpacity(normal: Double) -> Double { increasedContrast ? 1 : normal }
}

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
    var isAccessibilityFocused = false
    var isEngaged: Bool { isHovering || isAccessibilityFocused }
    var isPressed = false
    var increasesContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    /// Microphone loudness in `0...1` as RMS, written at 20 Hz while recording; not part of the presentation.
    var level: Float = 0
    /// The row of capsules, one per arrival, newest first.
    private(set) var bars = DockBars()
    /// When the newest bar landed, so the view places bars at a fractional offset between arrivals.
    private(set) var lastArrival = Date()

    /// Whether this recording's input has stayed below the floor the silence refusal applies.
    private(set) var silence = InputSilence()

    /// One arrival: the level the microphone reported, and one more capsule; `true` when the input just went silent.
    @discardableResult
    func meter(_ level: Float, now: Date = Date()) -> Bool {
        self.level = level
        bars.arrive(DockLevel.scale(rms: level))
        lastArrival = now
        return silence.read(level, at: now.timeIntervalSinceReferenceDate)
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
                silence = InputSilence()
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
    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    let model: DockViewModel
    var onPressBegan: () -> Void = {}
    var onPressEnded: () -> Void = {}
    /// Starts or finishes a dictation in one go, for a caller that cannot hold the button down.
    var onToggle: () -> Void = {}
    var onRecovery: (RecoveryAction) -> Void = { _ in }
    var onAttentionChange: (Bool) -> Void = { _ in }
    /// The size the current form wants; the panel is resized to match, so a grip claims no more screen.
    var onDesiredSize: (CGSize) -> Void = { _ in }

    var noticeAppearance: DockNoticeAppearance {
        DockNoticeAppearance(increasedContrast: model.increasesContrast)
    }

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
            .accessibilityValue(
                model.presentation.isRecording && model.silence.isSilent
                    ? InputSilence.line
                    : DockWording.spokenValue(for: model.presentation)
            )
            .accessibilityHint(DockWording.spokenHint(for: model.presentation))
            .accessibilityAddTraits(.isButton)
            .accessibilityFocused($isAccessibilityFocused)
            .onChange(of: isAccessibilityFocused) { _, focused in
                model.isAccessibilityFocused = focused
                onAttentionChange(focused)
            }
            // A press-and-hold is not a gesture VoiceOver can perform, so activating toggles instead.
            .accessibilityAction { onToggle() }
            .accessibilityActions {
                // The recovery the failure draws, spoken; its own button is inside the ignored children.
                if let action = model.presentation.action {
                    Button(DockWording.title(for: action, in: model.presentation)) { onRecovery(action) }
                }
            }
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
}

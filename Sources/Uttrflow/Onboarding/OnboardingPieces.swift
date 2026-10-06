// The parts of the onboarding card: round buttons, the pointer, badges, the field, keycaps, the ring and the dots.

import AppKit
import SwiftUI
import UttrflowAccount
import UttrflowUX

/// A round button with its word under it: white when it is the answer, glass otherwise.
struct OnboardingRoundButton<Mark: View>: View {
    let title: String
    let isProminent: Bool
    var isEnabled = true
    var isPointedAt = false
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(isProminent ? Color.white : Color.white.opacity(0.1))
                    .overlay {
                        Circle().strokeBorder(
                            .white.opacity(isSelected ? 0.9 : 0.18), lineWidth: isSelected ? 2 : 1)
                    }
                    .overlay { mark().foregroundStyle(isProminent ? OnboardingInk.onWhite : .white) }
                    .frame(width: OnboardingMetrics.roundSize, height: OnboardingMetrics.roundSize)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 12)
                Text(title)
                    .font(.system(size: isPointedAt ? 13 : 12, weight: isPointedAt ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(isPointedAt ? 1 : 0.75))
            }
            .contentShape(.rect)
        }
        .buttonStyle(OnboardingPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(!isEnabled)
        .keyboardShortcut(isProminent && isEnabled ? .defaultAction : nil)
        .opacity(isEnabled ? 1 : 0.35)
        .overlay(alignment: .topLeading) {
            if isPointedAt { OnboardingPointer().offset(x: 78, y: -4) }
        }
    }
}

/// Dims a round button while it is held down.
struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.78 : 1)
    }
}

/// The hand-drawn arrow and "click here" beside the one button a page cannot do without.
struct OnboardingPointer: View {
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Canvas { context, _ in
                var arrow = Path()
                arrow.move(to: CGPoint(x: 38, y: 6))
                arrow.addCurve(
                    to: CGPoint(x: 6, y: 26), control1: CGPoint(x: 26, y: 2), control2: CGPoint(x: 12, y: 8))
                arrow.move(to: CGPoint(x: 2, y: 18))
                arrow.addLine(to: CGPoint(x: 6, y: 27))
                arrow.addLine(to: CGPoint(x: 14, y: 22))
                context.stroke(
                    arrow, with: .color(OnboardingInk.glow),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 40, height: 34)
            Text("click here")
                .font(BrandFont.display(size: 13, weight: .medium))
                .foregroundStyle(OnboardingInk.glow)
                .offset(y: -6)
                .fixedSize()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A provider's mark, fetched rather than redrawn and possibly absent; see `Docs/app-onboarding.md`.
struct OnboardingProviderMark: View {
    let provider: SignInProvider
    let size: CGFloat

    var body: some View {
        if provider == .google, let mark = Bundle.module.image(forResource: "GoogleG") {
            Image(nsImage: mark)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if provider == .apple {
            Image(systemName: "apple.logo").font(.system(size: size * 0.9))
        } else {
            Image(systemName: "person.fill").font(.system(size: size * 0.8))
        }
    }
}

/// The disc over the waveform: a provider inside a turning arc, or a symbol on a toned disc.
struct OnboardingBadgeView: View {
    let badge: OnboardingBadge
    @State private var shaken = 0.0

    var body: some View {
        switch badge {
        case .waitingOn(let provider):
            ZStack {
                OnboardingSpinner().frame(width: 64, height: 64)
                Circle().fill(.white).frame(width: 46, height: 46)
                OnboardingProviderMark(provider: provider, size: 24)
                    .foregroundStyle(OnboardingInk.onWhite)
            }
        case .symbol(let name, let tone):
            Image(systemName: name)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tone == .caution ? OnboardingInk.caution : .white)
                .frame(width: 56, height: 56)
                .background(ground(tone), in: .circle)
                .overlay { Circle().strokeBorder(edge(tone), lineWidth: 1) }
                .shadow(
                    color: tone == .failure ? OnboardingInk.failureShadow.opacity(0.45) : .clear, radius: 12,
                    y: 10
                )
                .modifier(OnboardingShake(travel: shaken))
                .onAppear {
                    // No shake under Reduce Motion; the failure's colour and words still say it.
                    guard tone == .failure, !MotionBudget.current().reducesMotion else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { shaken = 1 }
                }
        }
    }

    private func ground(_ tone: OnboardingBadgeTone) -> AnyShapeStyle {
        switch tone {
        case .neutral: AnyShapeStyle(Color(rgb: BrandPalette.Onboarding.badgeGround).opacity(0.85))
        case .caution: AnyShapeStyle(Color(rgb: BrandPalette.Onboarding.cautionBadgeGround).opacity(0.85))
        case .failure:
            AnyShapeStyle(
                LinearGradient(
                    colors: [OnboardingInk.failureLit, Color(rgb: BrandPalette.Onboarding.failureDeep)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func edge(_ tone: OnboardingBadgeTone) -> Color {
        switch tone {
        case .neutral: .white.opacity(0.2)
        case .caution: OnboardingInk.caution.opacity(0.6)
        case .failure: .clear
        }
    }
}

/// Two shakes left and right as `travel` runs from 0 to 1, for a badge that reports a failure.
struct OnboardingShake: GeometryEffect {
    var travel: Double

    var animatableData: Double {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 4 * sin(travel * .pi * 4), y: 0))
    }
}

/// An arc turning round a disc while the browser has the user; still under Reduce Motion.
struct OnboardingSpinner: View {
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: MotionBudget.demonstrationFrameInterval,
                paused: !attended || !motion.workingBarsMove)
        ) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            Circle()
                .trim(from: 0, to: 0.23)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(motion.workingBarsMove ? turn * 360 : -90))
                .padding(1.25)
        }
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
    }
}

/// The white field in the card, with a caret; typed words appear a letter at a time and back.
struct OnboardingFieldView: View {
    let field: OnboardingField
    let width: CGFloat
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: MotionBudget.demonstrationFrameInterval,
                paused: !attended || !motion.demonstrationMoves)
        ) { timeline in
            let time = motion.demonstrationMoves ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: 1) {
                content(at: time, moving: motion.demonstrationMoves)
                Rectangle()
                    .fill(Color(rgb: BrandPalette.Onboarding.caret))
                    .frame(width: 2, height: 17)
                    .opacity(
                        !motion.demonstrationMoves || time.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0)
                Spacer(minLength: 0)
            }
        }
        .font(BrandFont.display(size: 15, weight: .medium))
        .lineLimit(1)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: width, alignment: .leading)
        .background(.white.opacity(0.95), in: .rect(cornerRadius: 12, style: .continuous))
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func content(at time: TimeInterval, moving: Bool) -> some View {
        switch field {
        case .placeholder(let words):
            Text(words).foregroundStyle(Color(rgb: BrandPalette.Onboarding.fieldPlaceholder))
        case .filled(let words):
            Text(words).foregroundStyle(OnboardingInk.field).truncationMode(.head)
        case .typing(let words):
            Text(moving ? String(words.prefix(Self.typed(words.count, at: time))) : words)
                .foregroundStyle(OnboardingInk.field)
        }
    }

    /// How many letters show: in over 2.4 s, then out again, over and over.
    static func typed(_ count: Int, at time: TimeInterval) -> Int {
        let phase = time.truncatingRemainder(dividingBy: 4.8) / 2.4
        let share = phase <= 1 ? phase : 2 - phase
        return Int((share * Double(count)).rounded())
    }

    private var label: String {
        switch field {
        case .placeholder(let words), .filled(let words), .typing(let words): words
        }
    }
}

/// The shortcut's keys, joined by plus signs; teal and pressed down while held.
struct OnboardingKeycaps: View {
    let keys: [String]
    let isHeld: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+").font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                Text(key)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 58, minHeight: 58)
                    .background(face, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center
                                ),
                                lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 0, y: isHeld ? 1 : 5)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 12)
                    .offset(y: isHeld ? 4 : 0)
            }
        }
        .animation(MotionBudget.current().allowing(.easeOut(duration: 0.12)), value: isHeld)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }

    private var face: LinearGradient {
        let top = isHeld ? OnboardingInk.teal.opacity(0.45) : .white.opacity(0.24)
        let bottom = isHeld ? OnboardingInk.teal.opacity(0.18) : .white.opacity(0.07)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The ring round the download: the percentage while it runs, a broken cloud when stopped, the mark when done.
struct OnboardingDownloadRing: View {
    let fraction: Double
    let download: OnboardingDownload

    var body: some View {
        let share = min(max(fraction, 0), 1)
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: download == .finished ? 1 : share)
                .stroke(
                    download == .stopped ? OnboardingInk.failureLit : .white,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(MotionBudget.current().allowing(.easeOut(duration: 0.25)), value: share)
            center(share)
        }
        .frame(width: 104, height: 104)
        .frame(width: 128, height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(share))
    }

    @ViewBuilder private func center(_ share: Double) -> some View {
        switch download {
        case .running:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(Int(share * 100))").font(BrandFont.display(size: 30, weight: .semibold)).tracking(
                    -0.9)
                Text("%").font(BrandFont.display(size: 15, weight: .semibold)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .monospacedDigit()
        case .stopped:
            Image(systemName: "icloud.slash").font(.system(size: 28)).foregroundStyle(
                OnboardingInk.failureLit)
        case .finished:
            UttrflowMarkView(height: 34).foregroundStyle(.white)
        }
    }

    private func label(_ share: Double) -> String {
        switch download {
        case .running: "Downloading the speech model, \(Int(share * 100))%"
        case .stopped: "The download stopped at \(Int(share * 100))%"
        case .finished: "The speech model is ready"
        }
    }
}

/// A sign-in code, monospaced and selectable, to be read off this screen and typed into another.
struct OnboardingCode: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .tracking(6)
            .foregroundStyle(OnboardingInk.field)
            .textSelection(.enabled)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(.white.opacity(0.95), in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
}

/// One dot per step: teal for done, a white bar for this one, faint for the rest.
struct OnboardingDots: View {
    let position: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(
                        index < position
                            ? OnboardingInk.teal : index == position ? .white : .white.opacity(0.25)
                    )
                    .frame(width: index == position ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// "Step 2 of 5: Microphone", naming the step when the position is one of the steps.
    private var label: String {
        let steps = OnboardingStep.inOrder
        guard steps.indices.contains(position - 1) else { return "Step \(position) of \(count)" }
        return "Step \(position) of \(count): \(steps[position - 1].railTitle)"
    }
}

/// The onboarding window's fixed colours; it is drawn dark in every appearance.
enum OnboardingInk {
    static let onWhite = Color(rgb: BrandPalette.Onboarding.buttonInk)
    static let glow = Color(rgb: BrandPalette.Onboarding.glow)
    static let teal = Color(rgb: BrandPalette.Teal.bright)
    static let caution = Color(rgb: BrandPalette.Semantic.cautionInk.dark)
    static let field = Color(rgb: BrandPalette.Onboarding.fieldInk)
    static let failureLit = Color(rgb: BrandPalette.Onboarding.failureLit)
    static let failureShadow = Color(rgb: BrandPalette.Onboarding.failureShadow)
    static let glass = Color(rgb: BrandPalette.Onboarding.glass)
}

// The welcome after signing in and the first try: confetti, the circle, the keyboard's corner and the wide button.

import SwiftUI
import UttrflowAccount
import UttrflowUX

/// One burst of confetti from `origin`, drawn from a seed so every frame is computed rather than stored.
struct OnboardingConfetti: View {
    let origin: UnitPoint
    let count: Int
    /// How far the pieces fly, as a share of the view's height.
    var reach: Double = 1
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false
    @State private var start = Date()
    @State private var landed = false

    /// How long one burst lasts before the view draws nothing.
    static let lifetime: TimeInterval = 3.2

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: MotionBudget.demonstrationFrameInterval,
                paused: landed || !attended || !motion.demonstrationMoves)
        ) { timeline in
            let age = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard motion.demonstrationMoves, age < Self.lifetime else { return }
                for index in 0..<count {
                    draw(Self.piece(index), at: age, in: size, on: &context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(Self.lifetime))
            landed = true
        }
    }

    /// One piece's flight: out at speed, slowed by the air, pulled down, turning, fading at the end.
    private func draw(
        _ piece: Piece, at age: TimeInterval, in size: CGSize, on context: inout GraphicsContext
    ) {
        let drag = 1.7
        let gravity = 620.0 * reach
        let slowed = (1 - exp(-drag * age)) / drag
        let speed = piece.speed * reach
        let x = origin.x * size.width + cos(piece.angle) * speed * slowed
        let y = origin.y * size.height + sin(piece.angle) * speed * slowed + gravity / drag * (age - slowed)
        let fade = min(1, max(0, (piece.life - age) * 1.4))
        guard fade > 0, y < size.height + 20 else { return }
        var copy = context
        copy.opacity = fade
        copy.translateBy(x: x, y: y)
        copy.rotate(by: .radians(piece.spin * age))
        let shape =
            piece.isRound
            ? Path(
                ellipseIn: CGRect(
                    x: -piece.width / 2, y: -piece.width / 2, width: piece.width, height: piece.width))
            : Path(
                CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height))
        copy.fill(shape, with: .color(piece.colour))
    }

    /// Everything that differs between two pieces.
    struct Piece {
        let angle: Double
        let speed: Double
        let spin: Double
        let width: Double
        let height: Double
        let isRound: Bool
        let life: Double
        let colour: Color
    }

    /// The colours thrown, from the onboarding palette.
    static let colours: [Color] = [
        OnboardingInk.teal, Color(rgb: BrandPalette.Teal.primary), Color(rgb: BrandPalette.Purple.light),
        Color(rgb: BrandPalette.Semantic.cautionInk.dark), Color(rgb: BrandPalette.Onboarding.welcomeGlow),
        .white,
        Color(rgb: BrandPalette.Semantic.warning),
    ]

    /// The `index`th piece, the same on every frame: a burst upwards, fanned about a quarter turn each side.
    static func piece(_ index: Int) -> Piece {
        let value = { (salt: Int) -> Double in
            let mixed =
                UInt64(truncatingIfNeeded: index &* 2_654_435_761 &+ salt &* 40_503) &* 0x9E37_79B9_7F4A_7C15
            return Double(mixed >> 11) / Double(UInt64(1) << 53)
        }
        return Piece(
            angle: -.pi / 2 + (value(1) - 0.5) * 2.6,
            speed: 380 + value(2) * 560,
            spin: (value(3) - 0.5) * 14,
            width: 6 + value(4) * 7,
            height: 3 + value(5) * 4,
            isRound: value(6) < 0.25,
            life: 2.2 + value(7) * 1,
            colour: colours[index % colours.count])
    }
}

/// The welcome's picture: the new account's circle, popping in over a burst of confetti.
struct OnboardingWelcomeHeader: View {
    let initials: String
    let provider: SignInProvider
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            EllipticalGradient(
                colors: [Color(rgb: BrandPalette.Semantic.cautionInk.dark).opacity(0.26), .clear],
                center: .bottom, startRadiusFraction: 0, endRadiusFraction: 0.75)
            EllipticalGradient(
                colors: [OnboardingInk.teal.opacity(0.25), .clear],
                center: UnitPoint(x: 0.5, y: 0.6), startRadiusFraction: 0, endRadiusFraction: 0.6)
            OnboardingConfetti(origin: UnitPoint(x: 0.5, y: 0.52), count: 160, reach: 0.5)
            circle
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(MotionBudget.current().allowing(.spring(response: 0.5, dampingFraction: 0.55))) {
                shown = true
            }
        }
    }

    private var circle: some View {
        Text(initials)
            .font(BrandFont.display(size: 35, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .background(
                LinearGradient(
                    colors: [OnboardingInk.teal, Color(rgb: BrandPalette.Purple.secondary)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .circle
            )
            .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3) }
            .shadow(color: OnboardingInk.teal.opacity(0.6), radius: 17, y: 12)
            .overlay(alignment: .bottomTrailing) {
                OnboardingProviderMark(provider: provider, size: 18)
                    .foregroundStyle(OnboardingInk.onWhite)
                    .frame(width: 30, height: 30)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 4)
                    .offset(x: 4, y: 4)
            }
            .accessibilityHidden(true)
    }
}

/// The address the account signed in with, beside its provider's mark.
struct OnboardingAccountChipView: View {
    let chip: OnboardingAccountChip

    var body: some View {
        HStack(spacing: 8) {
            OnboardingProviderMark(provider: chip.provider, size: 12)
                .foregroundStyle(OnboardingInk.onWhite)
                .frame(width: 20, height: 20)
                .background(.white, in: .circle)
            Text(chip.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .background(.white.opacity(0.08), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
    }
}

/// The page's one full-width button, with the bar that counts down to moving on and a caption.
struct OnboardingActionButton: View {
    let action: OnboardingAction
    let press: (OnboardingIntent) -> Void
    @State private var remaining = 1.0

    var body: some View {
        VStack(spacing: 8) {
            Button {
                press(action.intent)
            } label: {
                HStack(spacing: 9) {
                    Text(action.title)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(action.isProminent ? Color(rgb: BrandPalette.Teal.inkOnFill) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(face, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(action.isProminent ? 0 : 0.28), lineWidth: 1)
                }
                .shadow(
                    color: action.isProminent ? Color(rgb: BrandPalette.Teal.primary).opacity(0.6) : .clear,
                    radius: 14, y: 10
                )
                .contentShape(.rect)
            }
            .buttonStyle(OnboardingPressStyle())
            .keyboardShortcut(action.isProminent ? .defaultAction : nil)
            if let countdown = action.countdown {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 110, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(OnboardingInk.teal).frame(width: 110 * remaining, height: 3)
                    }
                    .onAppear {
                        remaining = 1
                        withAnimation(.linear(duration: Double(countdown.components.seconds))) {
                            remaining = 0
                        }
                    }
                    .accessibilityHidden(true)
            }
            if let caption = action.caption {
                Text(caption)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var face: AnyShapeStyle {
        action.isProminent
            ? AnyShapeStyle(Color(rgb: BrandPalette.Teal.primary)) : AnyShapeStyle(.white.opacity(0.12))
    }
}

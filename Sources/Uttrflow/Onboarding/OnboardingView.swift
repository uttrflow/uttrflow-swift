// The onboarding window's contents: the aurora, the logo, and the glass card each page is drawn on.

import AppKit
import SwiftUI
import UttrflowAccount
import UttrflowUX

/// The page the window is showing, observable for SwiftUI; every field comes from `OnboardingFlow`.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var page: OnboardingPage

    @ObservationIgnored private let flow: OnboardingFlow

    init(flow: OnboardingFlow) {
        self.flow = flow
        self.page = flow.page
        // Reads the flow through `self`, since the flow keeps this closure and must not be kept by it.
        flow.onChange = { [weak self] _ in
            guard let self else { return }
            page = self.flow.page
        }
    }

    func start() {
        Task { [flow] in await flow.start() }
    }

    /// Re-reads both permissions when the window comes to the front; System Settings never tells the app.
    func refresh() {
        Task { await flow.refresh() }
    }

    func press(_ intent: OnboardingIntent) {
        Task { await flow.perform(intent) }
    }

    /// Returns to sign-in, since a sign-out leaves nothing past it to show.
    func signedOut() {
        Task { await flow.signedOut() }
    }

    /// Tells the last page how the first try is going.
    func tried(_ trial: OnboardingTrial) {
        Task { await flow.tried(trial) }
    }
}

/// The onboarding window's contents, derived from `OnboardingPage`; dark whatever the Mac is set to.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingScreen(page: model.page, press: model.press)
            .onAppear { model.start() }
    }
}

/// One page drawn whole: the aurora for its mood, the logo, and the card.
struct OnboardingScreen: View {
    let page: OnboardingPage
    let press: (OnboardingIntent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingBackdrop(mood: page.mood)
            OnboardingLogo()
                .padding(.leading, OnboardingMetrics.logoInset.width)
                .padding(.top, OnboardingMetrics.logoInset.height)
            OnboardingCard(page: page, press: press)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, OnboardingMetrics.cardTrailing)
                .padding(.top, OnboardingMetrics.cardTop)
                .padding(.bottom, OnboardingMetrics.cardBottom)
        }
        .frame(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
        .coordinateSpace(.named(OnboardingMetrics.windowSpace))
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// The glass card: the picture above, the heading, the round buttons, a hint and the dots below.
struct OnboardingCard: View {
    let page: OnboardingPage
    let press: (OnboardingIntent) -> Void

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        content
            .frame(width: OnboardingMetrics.cardWidth)
            .frame(maxHeight: .infinity)
            .background(OnboardingCardGlass(mood: page.mood))
            .clipShape(.rect(cornerRadius: OnboardingMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.1)], startPoint: .top,
                            endPoint: .bottom),
                        lineWidth: 1)
            }
            // Cast by a still shape behind the opaque card, so the moving aurora inside never re-renders the shadow.
            .background {
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardRadius, style: .continuous)
                    .fill(.black)
                    .shadow(color: .black.opacity(0.65), radius: 30, y: 30)
            }
            .animation(motion.onboardingMoves ? .smooth(duration: 0.26) : nil, value: page.title)
    }

    /// The welcome and the first try put their heading first; every other page leads with its picture.
    @ViewBuilder private var content: some View {
        switch page.picture {
        case .welcome(let initials, let provider): welcome(initials: initials, provider: provider)
        case .keyboard(let keyboard): trying(keyboard)
        default: pictureFirst
        }
    }

    /// The circle over confetti, the greeting, the account, and Continue counting down.
    private func welcome(initials: String, provider: SignInProvider) -> some View {
        VStack(spacing: 0) {
            OnboardingWelcomeHeader(initials: initials, provider: provider)
                .frame(maxWidth: .infinity)
                .frame(height: OnboardingMetrics.welcomeHeight)
                .clipped()
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            VStack(spacing: 14) {
                heading(size: 32, glow: Color(rgb: BrandPalette.Onboarding.welcomeGlow))
                if let account = page.account { OnboardingAccountChipView(chip: account) }
                Spacer(minLength: 0)
                if let action = page.action { OnboardingActionButton(action: action, press: press) }
                OnboardingDots(position: page.position, count: page.stepCount)
            }
            .padding(.top, 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
    }

    /// The heading and what to do, the keyboard's corner, the field, and the way on.
    private func trying(_ keyboard: OnboardingKeyboard) -> some View {
        VStack(spacing: 18) {
            heading(size: 30, glow: OnboardingInk.glow)
            OnboardingKeyboardCorner(keyboard: keyboard)
            OnboardingTryField(field: keyboard.field, isListening: keyboard.isListening)
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                if let hint = page.hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                if let action = page.action { OnboardingActionButton(action: action, press: press) }
                OnboardingDots(position: page.position, count: page.stepCount)
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .overlay {
            if keyboard.celebrates {
                OnboardingConfetti(origin: UnitPoint(x: 0.5, y: 0.56), count: 70, reach: 0.6)
            }
        }
    }

    /// The title in the display face with the subtitle under it.
    private func heading(size: CGFloat, glow: Color) -> some View {
        VStack(spacing: 6) {
            Text(page.title)
                .font(BrandFont.display(size: size, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(
                    LinearGradient(
                        stops: [.init(color: .white, location: 0.3), .init(color: glow, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                )
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(page.accessibilityLabel)
            if let subtitle = page.subtitle {
                Text(subtitle)
                    .font(BrandFont.display(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .id(page.title)
        .transition(.opacity)
    }

    /// Every other page: the picture above, the heading, the round buttons and the dots.
    private var pictureFirst: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity)
                .frame(height: OnboardingMetrics.pictureHeight)
                .background(pictureGround)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            VStack(spacing: 22) {
                title
                // Pushed to the foot with one gap above it, so a page with a hint and the terms still fits the card.
                VStack(spacing: 0) {
                    buttons
                    footnotes
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                OnboardingDots(position: page.position, count: page.stepCount)
            }
            .padding(.top, 26)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .id(page.title)
            .transition(.opacity)
        }
    }

    /// The teal light rising from the foot of the picture.
    private var pictureGround: some View {
        ZStack {
            Color.black.opacity(0.15)
            EllipticalGradient(
                colors: [OnboardingInk.teal.opacity(0.28), .clear],
                center: .bottom, startRadiusFraction: 0, endRadiusFraction: 0.7)
        }
    }

    @ViewBuilder private var picture: some View {
        switch page.picture {
        case .waveform(let wave, let badge):
            ZStack {
                OnboardingWaveform(wave: wave).frame(width: 300, height: 110)
                if let badge { OnboardingBadgeView(badge: badge) }
            }
        case .typing(let wave, let field):
            VStack(spacing: 6) {
                OnboardingWaveform(wave: wave).frame(width: 240, height: 88)
                OnboardingFieldView(field: field, width: 250)
            }
        case .download(let fraction, let download):
            OnboardingDownloadRing(fraction: fraction, download: download)
        case .keys(let keys, let isHeld, let field):
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    OnboardingKeycaps(keys: keys, isHeld: isHeld)
                    if isHeld { OnboardingWaveform(wave: .talking, count: 18).frame(width: 90, height: 33) }
                }
                OnboardingFieldView(field: field, width: 280)
            }
        case .code(let code):
            OnboardingCode(code: code)
        // Drawn by their own layouts, never inside the picture slot.
        case .welcome, .keyboard:
            EmptyView()
        }
    }

    private var title: some View {
        Text(page.title)
            .font(BrandFont.display(size: 34, weight: .semibold))
            .tracking(-1)
            .multilineTextAlignment(.center)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.35), .init(color: OnboardingInk.glow, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(page.accessibilityLabel)
    }

    private var buttons: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(page.providers, id: \.provider) { provider in
                OnboardingRoundButton(
                    title: provider.label, isProminent: provider.provider == page.providers.first?.provider,
                    isEnabled: provider.isEnabled, action: { press(.signIn(provider.provider)) }
                ) {
                    OnboardingProviderMark(provider: provider.provider, size: 26)
                }
                .accessibilityLabel(provider.title)
            }
            ForEach(Array(page.buttons.enumerated()), id: \.offset) { _, button in
                OnboardingRoundButton(
                    title: button.title, isProminent: button.isProminent, isEnabled: button.isEnabled,
                    isPointedAt: button.isPointedAt, isSelected: button.isSelected,
                    action: { press(button.intent) }
                ) {
                    Image(systemName: button.symbolName).font(.system(size: 22, weight: .medium))
                }
            }
        }
    }

    /// The hint, the terms and the link, each quiet and centred under the buttons.
    @ViewBuilder private var footnotes: some View {
        if let hint = page.hint {
            Text(hint)
                .font(.system(size: page.link == nil ? 11 : 12.5))
                .foregroundStyle(.white.opacity(page.link == nil ? 0.42 : 0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 12)
        }
        if page.showsTerms {
            Text("Terms · Privacy")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.top, 12)
                .accessibilityLabel("By continuing you agree to the Terms of Use and the Privacy Policy.")
        }
        if let link = page.link {
            Button(link.title) { press(link.intent) }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .underline(color: .white.opacity(0.3))
                .padding(.top, 10)
        }
    }
}

// MARK: - Sizes

/// The measurements the design is drawn to. See `Docs/app-onboarding.md`.
enum OnboardingMetrics {
    static let windowWidth: CGFloat = 860
    static let windowHeight: CGFloat = 560
    /// The logo's top-left corner, clear of the window's buttons.
    static let logoInset = CGSize(width: 24, height: 56)
    static let cardWidth: CGFloat = 390
    static let cardRadius: CGFloat = 28
    static let cardTop: CGFloat = 66
    static let cardTrailing: CGFloat = 40
    static let cardBottom: CGFloat = 40
    /// The window's coordinate space, which the card's glass lines its sky up in.
    static let windowSpace = "onboarding.window"
    /// How much the card's glass saturates the sky behind it.
    static let glassSaturation: Double = 1.5
    /// How strongly the violet-black tint covers the glass.
    static let glassTint: Double = 0.46
    /// The picture at the top of the card.
    static let pictureHeight: CGFloat = 170
    /// The welcome's taller picture, with room for the confetti to rise.
    static let welcomeHeight: CGFloat = 190
    static let roundSize: CGFloat = 64
    /// The aurora's shortest gap between frames: it turns a degree in a fifth of a second.
    static let auroraFrameInterval: TimeInterval = 1.0 / 15
}

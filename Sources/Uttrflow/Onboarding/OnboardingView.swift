// The onboarding window's pages, sizes, colours and parts.

import AppKit
import UttrflowAccount
import UttrflowUX
import SwiftUI

/// The page the window is showing, observable for SwiftUI; every field comes from `OnboardingFlow`.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var page: OnboardingPage

    @ObservationIgnored private let flow: OnboardingFlow

    init(flow: OnboardingFlow) {
        self.flow = flow
        self.page = flow.page
        flow.onChange = { [weak self] _ in
            guard let self else { return }
            page = flow.page
        }
    }

    /// Whether this window was opened to finish something; set before the view appears and starts the flow.
    @ObservationIgnored var skipsWelcome = false
    /// Whether the window was opened by Sign In rather than by a permission button.
    @ObservationIgnored var asksToSignIn = false

    func start() {
        Task { [flow, skipsWelcome, asksToSignIn] in
            await skipsWelcome ? flow.resume(askingToSignIn: asksToSignIn) : flow.start()
        }
    }

    /// Re-reads both permissions when the window comes to the front; System Settings never tells the app.
    func refresh() {
        Task { await flow.refresh() }
    }

    func press(_ intent: OnboardingIntent) {
        Task { await flow.perform(intent) }
    }

}

/// The onboarding window's contents: the brand rail and the page beside it, derived from `OnboardingPage`.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        HStack(spacing: 0) {
            OnboardingRail(position: model.page.position)
            page
        }
        .frame(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
        .background(Color.mainBackground)
        .animation(.smooth(duration: 0.26), value: model.page.position)
        .onAppear { model.start() }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One container, so the content takes its height and the footer never moves between pages.
            ZStack(alignment: .leading) {
                content
                    .id(model.page.position)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            footer
        }
        .padding(.top, OnboardingMetrics.pageTopInset)
        .padding(.horizontal, OnboardingMetrics.margin)
        .padding(.bottom, OnboardingMetrics.footInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.mainBackground)
    }

    // MARK: - The page

    @ViewBuilder private var content: some View {
        let page = model.page
        VStack(alignment: .leading, spacing: 0) {
            // Grouped as one sentence for a screen reader, with the controls below left reachable.
            VStack(alignment: .leading, spacing: 0) {
                Glyph(symbolName: page.symbolName, emphasis: page.emphasis)
                Text(page.title)
                    .font(.system(size: OnboardingMetrics.titleSize, weight: .bold))
                    .kerning(-0.45)
                    .padding(.top, 22)
                Text(page.subtitle)
                    .font(.system(size: OnboardingMetrics.subtitleSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)
                if let body = page.body {
                    Text(body)
                        .font(.system(size: OnboardingMetrics.bodySize))
                        .foregroundStyle(Color.mainMuted)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: OnboardingMetrics.columnWidth, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(page.accessibilityLabel)

            if let code = page.code {
                SignInCode(code: code)
                    .padding(.top, 20)
            }
            if !page.keys.isEmpty {
                Keycaps(keys: page.keys)
                    .padding(.top, 20)
            }
            if let progress = page.progress {
                ProgressTrack(fraction: progress)
                    .padding(.top, 24)
            }
            // A warning explains why what is under it will not work, so it is read first.
            if let note = page.note, note.tone == .warning {
                Note(note: note)
                    .padding(.top, 20)
            }
            if !page.providers.isEmpty {
                ProviderStack(providers: page.providers) { model.press(.signIn($0)) }
                    .padding(.top, 20)
            }
            if let note = page.note, note.tone != .warning {
                Note(note: note)
                    .padding(.top, 22)
            }
            if let fineprint = page.fineprint {
                Text(fineprint)
                    // The one line a person is agreeing to, so it is not the dimmest text in the window.
                    .font(.system(size: OnboardingMetrics.fineprintSize))
                    .foregroundStyle(Color.mainMuted)
                    .padding(.top, 18)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The foot of the window

    /// The answers, ranged right, with the one the page steers towards last.
    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(Array(model.page.buttons.enumerated()), id: \.offset) { _, button in
                Button(button.title) { model.press(button.intent) }
                    .buttonStyle(OnboardingButtonStyle(isProminent: button.isProminent))
                    .disabled(!button.isEnabled)
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - Sizes

/// The measurements the design is drawn to.
enum OnboardingMetrics {
    /// Big enough for the sign-in page with three providers; the window clips rather than scrolls.
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 520
    static let railWidth: CGFloat = 232
    static let railTopInset: CGFloat = 52
    static let railRowHeight: CGFloat = 34
    static let railRowInset: CGFloat = 8
    static let railDotSize: CGFloat = 18
    static let margin: CGFloat = 40
    /// Long enough for a comfortable line: the body runs to three lines, not two wide ones.
    static let columnWidth: CGFloat = 400
    static let pageTopInset: CGFloat = 44
    static let footInset: CGFloat = 26
    static let glyphSize: CGFloat = 60
    static let glyphRadius: CGFloat = 17
    /// The last page's tile, which is larger because that page is the good news.
    static let celebratedGlyphSize: CGFloat = 74
    static let celebratedGlyphRadius: CGFloat = 21
    static let titleSize: CGFloat = 25
    static let subtitleSize: CGFloat = 14.5
    static let bodySize: CGFloat = 13
    static let calloutSize: CGFloat = 11.5
    static let fineprintSize: CGFloat = 11
    static let providerWidth: CGFloat = 336
    static let providerHeight: CGFloat = 40
    static let controlHeight: CGFloat = 34
    static let controlRadius: CGFloat = 9
}

// MARK: - Colours

extension Color {
    /// The accent as a foreground in both appearances; the light half clears 4.5:1 on `#F3F2F7`.
    static let onboardingAccentInk = Color(nsColor: .orbit(dark: 0x5F_E0D3, light: 0x0E_6B64))
    /// The same, for the pages that are reporting a failure.
    static let onboardingCautionInk = Color(nsColor: .orbit(dark: 0xFF_B05C, light: 0x9A_4E00))
    /// A control on the page, one step lifted from the ground, so provider buttons read as buttons.
    static let onboardingControl = Color(nsColor: .orbit(dark: 0x12_151C, light: 0xFF_FFFF))
}

// MARK: - Parts

/// The rounded slab at the top of every page.
private struct Glyph: View {
    let symbolName: String?
    let emphasis: OnboardingEmphasis

    /// Whether the arrival animation has run; one-shot, because a page that pulses for ever looks busy.
    @State private var hasLanded = false

    private var isCelebrating: Bool { emphasis == .success }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .overlay(mark)
            .shadow(color: shadow, radius: isCelebrating ? 22 : 13, y: 6)
            .background(alignment: .center) { bloom }
            .scaleEffect(isCelebrating && !hasLanded ? 0.72 : 1)
            .opacity(isCelebrating && !hasLanded ? 0 : 1)
            .onAppear {
                guard isCelebrating else { return }
                withAnimation(.spring(response: 0.52, dampingFraction: 0.58)) {
                    hasLanded = true
                }
            }
    }

    private var size: CGFloat {
        isCelebrating ? OnboardingMetrics.celebratedGlyphSize : OnboardingMetrics.glyphSize
    }

    private var radius: CGFloat {
        isCelebrating ? OnboardingMetrics.celebratedGlyphRadius : OnboardingMetrics.glyphRadius
    }

    /// The last page's light and three rings that arrive and then stop.
    @ViewBuilder private var bloom: some View {
        if isCelebrating {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.dockAccentLight.opacity(0.34), .dockAccent.opacity(0)],
                            center: .center, startRadius: 8, endRadius: 132)
                    )
                    .frame(width: 264, height: 264)
                ForEach(Array([1.0, 1.45, 1.95].enumerated()), id: \.offset) { index, scale in
                    Circle()
                        .strokeBorder(
                            Color.dockAccentLight.opacity(0.30 - Double(index) * 0.09),
                            lineWidth: 1
                        )
                        .frame(width: size + 26, height: size + 26)
                        .scaleEffect(hasLanded ? scale : 0.72)
                        .opacity(hasLanded ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.7).delay(0.06 * Double(index)), value: hasLanded)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The symbol, or the mark itself on the pages about Uttrflow; not the icon, which is already a tile.
    @ViewBuilder private var mark: some View {
        if let symbolName {
            Image(systemName: symbolName)
                .font(
                    .system(
                        size: isCelebrating ? 32 : 25,
                        weight: isCelebrating ? .semibold : .regular)
                )
                .foregroundStyle(symbolInk)
        } else {
            UttrflowMarkView(height: 28)
                .foregroundStyle(.white)
        }
    }

    private var fill: AnyShapeStyle {
        switch emphasis {
        case .brand, .success:
            AnyShapeStyle(
                LinearGradient(
                    colors: [Color(rgb: 0x33_D6C7), .dockAccent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        case .neutral: AnyShapeStyle(Color.dockAccent.opacity(0.12))
        case .caution: AnyShapeStyle(Color.dockWarning.opacity(0.13))
        }
    }

    private var border: Color {
        switch emphasis {
        case .brand, .success: .clear
        case .neutral: .dockAccent.opacity(0.28)
        case .caution: .dockWarning.opacity(0.28)
        }
    }

    private var symbolInk: Color {
        switch emphasis {
        case .brand, .success: .white
        case .neutral: .onboardingAccentInk
        case .caution: .onboardingCautionInk
        }
    }

    private var shadow: Color {
        switch emphasis {
        case .brand, .success: .dockAccent.opacity(0.42)
        case .neutral, .caution: .clear
        }
    }
}

/// The three ways in, stacked; offline they stay visible but inert.
private struct ProviderStack: View {
    let providers: [OnboardingProviderButton]
    let choose: (SignInProvider) -> Void

    var body: some View {
        VStack(spacing: 9) {
            ForEach(providers, id: \.provider) { button in
                Button {
                    choose(button.provider)
                } label: {
                    HStack(spacing: 9) {
                        ProviderMark(provider: button.provider)
                        Text(button.title)
                    }
                }
                .buttonStyle(ProviderButtonStyle())
                .disabled(!button.isEnabled)
            }
        }
        .frame(width: OnboardingMetrics.providerWidth)
    }
}

/// The provider's mark; Google's is fetched, never redrawn, and may be absent. See Docs/app-onboarding.md.
private struct ProviderMark: View {
    let provider: SignInProvider

    var body: some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 15))
        case .google:
            if let mark = Bundle.module.image(forResource: "GoogleMark") {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
        case .gitHub:
            EmptyView()
        }
    }
}

/// The sign-in code, monospaced and selectable, drawn to be read off one screen and typed into another.
private struct SignInCode: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .tracking(6)
            .textSelection(.enabled)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.dockAccent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.dockAccent.opacity(0.30), lineWidth: 1)
            )
            // Read one character at a time; this is the one string that must be transcribed exactly.
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
}

/// The keys to hold, drawn as keycaps with a lit edge and a shadow.
private struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 36, minHeight: 32)
                    .padding(.horizontal, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.onboardingControl)
                            .shadow(color: .black.opacity(0.35), radius: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.mainSeparator, lineWidth: 1))
            }
        }
    }
}

/// How far through the download is, with the figure beside the bar so a slow line looks unlike a stall.
private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Downloading the speech model")
                    .font(.system(size: OnboardingMetrics.calloutSize, weight: .medium))
                    .foregroundStyle(Color.mainMuted)
                Spacer(minLength: 12)
                Text(fraction.asPercentage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.onboardingAccentInk)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.dockAccent, .dockAccentLight],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: proxy.size.width * fraction.clampedToUnitInterval)
                    .shadow(color: .dockAccentLight.opacity(0.45), radius: 7)
            }
            .frame(height: 8)
            .background(Color.onboardingControl, in: .capsule)
            .animation(.easeOut(duration: 0.25), value: fraction)
        }
        .frame(width: OnboardingMetrics.columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading the speech model, \(fraction.asPercentage)")
    }
}

/// The quieter line under the body: what this page costs, or what it protects.
private struct Note: View {
    let note: OnboardingNote

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: note.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.top, 1)
            Text(note.text)
                .font(.system(size: OnboardingMetrics.calloutSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: OnboardingMetrics.columnWidth, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(edge, lineWidth: 1))
    }

    /// A quiet note is tinted with the accent, because it states the product's own claim.
    private var background: Color {
        switch note.tone {
        case .quiet: .dockAccent.opacity(0.09)
        case .warning: .dockWarning.opacity(0.12)
        }
    }

    private var edge: Color {
        switch note.tone {
        case .quiet: .dockAccent.opacity(0.22)
        case .warning: .dockWarning.opacity(0.28)
        }
    }

    private var ink: Color {
        switch note.tone {
        case .quiet: .onboardingAccentInk
        case .warning: .onboardingCautionInk
        }
    }
}

// MARK: - Controls

/// The answers at the foot of a page: a filled accent for the one steered towards, an outline beside it.
private struct OnboardingButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, because `isEnabled` is an environment value and `makeBody` is not a view.
        Face(configuration: configuration, isProminent: isProminent)
    }

    private struct Face: View {
        let configuration: Configuration
        let isProminent: Bool
        /// Read here rather than in `makeBody`, which is not a view and cannot see it.
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: isProminent ? .semibold : .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, isProminent ? 18 : 16)
                .frame(height: OnboardingMetrics.controlHeight)
                .background(background, in: .rect(cornerRadius: OnboardingMetrics.controlRadius))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: OnboardingMetrics.controlRadius, style: .continuous
                    )
                    .strokeBorder(isProminent ? .clear : Color.mainSeparator, lineWidth: 1)
                )
                .shadow(
                    color: isProminent && isEnabled ? .dockAccent.opacity(0.38) : .clear,
                    radius: 9, y: 4
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .contentShape(.rect)
        }

        private var background: AnyShapeStyle {
            guard isProminent else { return AnyShapeStyle(.clear) }
            guard isEnabled else { return AnyShapeStyle(Color.dockAccent.opacity(0.20)) }
            return AnyShapeStyle(LinearGradient.accentFill)
        }

        private var foreground: Color {
            if isProminent {
                isEnabled ? .white : .white.opacity(0.45)
            } else {
                isEnabled ? .secondary : Color.mainDim
            }
        }
    }
}

/// One of the three ways in: a full-width control on the page's own card colour.
private struct ProviderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration)
    }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.mainText)
                .frame(maxWidth: .infinity, minHeight: OnboardingMetrics.providerHeight)
                .background(Color.onboardingControl, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.mainSeparator, lineWidth: 1)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
                .contentShape(.rect)
        }
    }
}

extension Double {
    /// A fraction a download reported, kept inside the bar it is drawn in.
    fileprivate var clampedToUnitInterval: Double { min(max(self, 0), 1) }

    /// The figure beside the bar, rounded down so an unfinished bar never reads 100%.
    fileprivate var asPercentage: String {
        "\(Int(clampedToUnitInterval * 100))%"
    }
}

// The onboarding window's ground: the aurora for the page's mood, the logo, and the waveform.

import AppKit
import SwiftUI
import UttrflowUX

/// The window behind the card: the mood's aurora turning slowly under a veil and grain, and the faded mark.
struct OnboardingBackdrop: View {
    let mood: OnboardingMood

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OnboardingSky(mood: mood)
            OnboardingGrain()
            UttrflowMarkView(height: 470)
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: -40, y: 70)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The ground, the mood's aurora and the veil: what the card's glass sees through.
struct OnboardingSky: View {
    let mood: OnboardingMood
    /// How saturated the aurora is drawn; the card's glass draws it richer than the window does.
    var saturation: Double = 1

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        ZStack {
            Color(rgb: BrandPalette.Onboarding.windowGround)
            OnboardingAurora(mood: mood, saturation: saturation)
                .id(mood)
                .transition(.opacity)
            LinearGradient(
                colors: [.clear, Color(rgb: BrandPalette.Onboarding.windowGround).opacity(0.3)],
                startPoint: .top, endPoint: .bottom)
        }
        .animation(motion.onboardingMoves ? .easeInOut(duration: 0.6) : nil, value: mood)
    }
}

/// The card's glass: the sky behind the card, saturated as frosted glass does, under the violet-black tint.
struct OnboardingCardGlass: View {
    let mood: OnboardingMood

    var body: some View {
        GeometryReader { proxy in
            let card = proxy.frame(in: .named(OnboardingMetrics.windowSpace))
            OnboardingSky(mood: mood, saturation: OnboardingMetrics.glassSaturation)
                .frame(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
                .offset(x: -card.minX, y: -card.minY)
        }
        .overlay(OnboardingInk.glass.opacity(OnboardingMetrics.glassTint))
        .accessibilityHidden(true)
    }
}

/// One mood's conic gradient, blurred soft and turning once every forty seconds when the Mac allows motion.
private struct OnboardingAurora: View {
    let mood: OnboardingMood
    let saturation: Double
    @Environment(\.displayScale) private var displayScale
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: OnboardingMetrics.auroraFrameInterval,
                paused: !attended || !motion.demonstrationMoves)
        ) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let canvas = OnboardingAuroraPicture.canvasSize(for: size)
                if let picture = OnboardingAuroraPicture.image(
                    mood: mood, saturation: saturation, size: size, scale: displayScale)
                {
                    Image(nsImage: picture)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: canvas.width, height: canvas.height)
                        .rotationEffect(.degrees(turn(at: timeline.date, moving: motion.demonstrationMoves)))
                        .position(x: size.width / 2, y: size.height / 2)
                }
            }
        }
        .opacity(opacity)
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
    }

    /// How far round the aurora has turned, one turn every forty seconds.
    private func turn(at date: Date, moving: Bool) -> Double {
        guard moving else { return 0 }
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40 * 360
    }

    /// A stop saturated as a CSS `saturate()` filter does, so blurring it after gives the same colours.
    fileprivate static func saturated(_ rgb: UInt32, by amount: Double) -> Color {
        let channels = [16, 8, 0].map { Double((rgb >> UInt32($0)) & 0xFF) / 255 }
        let luma = 0.213 * channels[0] + 0.715 * channels[1] + 0.072 * channels[2]
        let pushed = channels.map { min(1, max(0, luma + amount * ($0 - luma))) }
        return Color(.sRGB, red: pushed[0], green: pushed[1], blue: pushed[2])
    }

    /// The problem moods are dimmer, so bad news is never the brightest thing on the screen.
    private var opacity: Double {
        switch mood {
        case .brand, .live, .waiting, .done: 1
        case .warning: 0.7
        case .failure: 0.6
        case .offline: 0.9
        }
    }
}

/// Each mood's aurora, blurred into a bounded picture once and rotated as an image thereafter.
@MainActor
enum OnboardingAuroraPicture {
    private struct Key: Hashable {
        let mood: String
        let saturation: Double
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    private static var pictures: [Key: NSImage] = [:]
    private static let blurRadius: CGFloat = 70

    /// The image's square canvas holds the uncut aurora at every angle.
    static func canvasSize(for size: CGSize) -> CGSize {
        let width = size.width * 1.5
        let height = size.height * 1.5
        let diagonal = hypot(width, height) + blurRadius * 6
        return CGSize(width: diagonal, height: diagonal)
    }

    /// Renders a mood and saturation combination once for the onboarding window's size.
    static func image(mood: OnboardingMood, saturation: Double, size: CGSize, scale: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = Key(
            mood: String(describing: mood), saturation: saturation,
            width: Int(size.width.rounded()), height: Int(size.height.rounded()), scale: scale)
        if let known = pictures[key] { return known }
        let canvas = canvasSize(for: size)
        let stops = stops(for: mood, saturation: saturation)
        let renderer = ImageRenderer(
            content: ZStack {
                AngularGradient(
                    colors: stops, center: center(for: mood),
                    startAngle: .degrees(startAngle(for: mood)),
                    endAngle: .degrees(startAngle(for: mood) + 360)
                )
                .frame(width: size.width * 1.5, height: size.height * 1.5)
                .blur(radius: blurRadius)
            }
            .frame(width: canvas.width, height: canvas.height))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        if pictures.count >= 4, let oldest = pictures.keys.first { pictures[oldest] = nil }
        pictures[key] = image
        return image
    }

    /// The mood's stops, closed on the first so the turn shows no seam.
    private static func stops(for mood: OnboardingMood, saturation: Double) -> [Color] {
        let values: [UInt32] =
            switch mood {
            case .brand: BrandPalette.Onboarding.brandAurora
            case .live: BrandPalette.Onboarding.liveAurora
            case .waiting: BrandPalette.Onboarding.waitingAurora
            case .warning: BrandPalette.Onboarding.warningAurora
            case .failure: BrandPalette.Onboarding.failureAurora
            case .offline: BrandPalette.Onboarding.offlineAurora
            case .done: BrandPalette.Onboarding.doneAurora
            }
        return (values + values.prefix(1)).map { OnboardingAurora.saturated($0, by: saturation) }
    }

    /// Where the gradient turns about, matching the live onboarding artwork.
    private static func center(for mood: OnboardingMood) -> UnitPoint {
        switch mood {
        case .brand: UnitPoint(x: 0.35, y: 0.55)
        case .warning, .failure, .offline: UnitPoint(x: 0.4, y: 0.5)
        case .live, .waiting, .done: .center
        }
    }

    /// Where the first stop sits, in SwiftUI's angles.
    private static func startAngle(for mood: OnboardingMood) -> Double {
        switch mood {
        case .brand, .done: 120
        case .live: 90
        case .waiting: 0
        case .warning, .failure, .offline: 110
        }
    }
}

/// Fine white grain over the aurora, drawn once; deterministic, so it does not shimmer.
private struct OnboardingGrain: View {
    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var generator = SplitMix64(seed: 0x5F_E0D3_29C0)
            let dot = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
            for _ in 0..<6000 {
                let x = generator.fraction() * size.width
                let y = generator.fraction() * size.height
                context.fill(
                    dot.offsetBy(dx: x, dy: y),
                    with: .color(.white.opacity(0.03 + generator.fraction() * 0.07)))
            }
        }
        .drawingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// The full logo: the mark on its dark tile beside the wordmark, both from the one mark.
struct OnboardingLogo: View {
    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(rgb: BrandPalette.Onboarding.tileTop),
                            Color(rgb: BrandPalette.Onboarding.tileBottom),
                        ], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 70, height: 70)
                .overlay {
                    UttrflowMarkView(height: 36)
                        .foregroundStyle(Color(rgb: BrandPalette.Onboarding.logoInk))
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 10)
                .frame(width: 84, height: 84)
            BrandWordmark(size: 58)
                .foregroundStyle(Color(rgb: BrandPalette.Onboarding.logoInk))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uttrflow")
    }
}

/// A row of bars that moves like speech, swells while waiting, or lies flat, faded out at both ends.
struct OnboardingWaveform: View {
    let wave: OnboardingWave
    /// How many bars are drawn.
    var count = 44
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false

    var body: some View {
        let motion = MotionBudgetObserver.shared.budget
        TimelineView(
            .animation(
                minimumInterval: MotionBudget.demonstrationFrameInterval,
                paused: wave == .still || !attended || !motion.demonstrationMoves)
        ) { timeline in
            Canvas { context, size in
                let time = motion.demonstrationMoves ? timeline.date.timeIntervalSinceReferenceDate : 0
                draw(in: context, size: size, time: time)
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
        }
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let inset = size.width * 20 / 600
        let bar = size.width * 6 / 600
        let gap = (size.width - 2 * inset - CGFloat(count) * bar) / CGFloat(count - 1)
        let level = Self.level(wave, at: time)
        let opacity = wave == .still ? 0.45 : 0.95
        for index in 0..<count {
            let position = Double(index) / Double(count - 1) - 0.5
            let envelope = exp(-position * position * 7)
            let height = max(
                bar, CGFloat(max(0.04, level * envelope * Self.ripple(index, time))) * size.height * 0.86)
            let rect = CGRect(
                x: inset + CGFloat(index) * (bar + gap), y: (size.height - height) / 2, width: bar,
                height: height)
            context.fill(
                Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(.white.opacity(opacity)))
        }
    }

    /// How loud the row is: phrases of syllables when talking, a slow swell when idle, nothing when still.
    static func level(_ wave: OnboardingWave, at time: TimeInterval) -> Double {
        switch wave {
        case .still: return 0
        case .idle: return 0.22 + 0.08 * sin(time * 1.6)
        case .talking:
            let phrase = sin(time * 0.9) > -0.35 ? 1.0 : 0.15
            let syllable = 0.45 + 0.55 * abs(sin(time * 6.3 + sin(time * 1.7)))
            return phrase * syllable
        }
    }

    /// Each bar's own wobble, so the row never moves as one block.
    static func ripple(_ index: Int, _ time: TimeInterval) -> Double {
        let bar = Double(index)
        return 0.55 + 0.25 * sin(time * 5.1 + bar * 0.7) + 0.2 * sin(time * 8.3 - bar * 1.3)
            + 0.15 * sin(time * 2.2 + bar * 0.31)
    }
}

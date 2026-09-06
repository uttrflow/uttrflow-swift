// The brand rail beside the onboarding pages, and the rail ground Settings shares.

import AppKit
import UttrflowUX
import SwiftUI

/// The brand rail down the left of the onboarding window: the mark, the seven steps, and the current one.
struct OnboardingRail: View {
    let position: Int

    private let steps = OnboardingStep.inOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                UttrflowMarkView(height: 21)
                Text("Uttrflow")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
            }
            .foregroundStyle(.white)
            .padding(.leading, OnboardingMetrics.railRowInset)

            list
                .padding(.top, 32)

            Spacer(minLength: 12)

            Text("Step \(position) of \(steps.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .padding(.leading, OnboardingMetrics.railRowInset)
        }
        .padding(.top, OnboardingMetrics.railTopInset)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .frame(width: OnboardingMetrics.railWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(RailGround())
        // One label for the whole rail; seven rows read out one at a time repeat the page.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Step \(position) of \(steps.count): \(steps[position - 1].railTitle)")
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                row(step, at: index + 1)
            }
        }
        .background(alignment: .topLeading) { spine }
    }

    /// The line the indicators are threaded on, lit as far as the user has come, drawn behind the rows.
    private var spine: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 1, height: OnboardingMetrics.railRowHeight * CGFloat(steps.count - 1))
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(
                    width: 1,
                    height: OnboardingMetrics.railRowHeight * CGFloat(max(position - 1, 0)))
        }
        .offset(
            x: OnboardingMetrics.railRowInset + OnboardingMetrics.railDotSize / 2 - 0.5,
            y: OnboardingMetrics.railRowHeight / 2)
    }

    private func row(_ step: OnboardingStep, at index: Int) -> some View {
        HStack(spacing: 11) {
            indicator(for: index)
            Text(step.railTitle)
                .font(.system(size: 12.5, weight: index == position ? .semibold : .medium))
                .foregroundStyle(label(for: index))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OnboardingMetrics.railRowInset)
        .frame(height: OnboardingMetrics.railRowHeight)
        .background(
            index == position ? Color.white.opacity(0.10) : .clear,
            in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private func indicator(for index: Int) -> some View {
        let size = OnboardingMetrics.railDotSize
        if index < position {
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        // The rail's own deep end, so the tick reads as cut out of the ground.
                        .foregroundStyle(Color(rgb: 0x06_3A35)))
        } else if index == position {
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: size, height: size)
                .overlay(Circle().fill(.white).frame(width: 7, height: 7))
        } else {
            Circle()
                .strokeBorder(.white.opacity(0.30), lineWidth: 1.5)
                .frame(width: size, height: size)
        }
    }

    private func label(for index: Int) -> Color {
        if index < position {
            .white.opacity(0.74)
        } else if index == position {
            .white
        } else {
            .white.opacity(0.44)
        }
    }

}

/// The rail's ground, shared with Settings: the accent deepened until white sits on it, in both appearances.
struct RailGround: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(rgb: 0x0E_4F49),
                Color(rgb: 0x09_3B37),
                Color(rgb: 0x06_2725),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.dockAccentLight.opacity(0.30), .clear],
                center: UnitPoint(x: 0.14, y: 0), startRadius: 0, endRadius: 300)
        )
        .overlay(RailPattern())
    }
}

/// A handful of out-of-focus lights under film grain, all white below 8%; the grain hides gradient banding.
private struct RailPattern: View {
    /// Each light as a fraction of the rail, so the arrangement survives a taller window.
    private struct Light {
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let alpha: Double
    }

    private static let lights = [
        Light(x: 150, y: 0.635, diameter: 120, alpha: 0.07),
        Light(x: 24, y: 0.808, diameter: 86, alpha: 0.05),
        Light(x: 176, y: 0.869, diameter: 64, alpha: 0.06),
        Light(x: 96, y: 0.742, diameter: 46, alpha: 0.05),
        Light(x: -14, y: 0.577, diameter: 70, alpha: 0.04),
        Light(x: 188, y: 0.481, diameter: 40, alpha: 0.05),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.lights.enumerated()), id: \.offset) { _, light in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(light.alpha), .white.opacity(0)],
                                center: .center, startRadius: 0,
                                endRadius: light.diameter * 0.34)
                        )
                        .frame(width: light.diameter, height: light.diameter)
                        .offset(x: light.x, y: proxy.size.height * light.y)
                }
                Grain()
            }
        }
        .allowsHitTesting(false)
    }
}

/// Film grain, drawn once and rasterised; deterministic, so it does not shimmer when the window resizes.
private struct Grain: View {
    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var generator = SplitMix64(seed: 0x5F_E0D3_29C0)
            let dot = Path(CGRect(x: 0, y: 0, width: 1, height: 1))
            for _ in 0..<2400 {
                let x = generator.fraction() * size.width
                let y = generator.fraction() * size.height
                context.fill(
                    dot.offsetBy(dx: x, dy: y),
                    with: .color(.white.opacity(0.02 + generator.fraction() * 0.05)))
            }
        }
        // Rasterised once rather than re-run on every redraw of the page beside it.
        .drawingGroup()
        .blendMode(.plusLighter)
    }
}

/// Sixty-four bits of reproducible noise, small enough to read.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func fraction() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }
}

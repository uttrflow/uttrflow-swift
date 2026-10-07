// The onboarding aurora's cached picture keeps the original backdrop while it turns.

import AppKit
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Onboarding aurora picture")
struct OnboardingAuroraPictureTests {
    private let size = CGSize(width: 860, height: 560)
    /// An 8-bit picture quantised once and resampled when turned differs by up to 6 levels from the live blur.
    private static let tolerance: CGFloat = 6.0 / 255

    @Test("the blurred picture matches the original sign-in aurora at every turn")
    func cachedPictureMatchesTheOriginal() throws {
        for scale in [CGFloat(1), CGFloat(2)] {
            let picture = try #require(
                OnboardingAuroraPicture.image(
                    mood: .brand, saturation: 1, size: size, scale: scale))
            for degrees in [0.0, 23.0, 90.0, 180.0] {
                let original = try #require(render(originalAurora(degrees: degrees), scale: scale))
                let cached = try #require(render(cachedAurora(picture, degrees: degrees), scale: scale))
                #expect(maximumChannelDifference(original, cached) <= Self.tolerance)
            }
        }
    }

    @Test("the same size and mood reuse the blurred picture")
    func cachedPictureIsReused() throws {
        let first = try #require(
            OnboardingAuroraPicture.image(mood: .brand, saturation: 1, size: size, scale: 1))
        let second = try #require(
            OnboardingAuroraPicture.image(mood: .brand, saturation: 1, size: size, scale: 1))
        #expect(first === second)
    }

    private func originalAurora(degrees: Double) -> some View {
        AngularGradient(
            colors: BrandPalette.Onboarding.brandAurora.map { Color(rgb: $0) }
                + BrandPalette.Onboarding.brandAurora.prefix(1).map { Color(rgb: $0) },
            center: UnitPoint(x: 0.35, y: 0.55),
            startAngle: .degrees(120), endAngle: .degrees(480)
        )
        .frame(width: size.width * 1.5, height: size.height * 1.5)
        .rotationEffect(.degrees(degrees))
        .blur(radius: 70)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func cachedAurora(_ picture: NSImage, degrees: Double) -> some View {
        let canvas = OnboardingAuroraPicture.canvasSize(for: size)
        return Image(nsImage: picture)
            .resizable()
            .interpolation(.high)
            .frame(width: canvas.width, height: canvas.height)
            .rotationEffect(.degrees(degrees))
            .position(x: size.width / 2, y: size.height / 2)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func render(_ view: some View, scale: CGFloat) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image)
    }

    private func maximumChannelDifference(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) -> CGFloat {
        guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh else {
            return 1
        }
        var largest: CGFloat = 0
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                guard let a = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    let b = second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { return 1 }
                largest = max(
                    largest,
                    max(
                        max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent)),
                        max(abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent)))
                )
            }
        }
        return largest
    }
}

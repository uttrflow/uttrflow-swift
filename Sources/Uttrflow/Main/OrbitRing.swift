// The bars of the ring under the greeting, as values and as a shape.

import SwiftUI

/// One bar of the ring: where it sits, how far it reaches, and which voice it is in.
struct OrbitTick: Equatable, Sendable {
    /// Clockwise from twelve o'clock, in turns: 0 is the top, 0.5 the bottom.
    let turn: Double
    /// How far out this bar reaches, from 0 at the ring's inner edge to 1 at its outer.
    let reach: Double
    let voice: OrbitVoice

    /// The heights the ring is made of, fixed so the ring does not reshuffle on every redraw.
    private static let reaches: [Double] = [
        0.22, 0.46, 0.68, 0.34, 0.82, 0.52, 0.30, 0.64, 0.92, 0.44, 0.72, 0.28,
        0.56, 0.86, 0.38, 0.62, 0.24, 0.50, 0.76, 0.32, 0.58, 0.88, 0.26, 0.48,
        0.36, 0.70, 0.42, 0.90, 0.54, 0.66, 0.20, 0.80, 0.60, 0.40, 0.74, 0.50,
    ]

    static func ring(count: Int) -> [OrbitTick] {
        (0..<max(count, 0)).map { index in
            OrbitTick(
                turn: Double(index) / Double(max(count, 1)),
                reach: reaches[index % reaches.count],
                voice: voice(at: index))
        }
    }

    /// One lit bar in three, alternating the two accents; denser reads as a colour wheel.
    private static func voice(at index: Int) -> OrbitVoice {
        switch index % 6 {
        case 2: .primary
        case 4: .secondary
        default: .quiet
        }
    }
}

/// Which colour a bar is drawn in, named for the job rather than the hue.
enum OrbitVoice: Equatable, Sendable {
    case primary
    case secondary
    case quiet
}

/// The ring itself: bars standing off a circle, each rotated about its centre.
struct OrbitRing: Shape {
    let ticks: [OrbitTick]
    /// Where the bars begin, as a share of the radius. The microphone sits inside this.
    var innerShare: CGFloat = 0.60
    var thickness: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerShare
        let span = outer - inner
        for tick in ticks {
            // A third of the span is floor, so even the shortest bar reads as a bar.
            let length = span * (0.34 + 0.66 * tick.reach)
            let bar = CGRect(
                x: -thickness / 2, y: -(inner + length), width: thickness, height: length)
            let placement = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: tick.turn * 2 * .pi)
            path.addPath(
                Path(roundedRect: bar, cornerRadius: thickness / 2), transform: placement)
        }
        return path
    }
}

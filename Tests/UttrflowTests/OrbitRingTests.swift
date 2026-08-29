import Foundation
import SwiftUI
import Testing

@testable import Uttrflow

/// The ring is drawn, so most of it is not worth a test. Its arrangement is: the bars are
/// the app's one piece of ornament, and an ornament that shifts between redraws, escapes
/// its own circle or turns into a solid wheel of colour is a bug nobody would think to
/// look for in a screenshot.
@Suite("The ring under the greeting")
struct OrbitRingTests {
    @Test("puts the bars evenly round the circle, starting at the top")
    func evenlySpaced() {
        let ticks = OrbitTick.ring(count: 8)

        #expect(ticks.count == 8)
        #expect(ticks.first?.turn == 0)
        for (index, tick) in ticks.enumerated() {
            #expect(abs(tick.turn - Double(index) / 8) < 0.000_001)
            #expect(tick.turn < 1, "a full turn would draw two bars on top of each other")
        }
    }

    /// A ring built from `Double.random` would be a different ring every time the page
    /// redrew — which is on every keystroke in the search field.
    @Test("draws the same ring every time")
    func deterministic() {
        #expect(OrbitTick.ring(count: 52) == OrbitTick.ring(count: 52))
    }

    @Test("keeps every bar inside the ring")
    func withinReach() {
        for tick in OrbitTick.ring(count: 52) {
            #expect(tick.reach > 0 && tick.reach <= 1)
        }
    }

    /// One in three lit, and the two accents in equal measure. Denser and it reads as a
    /// colour wheel; sparser and the accents look like a mistake in the drawing.
    @Test("keeps the lit bars a minority, evenly split between the two accents")
    func litBarsStayAMinority() {
        let ticks = OrbitTick.ring(count: 52)
        let quiet = ticks.filter { $0.voice == .quiet }
        let primary = ticks.filter { $0.voice == .primary }
        let secondary = ticks.filter { $0.voice == .secondary }

        #expect(quiet.count > ticks.count / 2)
        #expect(abs(primary.count - secondary.count) <= 1)
        #expect(primary.count + secondary.count + quiet.count == ticks.count)
    }

    /// The bars stand *off* a circle, so the easiest way to draw them wrongly is to
    /// rotate about the corner instead of the centre — which puts half the ring outside
    /// the space it was given and clips it away silently.
    @Test("draws inside the space it is given")
    func staysInsideItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let drawn = OrbitRing(ticks: OrbitTick.ring(count: 52)).path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -1, dy: -1).contains(drawn))
        #expect(drawn.width > 120, "a ring that fits in a corner is not a ring")
    }

    /// The microphone sits in the hole in the middle, so every bar has to start at the
    /// ring's inner edge and grow outwards. A bar drawn from the centre out would cover
    /// the one thing the ring is around.
    @Test("starts every bar at the inner edge and grows outwards")
    func leavesTheWellClear() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let inner = 100 * 0.6
        func bar(at turn: Double) -> CGRect {
            OrbitRing(
                ticks: [OrbitTick(turn: turn, reach: 1, voice: .quiet)],
                innerShare: 0.6, thickness: 4
            ).path(in: rect).boundingRect
        }

        // Twelve o'clock: the bar lives entirely above the middle.
        #expect(bar(at: 0).maxY <= rect.midY - inner + 0.001)
        // Three o'clock: the same bar, a quarter turn round, entirely to the right of it.
        #expect(bar(at: 0.25).minX >= rect.midX + inner - 0.001)
    }

    /// Asked for nothing, it draws nothing — rather than trapping on the division a
    /// count of zero would otherwise make.
    @Test("survives being asked for an empty ring")
    func empty() {
        #expect(OrbitTick.ring(count: 0).isEmpty)
        #expect(OrbitTick.ring(count: -3).isEmpty)
    }
}

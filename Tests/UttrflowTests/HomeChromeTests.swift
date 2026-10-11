// Tests for the home hero's picture fade and the collapsed sidebar's room for the traffic lights.

import AppKit
import Testing

@testable import Uttrflow

/// The stored property named `label`, read by reflection because the controller keeps it private.
private func stored<T>(_ label: String, of subject: Any, as type: T.Type) -> T? {
    Mirror(reflecting: subject).descendant(label) as? T
}

@MainActor
@Suite("Home chrome", .timeLimit(.minutes(1)), .serialized)
struct HomeChromeTests {
    @Test("the light fade eases in over more of the picture than the dark one")
    func lightFadeIsLongerAndEased() {
        let light = HomeMoodPicture.lightFade.map(\.location)
        #expect(light.first == 0)
        #expect(abs((light.last ?? 0) - 0.6) < 0.0001)
        #expect(light == light.sorted())
        #expect(HomeMoodPicture.darkFade.map(\.location) == [0, 0.42])
    }

    @Test("the collapsed sidebar is wide enough to hold the traffic lights")
    func railHoldsTheTrafficLights() throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())
        let controller = app.makeMainWindow()
        app.mainWindow = controller
        controller.show(.home)
        let window = try #require(stored("window", of: controller, as: NSWindow?.self) ?? nil)
        defer { window.close() }
        let zoom = try #require(window.standardWindowButton(.zoomButton))

        let right = zoom.convert(zoom.bounds, to: nil).maxX
        #expect(right + 6 <= MainMetrics.iconRailWidth)
    }
}

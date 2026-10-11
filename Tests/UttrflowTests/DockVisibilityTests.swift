// Tests that a hidden floating button draws nothing and reads no microphone level.

import Testing
import AppKit
import UttrflowPipeline

@testable import Uttrflow

@MainActor
@Suite("A hidden floating button")
struct DockVisibilityTests {
    private static func dock() -> DockPanelController {
        let dock = DockPanelController()
        dock.setLevelSource { 0.2 }
        return dock
    }

    @Test("draws nothing until it is first shown")
    func emptyUntilShown() {
        let dock = Self.dock()
        #expect(!dock.drawsContent)
        dock.show()
        defer { dock.hide() }
        #expect(dock.drawsContent)
    }

    @Test("empties itself when hidden, so no spinner or meter runs behind it")
    func emptiedWhenHidden() {
        let dock = Self.dock()
        dock.show()
        dock.update(with: DictationPresenter.dock(for: .tidying))
        dock.hide()
        #expect(!dock.isVisible)
        #expect(!dock.drawsContent)
    }

    @Test("reads the microphone for the meter only while it is on screen")
    func metersOnlyWhileShown() {
        let dock = Self.dock()
        dock.update(with: DictationPresenter.dock(for: .recording))
        #expect(!dock.isMetering)
        dock.show()
        #expect(dock.isMetering)
        dock.hide()
        #expect(!dock.isMetering)
        dock.show()
        #expect(dock.isMetering)
        dock.update(with: DictationPresenter.dock(for: .tidying))
        #expect(!dock.isMetering)
        dock.hide()
    }

    @Test("repositions inside the updated screen frame when display parameters change")
    func repositionsAfterScreenParametersChange() {
        let center = NotificationCenter()
        var visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let dock = DockPanelController(
            notificationCenter: center,
            visibleFrameProvider: { visibleFrame })
        dock.show()
        defer { dock.hide() }

        visibleFrame = CGRect(x: 0, y: 0, width: 900, height: 650)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(dock.frame.maxX == visibleFrame.maxX - DockPlacement.margin)
        #expect(dock.frame.minY == visibleFrame.minY + DockPlacement.margin)
        #expect(visibleFrame.contains(dock.frame))
    }

    @Test("re-anchors on the surviving display when its own display is unplugged")
    func reanchorsOnSurvivingDisplayAfterUnplug() {
        let center = NotificationCenter()
        let external = CGRect(x: -1920, y: -240, width: 1920, height: 1055)
        let builtIn = CGRect(x: 0, y: 84, width: 1512, height: 862)
        let displays = [external, builtIn]
        let attached = Box(0)
        let dock = DockPanelController(
            anchor: .bottomLeft, notificationCenter: center,
            visibleFrameProvider: { displays[attached.value] })
        dock.show()
        defer { dock.hide() }
        #expect(external.contains(dock.frame))

        attached.value = 1
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(builtIn.contains(dock.frame))
        #expect(dock.frame.minX == builtIn.minX + DockPlacement.margin)
        #expect(dock.frame.minY == builtIn.minY + DockPlacement.margin)
    }

    private final class Box: @unchecked Sendable {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    @Test("stays where it is when only focus or the pointer moves")
    func staysPutWithoutATopologyChange() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let dock = DockPanelController(visibleFrameProvider: { visibleFrame })
        dock.show()
        defer { dock.hide() }
        let placed = dock.frame

        dock.update(with: DictationPresenter.dock(for: .idle))
        dock.show()

        #expect(dock.frame == placed)
    }
}

import Testing
import UttrflowCore
import UttrflowUX

@Suite("Where a clip belongs after the panel closes")
struct PanelCaretTests {
    private func app(_ pid: Int32) -> InsertionDestination {
        InsertionDestination(applicationName: nil, bundleIdentifier: "test.app\(pid)", processIdentifier: pid)
    }

    private func resolved(frontmost: Int32?, focused: Int32?) -> Int32? {
        PanelCaret.destination(
            captured: app(1), frontmost: frontmost.map(app), focused: focused.map(app), ownProcess: 9
        ).processIdentifier
    }

    @Test("a floating panel holding focus over the same frontmost app is the target")
    func followsFocus() { #expect(resolved(frontmost: 1, focused: 2) == 2) }

    @Test("the plain case stays on the captured app")
    func plain() { #expect(resolved(frontmost: 1, focused: 1) == 1) }

    @Test("Uttrflow itself is never the target")
    func neverSelf() { #expect(resolved(frontmost: 1, focused: 9) == 1) }

    @Test("a real switch of frontmost app keeps the captured target, so the check still refuses")
    func switched() { #expect(resolved(frontmost: 3, focused: 3) == 1) }

    @Test("an unreadable answer keeps the captured target")
    func unreadable() {
        #expect(resolved(frontmost: nil, focused: 2) == 1)
        #expect(resolved(frontmost: 1, focused: nil) == 1)
    }
}

import Synchronization
import Testing

@testable import UttrflowInput

/// Stands in for the system's secure-input answer, which a test cannot turn on.
private final class SecureInputSwitch: Sendable {
    private let on = Mutex(false)

    var isOn: Bool {
        get { on.withLock { $0 } }
        set { on.withLock { $0 = newValue } }
    }
}

@Suite("Watching for secure keyboard entry")
@MainActor
struct SecureInputWatchTests {
    @Test("announces an episode once, however often it is checked, and its end once")
    func oncePerEpisode() {
        let secure = SecureInputSwitch()
        let watch = SecureInputWatch { secure.isOn }

        #expect(!watch.check(), "nothing to say while the shortcut can be heard")
        #expect(!watch.isBlocking)

        secure.isOn = true
        #expect(watch.check())
        #expect(watch.isBlocking)
        #expect(!watch.check(), "the same episode is not announced twice")

        secure.isOn = false
        #expect(watch.check())
        #expect(!watch.isBlocking)
    }

    @Test("says in words what to do instead of the shortcut")
    func noticeNamesTheWayAround() {
        #expect(SecureInputWatch.notice.contains("secure keyboard entry"))
        #expect(SecureInputWatch.notice.contains("menu bar"))
    }

    @Test("asks the system by default, which answers without side effects")
    func systemAnswer() {
        let watch = SecureInputWatch()
        #expect(watch.check() == watch.isBlocking)
    }
}

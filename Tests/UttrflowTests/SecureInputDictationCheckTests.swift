// Tests that a dictation press asks about secure keyboard entry, so the notice needs no timer.

import Foundation
import Synchronization
import UttrflowPipeline
import UttrflowInput
import Testing

@testable import Uttrflow

@MainActor
@Suite("A dictation press checks secure keyboard entry")
struct SecureInputDictationCheckTests {
    @Test("a dictation that fails while secure input is on shows the notice, and the next one clears it")
    func failedDictationRaisesAndClearsTheNotice() {
        let sandbox = Sandbox()
        let on = Mutex(false)
        let app = AppDelegate(
            container: sandbox.root,
            secureInput: SecureInputWatch(isSecureInputOn: { on.withLock { $0 } }))
        #expect(app.shortcutUnheard == nil)

        on.withLock { $0 = true }
        app.render(
            .failed(DictationFailure(message: "Not inserted", recovery: .retry, severity: .recoverable)))
        #expect(app.shortcutUnheard == SecureInputWatch.notice)

        on.withLock { $0 = false }
        app.render(.recording)
        #expect(app.shortcutUnheard == nil)
    }
}

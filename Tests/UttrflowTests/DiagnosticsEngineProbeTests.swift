// The Diagnostics page said "Not checked yet" forever, because nothing ever checked.

import Foundation
import Testing
import UttrflowCore

@testable import Uttrflow

@MainActor
@Suite("The clean-up engines Diagnostics reports on", .timeLimit(.minutes(1)))
struct DiagnosticsEngineProbeTests {
    /// Starts the probe and waits for it to finish, which it does on a task of its own.
    private func probed(_ app: AppDelegate) async -> [TransformerKind: Bool] {
        await app.probeTransformers().value
        return app.transformerAvailability
    }

    /// #152: the snapshot's availability was never populated, so every row read `nil`.
    @Test("are asked, so the page has an answer rather than a pending check")
    func areAsked() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        #expect(app.transformerAvailability.isEmpty)

        let answered = await probed(app)
        #expect(!answered.isEmpty, "nothing was asked, so the page would say Not checked yet")
        // The floor can always run, whatever else this Mac has.
        #expect(answered[.rules] == true)
    }

    @Test("and every kind gets an answer, not only the ones that said yes")
    func everyKindIsAnswered() async {
        let app = AppDelegate(container: Sandbox().root)
        let answered = await probed(app)

        for kind in TransformerKind.allCases {
            #expect(answered[kind] != nil, "\(kind.rawValue) was left unanswered")
        }
    }
}

// The Diagnostics page said "Not checked yet" forever, because nothing ever checked.

import Foundation
import Testing
import UttrflowCore

@testable import Uttrflow

@MainActor
@Suite("The clean-up engines Diagnostics reports on")
struct DiagnosticsEngineProbeTests {
    /// Waits for the probe, which runs beside the test rather than inside it.
    private func settled(_ app: AppDelegate) async -> [TransformerKind: Bool] {
        for _ in 0..<200 where app.transformerAvailability.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return app.transformerAvailability
    }

    /// #152: the snapshot's availability was never populated, so every row read `nil`.
    @Test("are asked, so the page has an answer rather than a pending check")
    func areAsked() async {
        let app = AppDelegate(container: Sandbox().root)
        #expect(app.transformerAvailability.isEmpty)

        app.probeTransformers()

        let answered = await settled(app)
        #expect(!answered.isEmpty, "nothing was asked, so the page would say Not checked yet")
        // The floor can always run, whatever else this Mac has.
        #expect(answered[.rules] == true)
    }

    @Test("and every kind gets an answer, not only the ones that said yes")
    func everyKindIsAnswered() async {
        let app = AppDelegate(container: Sandbox().root)
        app.probeTransformers()
        let answered = await settled(app)

        for kind in TransformerKind.allCases {
            #expect(answered[kind] != nil, "\(kind.rawValue) was left unanswered")
        }
    }
}

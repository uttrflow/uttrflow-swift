import Foundation
import Testing
import UttrflowUX

@testable import Uttrflow

@Suite("Quick panel intent routing")
struct QuickPanelIntentRoutingTests {
    private let sheet = PanelSheetPresentation(
        kind: .confirmingMakeNote,
        title: "Make this clip a note?",
        draft: "",
        placeholder: "",
        note: nil,
        conflict: nil,
        collections: [],
        confirmTitle: "Make note",
        isConfirmEnabled: true)

    @Test("panel intents wait until the sheet closes")
    func intentsWaitForSheet() {
        let intents: [PanelIntent] = [
            .pin(UUID()), .markSecret(UUID()), .undoDelete,
        ]
        for intent in intents {
            var received: PanelIntent?
            PanelIntentRouting.forward(intent, through: sheet) { received = $0 }
            #expect(received == nil, "\(intent)")

            PanelIntentRouting.forward(intent, through: nil) { received = $0 }
            #expect(received == intent, "\(intent)")
        }
    }
}

import Testing
import UttrflowUX

@Suite("Panel intents keep their routing contract")
struct PanelIntentRoutingTests {
    @Test("editing and collection actions retain their keyboard routes")
    func keyboardRoutesPreserveTargets() {
        let id = PanelFixture.clips[0].id
        #expect(PanelIntent.alias(id).key == .alias(id))
        #expect(PanelIntent.move(id).key == .move(id))
        #expect(PanelIntent.delete(id).key == .delete(id))
        #expect(PanelIntent.makeNote(id).key == .makeNote(id))
        #expect(PanelIntent.renameCategory("Notes").key == .renameCategory("Notes"))
        #expect(PanelIntent.deleteCategory("Notes").key == .deleteCategory("Notes"))
        #expect(PanelIntent.format(id).key == nil)
    }

    @Test("only direct store actions produce immediate changes")
    func immediateChangesPreserveTargets() {
        let id = PanelFixture.clips[0].id
        #expect(PanelIntent.pin(id).immediateChange == .setPinned(id, true))
        #expect(PanelIntent.unpin(id).immediateChange == .setPinned(id, false))
        #expect(PanelIntent.markNotSecret(id).immediateChange == .setSecret(id, false))
        #expect(PanelIntent.markSecret(id).immediateChange == .setSecret(id, true))
        #expect(PanelIntent.delete(id).immediateChange == nil)
    }
}

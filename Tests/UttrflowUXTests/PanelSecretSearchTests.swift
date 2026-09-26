// Tests that a masked secret is never found by the text it hides.
import Foundation
import Testing

@testable import UttrflowUX

/// A masked row says nothing about its hidden text, including whether a query is inside it.
@Suite("Searching a masked secret")
struct PanelSecretSearchTests {
    static let secret = PanelFixture.clip(
        "tok-example-9f3k", kind: .secret, minutesAgo: 1, alias: "staging token")

    @Test("a fragment of a masked secret's text does not find it")
    func hiddenTextIsNotSearched() {
        let panel = PanelFixture.panel([Self.secret], query: "9f3k")

        #expect(panel.results.rows.isEmpty)
        #expect(PanelPresenter.present(panel).groups.isEmpty)
    }

    @Test("a masked secret is still found by its alias")
    func aliasStillFinds() {
        let rows = PanelFixture.panel([Self.secret], query: "staging").results.rows

        #expect(rows.map(\.match) == [.alias])
    }

    @Test("revealing the secret restores search by its text")
    func revealRestoresSearch() {
        let rows = PanelFixture.panel([Self.secret], query: "9f3k", revealed: [Self.secret.id])
            .results.rows

        #expect(rows.map(\.match) == [.content])
    }

    /// The memo must not reuse a masked scan once the clip is revealed under the same query.
    @Test("revealing under the same query searches the text again")
    func revealInvalidatesTheMemo() {
        var panel = PanelFixture.panel([Self.secret], query: "9f3k")
        #expect(panel.results.rows.isEmpty)

        panel.revealed.insert(Self.secret.id)

        #expect(panel.results.rows.map(\.match) == [.content])
    }
}

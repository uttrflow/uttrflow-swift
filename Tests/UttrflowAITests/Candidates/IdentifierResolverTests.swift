import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Identifier binding: a spoken run named by the one identifier on screen")
struct IdentifierResolverTests {
    private func bind(_ spoken: String, to shown: [String]) -> IdentifierResolver.Binding {
        IdentifierResolver.bind(
            spokenWords: spoken.split(separator: " ").map(String.init),
            vocabulary: ScreenVocabulary(identifiers: shown))
    }

    @Test("binds the words that spell an identifier with their spaces closed up")
    func bindsByExactWords() {
        #expect(bind("order totals", to: ["orderTotals"]) == .bound("orderTotals"))
    }

    @Test("binds a snake-case or Pascal-case spelling of the same words")
    func bindsBySpellingVariant() {
        #expect(bind("order totals", to: ["order_totals"]) == .bound("order_totals"))
        #expect(bind("order totals", to: ["OrderTotals"]) == .bound("OrderTotals"))
    }

    @Test("binds an identifier that sounds and opens like the run")
    func bindsBySoundAlike() {
        #expect(bind("cash store", to: ["CacheStore"]) == .bound("CacheStore"))
    }

    @Test("refuses when two identifiers on screen spell the run")
    func refusesATie() {
        #expect(
            bind("order totals", to: ["orderTotals", "order_totals"])
                == .ambiguous(["orderTotals", "order_totals"]))
    }

    @Test("refuses a near miss that neither spells nor sounds like the run")
    func refusesANearMiss() {
        #expect(bind("aarav", to: ["aaronId", "AaronKit"]) == .none)
    }

    @Test("never binds to prose on screen, only to words shaped like identifiers")
    func readsOnlyIdentifiers() {
        let shown = ScreenVocabulary(identifiers: ["Aaron", "order", "orderTotals", "_cache_key", "x_y"])
        #expect(shown.identifiers == ["orderTotals", "x_y"])
        #expect(bind("aaron", to: ["Aaron"]) == .none)
    }

    @Test("reads identifiers off the title, the selection and the text at the caret")
    func readsTheScreen() {
        let app = AppContext(
            documentName: "revenue.sql — order_totals", selectedText: "fetchInvoices()",
            precedingText: "SELECT * FROM __private_rows ", followingText: " WHERE x")
        let read = ScreenVocabulary(
            Situation(app: app, insertion: app.insertionPoint, destination: .sqlEditor))
        #expect(read.identifiers == ["order_totals", "fetchInvoices", "private_rows"])
    }

    @Test("binds nothing when the screen shows no identifier")
    func bindsNothingWithoutAScreen() {
        #expect(bind("order totals", to: []) == .none)
        #expect(ScreenVocabulary(Situation.unknown).identifiers.isEmpty)
    }
}

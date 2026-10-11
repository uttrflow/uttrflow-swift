import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Naming convention: the case a file writes each kind of name in")
struct NamingConventionTests {
    private func convention(_ shown: [String], _ language: CodeLanguage?) -> NamingConvention {
        NamingConvention.infer(from: ScreenVocabulary(identifiers: shown), language: language)
    }

    private let words = ["get", "user", "by", "id"]

    @Test("reads the style an identifier is written in")
    func readsStyles() {
        #expect(NameStyle(identifier: "orderTotals") == .camel)
        #expect(NameStyle(identifier: "OrderTotals") == .pascal)
        #expect(NameStyle(identifier: "order_totals") == .snake)
        #expect(NameStyle(identifier: "MAX_RETRIES") == .screamingSnake)
        #expect(NameStyle(identifier: "_order_totals") == .snake)
        #expect(NameStyle(identifier: "order") == nil)
        #expect(NameStyle(identifier: "URL") == nil)
        #expect(NameStyle(identifier: "Order_Totals") == nil)
        #expect(NameStyle(identifier: "9lives") == nil)
    }

    @Test("writes the same words in every style")
    func writesEveryStyle() {
        #expect(NameStyle.camel.write(words) == "getUserById")
        #expect(NameStyle.pascal.write(words) == "GetUserById")
        #expect(NameStyle.snake.write(words) == "get_user_by_id")
        #expect(NameStyle.screamingSnake.write(words) == "GET_USER_BY_ID")
        #expect(NameStyle.kebab.write(words) == "get-user-by-id")
        #expect(NameStyle.camel.write(["Get", "USER"]) == "getUser")
    }

    @Test("a convention shown on screen agrees with each of the six languages")
    func presentInSixLanguages() {
        let cases: [(CodeLanguage, [String], NameStyle, NameStyle)] = [
            (.swift, ["fetchInvoices", "orderTotals", "InvoiceStore"], .camel, .pascal),
            (.python, ["fetch_invoices", "order_totals", "InvoiceStore"], .snake, .pascal),
            (.javascript, ["fetchInvoices", "orderTotals", "InvoiceStore"], .camel, .pascal),
            (.go, ["fetchInvoices", "orderTotals", "InvoiceStore"], .camel, .pascal),
            (.rust, ["fetch_invoices", "order_totals", "InvoiceStore"], .snake, .pascal),
            (.java, ["fetchInvoices", "orderTotals", "InvoiceStore"], .camel, .pascal),
        ]
        for (language, shown, value, type) in cases {
            let found = convention(shown, language)
            #expect(found.style(for: .value) == value, "\(language) value")
            #expect(found.style(for: .type) == type, "\(language) type")
            #expect(found.name(words, role: .value) == value.write(words), "\(language) name")
        }
    }

    @Test("an empty screen falls back to the language default in each of the six languages")
    func absentInSixLanguages() {
        let expected: [(CodeLanguage, String, String)] = [
            (.swift, "getUserById", "GetUserById"), (.python, "get_user_by_id", "GetUserById"),
            (.javascript, "getUserById", "GetUserById"), (.go, "getUserById", "GetUserById"),
            (.rust, "get_user_by_id", "GetUserById"), (.java, "getUserById", "GetUserById"),
        ]
        for (language, value, type) in expected {
            let found = convention([], language)
            #expect(found.name(words, role: .value) == value, "\(language) value")
            #expect(found.name(words, role: .type) == type, "\(language) type")
        }
        #expect(convention([], .rust).name(words, role: .constant) == "GET_USER_BY_ID")
    }

    @Test("a file that contradicts its language default is followed when it shows the habit twice")
    func contradictingInSixLanguages() {
        let snakeFile = ["fetch_invoices", "order_totals"]
        let camelFile = ["fetchInvoices", "orderTotals"]
        for language in [CodeLanguage.swift, .javascript, .go, .java] {
            let found = convention(snakeFile, language)
            #expect(found.name(words, role: .value) == "get_user_by_id", "\(language)")
        }
        for language in [CodeLanguage.python, .rust] {
            let found = convention(camelFile, language)
            #expect(found.name(words, role: .value) == "getUserById", "\(language)")
        }
    }

    @Test("one contradicting identifier does not overturn the default")
    func oneIsNotAHabit() {
        #expect(convention(["fetch_invoices"], .swift).name(words, role: .value) == "getUserById")
    }

    @Test("a tie on screen keeps the language default")
    func tieKeepsDefault() {
        let found = convention(["fetch_invoices", "order_totals", "fetchInvoices", "orderTotals"], .python)
        #expect(found.name(words, role: .value) == "get_user_by_id")
    }

    @Test("a screen constant style is followed against the default")
    func constantStyle() {
        let found = convention(["MAX_RETRIES", "DEFAULT_LIMIT"], .swift)
        #expect(found.name(words, role: .constant) == "GET_USER_BY_ID")
    }

    @Test("with no language the screen decides alone, and with neither the words stay as spoken")
    func noLanguage() {
        #expect(convention(["fetch_invoices"], nil).name(words, role: .value) == "get_user_by_id")
        #expect(convention(["InvoiceStore"], nil).name(words, role: .type) == "GetUserById")
        #expect(convention([], nil).name(words, role: .value) == nil)
        #expect(convention([], .sql).name(words, role: .value) == nil)
    }

    @Test("an explicit style wins over the file and over no convention at all")
    func explicitWins() {
        let snakeInCamelFile = convention(["fetchInvoices", "orderTotals"], .swift)
            .name(words, role: .value, explicit: .snake)
        #expect(snakeInCamelFile == "get_user_by_id")
        #expect(convention([], nil).name(words, role: .value, explicit: .kebab) == "get-user-by-id")
    }

    @Test("words that are not plain words are never joined")
    func refusesOddWords() {
        let found = convention([], .swift)
        #expect(found.name([], role: .value) == nil)
        #expect(found.name(["get", "user's"], role: .value) == nil)
        #expect(found.name(["get", "id,"], role: .value) == nil)
    }
}

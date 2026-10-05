// Tests for reading a text as the amounts it states.

import Testing

@testable import UttrflowAI

@Suite("Reading amounts")
struct QuantityTests {
    @Test(
        "reads a number with the symbol attached to it",
        arguments: [
            ("revenue grew 5%", [Quantity(digits: "5", symbol: "%")]),
            ("the invoice is $500", [Quantity(digits: "500", symbol: "$")]),
            ("the gap is 20\u{00B0}", [Quantity(digits: "20", symbol: "\u{00B0}")]),
            ("temperature fell to -5 degrees", [Quantity(digits: "5", sign: "-", symbol: "")]),
            ("the balance is +500 dollars", [Quantity(digits: "500", sign: "+", symbol: "")]),
            ("the error was -3.5%", [Quantity(digits: "3.5", sign: "-", symbol: "%")]),
            ("the refund is -$12.50", [Quantity(digits: "12.50", sign: "-", symbol: "$")]),
            ("the credit is $+500", [Quantity(digits: "500", sign: "+", symbol: "$")]),
            ("i need 20 chairs", [Quantity(digits: "20", symbol: "")]),
            ("the budget is 50K", [Quantity(digits: "50000", symbol: "")]),
            ("we raised $2.5M", [Quantity(digits: "2500000", symbol: "$")]),
            ("we sold 5 million units", [Quantity(digits: "5000000", symbol: "")]),
            ("it costs 3 lakh", [Quantity(digits: "300000", symbol: "")]),
            ("we ran 5m", [Quantity(digits: "5", symbol: "")]),
            // One space is tolerated, since a model writing "5 %" means the percentage.
            ("revenue grew 5 %", [Quantity(digits: "5", symbol: "%")]),
        ]
    )
    func readsAnAmount(text: String, expected: [Quantity]) {
        #expect(Quantities.read(in: text) == expected)
    }

    /// The separator is a way of writing the number, not part of it, so both spellings are one amount.
    @Test("reads a thousands separator as part of the number")
    func readsASeparator() {
        #expect(Quantities.read(in: "we sold 12,000 units") == [Quantity(digits: "12000", symbol: "")])
        #expect(
            Quantities.read(in: "it cost $12,000") == [Quantity(digits: "12000", symbol: "$")])
        #expect(
            Quantities.read(in: "the delta was -1,234.50")
                == [Quantity(digits: "1234.50", sign: "-", symbol: "")])
    }

    @Test("does not read binary subtraction or hyphenated prose as signed quantities")
    func leavesBinaryAndHyphenatedNumbersUnsigned() {
        #expect(
            Quantities.read(in: "subtract 5-3") == [
                Quantity(digits: "5", symbol: ""), Quantity(digits: "3", symbol: ""),
            ])
        #expect(
            Quantities.read(in: "subtract 5 -3") == [
                Quantity(digits: "5", symbol: ""), Quantity(digits: "3", symbol: ""),
            ])
        #expect(Quantities.read(in: "ticket-5 is ready") == [Quantity(digits: "5", symbol: "")])
    }

    @Test("reads every amount in the order the text states them")
    func readsEveryAmountInOrder() {
        #expect(
            Quantities.read(in: "5% of 20 rooms cost $300")
                == [
                    Quantity(digits: "5", symbol: "%"), Quantity(digits: "20", symbol: ""),
                    Quantity(digits: "300", symbol: "$"),
                ])
    }

    @Test("finds nothing in a text that states no number")
    func findsNothingInProse() {
        #expect(Quantities.read(in: "no numbers here at all").isEmpty)
    }

    @Test("names an amount the way it is written")
    func namesItAsWritten() {
        #expect(Quantity(digits: "5", symbol: "%").written == "5%")
        #expect(Quantity(digits: "500", symbol: "$").written == "$500")
        #expect(Quantity(digits: "500", sign: "-", symbol: "$").written == "-$500")
        #expect(Quantity(digits: "3.5", sign: "-", symbol: "%").written == "-3.5%")
        #expect(Quantity(digits: "20", symbol: "").written == "20")
    }
}

@Suite("The guard reads an amount, not a digit run")
struct QuantityGuardTests {
    @Test(
        "refuses a rewrite that dropped the symbol on a number",
        arguments: [
            ("revenue grew 5%", "Revenue grew 5."),
            ("the invoice is $500", "The invoice is 500."),
            ("the gap is 20\u{00B0}", "The gap is 20."),
            ("temperature fell to -5 degrees", "Temperature fell to 5 degrees."),
            ("temperature fell to 5 degrees", "Temperature fell to -5 degrees."),
            ("the balance is +500 dollars", "The balance is 500 dollars."),
            ("the error was -3.5%", "The error was 3.5%."),
            ("the refund is -$12.50", "The refund is $12.50."),
            // Moved from one number to another, which the digit check cannot see either.
            ("5% of 20 rooms", "5 of 20% rooms."),
        ]
    )
    func refusesADroppedSymbol(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.changedQuantity(original: kept, rewritten: rewritten) != nil)
    }

    @Test("refuses a symbol the rewrite attached to a number that had none")
    func refusesAnInventedSymbol() {
        #expect(
            MeaningPreservationGuard.changedQuantity(
                original: "i need 20 chairs", rewritten: "I need 20% chairs.") != nil)
    }

    @Test(
        "says nothing about a rewrite that kept every amount as it was",
        arguments: [
            ("revenue grew 5%", "Revenue grew 5%."),
            ("the invoice is $500", "The invoice is $500."),
            ("temperature fell to -5 degrees", "Temperature fell to -5 degrees."),
            ("the balance is +500 dollars", "The balance is +500 dollars."),
            ("the refund is -$12.50", "The refund is -$12.50."),
            ("we sold 12,000 units", "We sold 12,000 units."),
            // The separator is a spelling, and the passes may write either.
            ("we sold 12,000 units", "We sold 12000 units."),
            ("i need 20 chairs", "I need 20 chairs."),
            ("no numbers here", "No numbers here."),
        ]
    )
    func acceptsAnAmountKept(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.changedQuantity(original: kept, rewritten: rewritten) == nil)
    }

    @Test(
        "reads a comma as a separator only where it groups the digits",
        arguments: [
            ("12,345", ["12345"]),
            ("1,234,567", ["1234567"]),
            ("999,999", ["999999"]),
            ("1,50,000", ["150000"]),
            ("12,00,00,000", ["120000000"]),
            ("1,234.50", ["1234.50"]),
            ("1,00,000.75", ["100000.75"]),
            ("10,20,30", ["10", "20", "30"]),
            ("3,4,5", ["3", "4", "5"]),
            ("1,23", ["1", "23"]),
            ("12,34", ["12", "34"]),
            ("1,2345", ["1", "2345"]),
            ("1234,567", ["1234", "567"]),
            ("100,200,30", ["100", "200", "30"]),
            ("40.7128,74.0060", ["40.7128", "74.0060"]),
            ("40.7128,-74.0060", ["40.7128", "74.0060"]),
            ("1.5,200", ["1.5", "200"]),
            ("10,20,2.5", ["10", "20", "2.5"]),
            ("7,8 and 12,000", ["7", "8", "12000"]),
            ("12,000, 13,000", ["12000", "13000"]),
        ]
    )
    func readsGroupingCommas(text: String, expected: [String]) {
        #expect(Quantities.read(in: text).map(\.digits) == expected)
    }
}

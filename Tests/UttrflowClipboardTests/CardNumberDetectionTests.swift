// Tests for recognising a card number, and for leaving every other long number alone.

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

/// Every card number below is a network's published test number, never a real card.
@Suite("Card numbers are hidden, and other long numbers are not")
struct CardNumberDetectionTests {
    @Test(
        "masks a test card number however it was written",
        arguments: [
            "4111 1111 1111 1111",
            "4111111111111111",
            "4111-1111-1111-1111",
            "5500-0000-0000-0004",
            "5555 5555 5555 4444",
            "2223 0031 2200 3222",
            "3782 822463 10005",
            "378282246310005",
            "6011 1111 1111 1117",
            "3530 1113 3330 0000",
            "3056 930902 5904",
            "4222222222222",
            "4222 222 222 222",
            "4222-222-222-222",
            "6200000000000005",
            "8100000000000002",
            "2200000000000004",
            "4111 1111 1111 1111 003",
            "  4111 1111 1111 1111\n",
        ])
    func cardNumbers(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
        #expect(SecretShapes.matches(text))
    }

    @Test(
        "masks a card number grouped by another space or a full stop, or typed in fullwidth digits",
        arguments: [
            "4111\u{A0}1111\u{A0}1111\u{A0}1111",
            "4111\u{2009}1111\u{2009}1111\u{2009}1111",
            "4111\u{202F}1111\u{202F}1111\u{202F}1111",
            "4111\t1111\t1111\t1111",
            "4111.1111.1111.1111",
            "\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
                + "\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
            "\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{3000}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{3000}"
                + "\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{3000}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
            "Card: 4111\u{A0}1111\u{A0}1111\u{A0}1111, expires 12/29",
        ])
    func otherSeparators(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
        #expect(CardNumberShape.matches(text) == BacktrackingPatterns.hasCardNumber(text))
    }

    @Test(
        "masks a card number grouped by any Unicode horizontal space",
        arguments: [
            "\u{A0}", "\u{2009}", "\u{202F}", "\u{3000}", "\t",
        ])
    func horizontalSpaceSeparators(_ separator: String) {
        let text = ["4111", "1111", "1111", "1111"].joined(separator: separator)
        #expect(ClipKindDetector.kind(of: text) == .secret, "\(text.debugDescription)")
        #expect(CardNumberShape.matches(text) == BacktrackingPatterns.hasCardNumber(text))
    }

    @Test(
        "masks fullwidth digits grouped by a fullwidth hyphen or full stop",
        arguments: ["\u{FF0D}", "\u{FF0E}"])
    func fullwidthSeparators(_ separator: String) {
        let group = "\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
        let text = ["\u{FF14}\u{FF11}\u{FF11}\u{FF11}", group, group, group].joined(separator: separator)
        #expect(ClipKindDetector.kind(of: text) == .secret, "\(text.debugDescription)")
        #expect(CardNumberShape.matches(text) == BacktrackingPatterns.hasCardNumber(text))
    }

    @Test(
        "leaves line-broken and fullwidth numbers that are not cards alone",
        arguments: [
            // A column of numbers, a mixed grouping and a failed Luhn check
            "1234\n5678\n9012\n3456",
            "Invoices:\n4539\n1488\n0343\n6467\n",
            "4539\u{2028}1488\u{2028}0343\u{2028}6467",
            "4539\r\n1488\r\n0343\r\n6467",
            "4111\n1111 1111 1111",
            "4111\u{2028}1111\u{2028}1111\u{2028}1112",
            "2024\n2025\n2026\n2027",
            // Phone numbers
            "+1\u{2028}415\u{2028}555\u{2028}0142",
            "\u{FF0B}\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
                + "\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
            // Dates and times
            "\u{FF12}\u{FF10}\u{FF12}\u{FF16}\u{FF0D}\u{FF10}\u{FF19}\u{FF0D}\u{FF11}\u{FF13}",
            "2026\u{85}09\u{85}13\u{85}12:30:45",
            // Version strings
            "\u{FF11}\u{FF0E}\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF0E}\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
                + "\u{FF0E}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF0E}\u{FF11}\u{FF11}\u{FF11}\u{FF11}",
            "v1.2.3\u{2028}v4.5.6\u{2028}v7.8.9",
            // Ordinary numbers
            "1700000000000\u{0B}20240913123045",
            "12\u{2029}34\u{2029}56\u{2029}78\u{2029}90\u{2029}12\u{2029}34\u{2029}56",
        ])
    func lineBrokenAndFullwidthNonCards(_ text: String) {
        #expect(!CardNumberShape.matches(text), "\(text.debugDescription)")
        #expect(ClipKindDetector.kind(of: text) != .secret, "\(text.debugDescription)")
    }

    @Test(
        "still leaves a mixed grouping, a decimal and a version alone",
        arguments: [
            "4111 1111\u{A0}1111.1111",
            "4111.1111.1111.1112",
            "4111111111111111.25",
            "1.4111.1111.1111.1111",
            "\u{FF14}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
                + "\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF12}",
        ])
    func otherSeparatorsStillNeedACard(_ text: String) {
        #expect(!CardNumberShape.matches(text), "\(text)")
    }

    @Test(
        "masks a card number inside a longer copy",
        arguments: [
            "Card: 4111 1111 1111 1111, expires 12/29",
            "card=4111111111111111;",
            "Pay with 5555-5555-5555-4444.",
            "Name on card\n4111 1111 1111 1111\nCVV on the back",
        ])
    func cardNumbersInText(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    /// Phone numbers, ISBNs, UUIDs, order numbers, timestamps and dates: each is long and numeric, none is a card.
    @Test(
        "leaves other long numbers alone",
        arguments: [
            // Phone numbers
            "+1 415 555 0142",
            "+91 98765 43210",
            "(415) 555-0142",
            "0044 20 7946 0958",
            "+4111111111111111",
            // ISBNs
            "978-0-306-40615-7",
            "9780306406157",
            // UUIDs
            "123e4567-e89b-12d3-a456-426614174000",
            "00000000-0000-4000-8000-000000000000",
            // Order and account numbers, the first three passing Luhn under no network's prefix
            "1234567812345670",
            "0000000000000000",
            "1111 1111 1111 1117",
            "403-1234567-1234567",
            "ORD-20240913-4111",
            "41111111111111111111111",
            "4111-1111-1111-1111-2222",
            // Timestamps and dates
            "1700000000000",
            "1700000000000000",
            "20240913123045",
            "2026-09-13 12:30:45",
            "2026-09-13T12:30:45.123456Z",
            "13/09/2026",
            "4111111111111111.25",
            // A network's prefix that fails Luhn
            "4111 1111 1111 1112",
            "4111111111111112",
        ])
    func otherLongNumbers(_ text: String) {
        #expect(!CardNumberShape.matches(text), "\(text)")
        #expect(ClipKindDetector.kind(of: text) != .secret, "\(text)")
    }
}

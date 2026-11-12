import Testing
import UttrflowCore

@testable import UttrflowAI

/// Identifiers whose number is part of a name: a version, a model or a numbered place, written in digits under either policy.
@Suite("NumberFormsPass carriers")
struct NumberCarrierTests {
    static let identifiers: [(String, String)] = [
        ("python three", "python 3"),
        ("python three point twelve", "python 3.12"),
        ("ios sixteen", "ios 16"),
        ("ios seventeen point two", "ios 17.2"),
        ("macos fourteen", "macos 14"),
        ("android twelve", "android 12"),
        ("windows ten", "windows 10"),
        ("windows eleven", "windows 11"),
        ("java eight", "java 8"),
        ("java twenty one", "java 21"),
        ("node eighteen", "node 18"),
        ("debian twelve", "debian 12"),
        ("kotlin two", "kotlin 2"),
        ("php eight point three", "php 8.3"),
        ("perl five", "perl 5"),
        ("ruby three point three", "ruby 3.3"),
        ("swift five point nine", "swift 5.9"),
        ("gpt four", "gpt 4"),
        ("iphone fifteen", "iphone 15"),
        ("ipad ten", "ipad 10"),
        ("pixel eight", "pixel 8"),
        ("postgres sixteen", "postgres 16"),
        ("mysql eight", "mysql 8"),
        ("fedora forty", "fedora 40"),
        ("model three", "model 3"),
        ("route eight", "route 8"),
        ("gate twelve", "gate 12"),
        ("port eighty eighty", "port 8080"),
        ("line four", "line 4"),
        ("room two", "room 2"),
    ]

    @Test("writes a carrier's number in digits, run together, under either policy", arguments: identifiers)
    func identifier(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test("names the identifier inside a sentence")
    func inSentence() {
        #expect(
            cleaned("we still run python three on the build machine", by: NumberFormsPass())
                == "we still run python 3 on the build machine")
        #expect(
            cleaned("the app needs ios sixteen or later", by: NumberFormsPass())
                == "the app needs ios 16 or later")
    }

    @Test(
        "keeps a number that counts, or that a carrier does not name, as the policy writes it",
        arguments: [
            ("three windows", "three windows"),
            ("one python", "one python"),
            ("two androids", "two androids"),
            ("i ran python three times", "i ran python three times"),
            ("the windows on two floors", "the windows on two floors"),
            ("python. three of them failed", "python. three of them failed"),
            ("we feed python three small mice", "we feed python three small mice"),
            ("we feed python three of the mice", "we feed python three of the mice"),
        ]
    )
    func counts(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }

    @Test("reads every carrier from the table, so adding one is a data change")
    func carriersAreData() {
        #expect(NumberCues.words(for: .versionCarrier).isSuperset(of: ["python", "ios", "windows", "gpt"]))
    }
}

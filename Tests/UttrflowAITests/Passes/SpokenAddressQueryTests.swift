import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken query string or fragment after a written address")
struct SpokenAddressQueryTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "writes the query and fragment said after an address exactly as spoken",
        arguments: [
            (
                "open example dot com slash search question mark q equals shoes",
                "open example.com/search?q=shoes"
            ),
            (
                "open example dot com slash search question mark q equals shoes ampersand page equals two",
                "open example.com/search?q=shoes&page=two"
            ),
            (
                "open example dot com slash search question mark q equals shoes ampersand page equals two ampersand sort equals price",
                "open example.com/search?q=shoes&page=two&sort=price"
            ),
            (
                "open example dot com slash search question mark page equals 2",
                "open example.com/search?page=2"
            ),
            ("open example dot com slash docs hash install", "open example.com/docs#install"),
            (
                "open example dot com slash docs slash setup hash step two",
                "open example.com/docs/setup#step two"
            ),
            (
                "open example dot com slash search question mark q equals shoes hash results",
                "open example.com/search?q=shoes#results"
            ),
            (
                "open example dot com colon eight thousand slash search question mark q equals shoes",
                "open example.com:8000/search?q=shoes"
            ),
            (
                "open example dot com question mark ref equals home",
                "open example.com?ref=home"
            ),
            ("open example dot com hash top", "open example.com#top"),
            (
                "open https colon slash slash example dot com slash search question mark q equals shoes ampersand page equals two",
                "open https://example.com/search?q=shoes&page=two"
            ),
            (
                "open localhost colon three thousand slash admin question mark tab equals users",
                "open localhost:3000/admin?tab=users"
            ),
            (
                "open ten dot zero dot zero dot one slash status question mark verbose equals true",
                "open 10.0.0.1/status?verbose=true"
            ),
            (
                "open www dot example dot com slash search question mark q equals shoes",
                "open www.example.com/search?q=shoes"
            ),
        ]
    )
    func writesQueryAndFragment(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("ends the address at the last good pair and leaves the rest as words")
    func stopsAtTheLastGoodPair() {
        let out = cleaned(
            "open example dot com slash search question mark q equals shoes ampersand page equals 3.5",
            by: sut)
        #expect(out.hasPrefix("open example.com/search?q=shoes"))
        #expect(out.hasSuffix("page equals 3.5"))
    }

    @Test(
        "leaves prose alone where no address was written",
        arguments: [
            "is the page at example dot com slash search? question mark is next",
            "what is the hash table for",
            "the question mark key is stuck",
            "we saw a question mark equals sign",
            "ask a question mark it with a star",
            "use a hash install step",
            "open example dot com slash search question mark",
            "the hash",
        ]
    )
    func leavesProse(input: String) {
        let out = cleaned(input, by: sut)
        #expect(!out.contains("?q=") && !out.contains("#install") && !out.contains("=") && !out.contains("#"))
    }
}

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Credentials named in prose")
struct ContextualCredentialTests {
    @Test("masks each of forty credential phrases with a generated value")
    func masksCredentialPhrases() {
        for index in 0..<40 {
            let keyword = Self.keyword(for: index)
            let value = index.isMultiple(of: 2) ? "q7Vn3Kp9Xr2M" : "Qv\(index)rT!x9AZ"
            let line: String
            if index.isMultiple(of: 8) {
                line = "The password for the staging server is \(value)"
            } else if index % 8 == 7 {
                line = "Thanks! API key for production: \(value)"
            } else if index % 8 == 5 {
                line = "The secret = \(value)"
            } else {
                line = "The \(keyword) is \(value)"
            }
            #expect(SecretShapes.matches(line), "Must mask \(line)")
            #expect(ClipKindDetector.kind(of: line) == .secret, "Must classify \(line) as secret")
        }
    }

    @Test("leaves each of forty ordinary credential mentions searchable")
    func leavesOrdinaryPhrasesSearchable() {
        for index in 0..<40 {
            let line = Self.ordinaryLine(for: index) + " That is note \(index)."
            #expect(!SecretShapes.matches(line), "Must leave \(line) searchable")
            #expect(ClipKindDetector.kind(of: line) != .secret, "Must not classify \(line) as secret")
        }
    }

    @Test("reads quoted and redacted credentials while rejecting ordinary code punctuation")
    func handlesQuotedAndPlaceholderValues() {
        #expect(SecretShapes.matches("my password is Tr0ub4dor&3"))
        #expect(SecretShapes.matches("The password is my_secret"))
        #expect(SecretShapes.matches("The passphrase is correct-horse"))
        #expect(!SecretShapes.matches("password is ab_cd") && SecretShapes.matches("password is abc_de"))
        #expect(SecretShapes.matches(#"The password is "Qv7!x9AZ"."#))
        #expect(!SecretShapes.matches("The code is C++"))
        #expect(!SecretShapes.matches("The code is main.swift"))
        #expect(!SecretShapes.matches("The code is variable_name"))
        #expect(SecretShapes.matches("The wifi password is <value>"))
        #expect(SecretShapes.matches("Thanks! API key for production: <40 chars>"))
        #expect(SecretShapes.matches("ssh host\npassword is <value>"))
        #expect(!SecretShapes.matches("The password is <placeholder>"))
        let key = String(repeating: "q7Vn3Kp9Xr2M5a8Bc4Df", count: 2)
        #expect(SecretShapes.matches("API key for production: \(key)"))
        #expect(!SecretShapes.matches("The password is ***"))
        #expect(!SecretShapes.matches("The password is $"))
    }

    @Test("reads a multi-line prose clip in bounded work")
    func scanWorkGrowsWithClipLength() {
        let line = "The password policy is strict and the code is in main.swift."
        let text = String(repeating: line + "\n", count: 200)
        let tally = ScanTally()
        let matched = SecretShapes.$tally.withValue(tally) { SecretShapes.matches(text) }
        #expect(!matched)
        #expect(tally.count <= text.utf8.count * 12)
    }

    private static func keyword(for index: Int) -> String {
        switch index % 8 {
        case 0: "password"
        case 1: "passcode"
        case 2: "passphrase"
        case 3: "pin"
        case 4: "token"
        case 5: "secret"
        case 6: "code"
        default: "API key"
        }
    }

    private static func ordinaryLine(for index: Int) -> String {
        switch index % 8 {
        case 0: "The password policy is strict."
        case 1: "The code is in main.swift."
        case 2: "The password is correct."
        case 3: "The passcode is written down."
        case 4: "The passphrase is easy to remember."
        case 5: "The pin is on the printed card."
        case 6: "The token is a part of the sentence."
        default: "The API key example is public."
        }
    }
}

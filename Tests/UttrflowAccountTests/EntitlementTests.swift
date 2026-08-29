import Foundation
import Testing

@testable import UttrflowAccount

@Suite("Who is signed in, and what they may do")
struct EntitlementTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func entitlement(expiring: TimeInterval) -> Entitlement {
        Entitlement(
            account: Account(
                identifier: "u_1", displayName: "Naveen", emailAddress: nil, provider: .google),
            plan: .pro, expiresAt: noon.addingTimeInterval(expiring), signature: "sig")
    }

    /// The expiry is a backstop against a cancelled subscription running for ever, not a
    /// session timeout — so the question asked of it is only ever "is this still valid",
    /// never "should we make them sign in again".
    @Test("is current until it expires, and not after")
    func currency() {
        #expect(entitlement(expiring: 86_400).isCurrent(at: noon))
        #expect(entitlement(expiring: -1).isCurrent(at: noon) == false)
    }

    /// Every provider needs a button, and Apple's wording is a trademark requirement
    /// rather than a preference — a test so nobody tidies it into "Continue with Apple".
    @Test("every provider names its own button")
    func buttonTitles() {
        for provider in SignInProvider.allCases {
            #expect(!provider.buttonTitle.isEmpty)
        }
        #expect(SignInProvider.apple.buttonTitle == "Sign in with Apple")
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let original = entitlement(expiring: 3600)
        let decoded = try JSONDecoder().decode(
            Entitlement.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

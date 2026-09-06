import Foundation
import Testing

@testable import UttrflowAccount

/// ``Entitlement`` currency, provider button titles, and Codable.
@Suite("Who is signed in, and what they may do")
struct EntitlementTests {
    /// The fixed instant the entitlements are dated from.
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    /// A pro entitlement for one fixed account, expiring `expiring` seconds from noon, unsigned.
    private func entitlement(expiring: TimeInterval) -> Entitlement {
        Entitlement(
            account: Account(
                identifier: "u_1", displayName: "Naveen", emailAddress: nil, provider: .google),
            plan: .pro, expiresAt: noon.addingTimeInterval(expiring), signature: "sig")
    }

    /// The expiry is a backstop against a cancelled subscription, never a session timeout.
    @Test("is current until it expires, and not after")
    func currency() {
        #expect(entitlement(expiring: 86_400).isCurrent(at: noon))
        #expect(entitlement(expiring: -1).isCurrent(at: noon) == false)
    }

    /// Apple's wording is a trademark requirement, so nobody tidies it into "Continue with Apple".
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

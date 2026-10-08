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
                identifier: "u_1", displayName: "Avery", emailAddress: nil, provider: .google),
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

/// The account's creation date, which the backend writes as an ISO string and the Account page shows.
@Suite("When the account was created")
struct AccountCreationDateTests {
    /// The account as the backend writes it, with `createdAt` spelled as given.
    private func document(createdAt: String?) -> Data {
        let date = createdAt.map { #","createdAt":"\#($0)""# } ?? ""
        return Data(
            #"{"identifier":"u_2","displayName":"Ada Byron","emailAddress":"ada@example.com","provider":"google"\#(date)}"#
                .utf8)
    }

    @Test("reads the backend's ISO timestamp")
    func readsTheTimestamp() throws {
        let account = try JSONDecoder().decode(
            Account.self, from: document(createdAt: "2026-08-01T08:00:00.000Z"))
        #expect(account.createdAt == Date(timeIntervalSince1970: 1_785_571_200))
        #expect(account.emailAddress == "ada@example.com")
    }

    /// An older cache or an older server sends none, and that is still an account.
    @Test("an account with no creation date has none")
    func absent() throws {
        let account = try JSONDecoder().decode(Account.self, from: document(createdAt: nil))
        #expect(account.createdAt == nil)
        #expect(account.displayName == "Ada Byron")
    }

    /// A date only displayed must never cost somebody their session.
    @Test("an unreadable creation date reads as none, and the rest of the account survives")
    func unreadable() throws {
        let account = try JSONDecoder().decode(
            Account.self, from: document(createdAt: "the first of August"))
        #expect(account.createdAt == nil)
        #expect(account.identifier == "u_2")
    }

    @Test("round-trips through Codable with the date as a string")
    func roundTrip() throws {
        let original = Account(
            identifier: "u_2", displayName: nil, emailAddress: "ada@example.com",
            provider: .gitHub, avatarPath: "/v1/me/avatar",
            createdAt: Date(timeIntervalSince1970: 1_785_571_200))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Account.self, from: data) == original)
        #expect(String(decoding: data, as: UTF8.self).contains("2026-08-01T08:00:00.000Z"))
    }
}

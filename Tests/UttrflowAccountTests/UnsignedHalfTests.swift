import Foundation
import Testing

@testable import UttrflowAccount

/// The rule stated on ``Profile/Subscription/effectivePlan`` — *displayed, never
/// enforced* — asserted in three doc comments and, until this file, checked nowhere.
///
/// It matters because only the entitlement is signed. Everything around it is a document
/// on disk that anybody can edit, and `isInternallyConsistent` binds it to the account
/// the entitlement names and to nothing else: the plan beside it is not covered, so a
/// free entitlement can sit inside a document claiming Pro and verify perfectly.
@Suite("The unsigned half of a profile decides nothing")
struct UnsignedHalfTests {
    /// A free entitlement inside a document that claims Pro, the way a hand-edited
    /// defaults file would be.
    private static func tampered() -> Profile {
        let honest = Fixture.profile(for: Fixture.entitlement(expiring: 3600, plan: .free))
        return Profile(
            account: honest.account,
            subscription: Profile.Subscription(
                plan: .pro, status: .active,
                currentPeriodEnd: Fixture.noon.addingTimeInterval(86_400),
                effectivePlan: .pro,
                limits: Profile.Limits(monthlyMinutes: 99_999, customDictionaryEntries: 9_999)),
            devices: honest.devices,
            entitlement: honest.entitlement,
            fetchedAt: honest.fetchedAt,
            validator: honest.validator)
    }

    @Test("a document that claims more than its entitlement is still kept")
    func tamperingIsNotRefused() throws {
        // Not refused, and that is the point: the check binds the document to its
        // account, not to its plan. What stops it mattering is the rule below.
        let profile = Self.tampered()
        #expect(profile.isInternallyConsistent)
        #expect(Fixture.verifier.isAuthentic(profile.entitlement))
    }

    @Test("but the plan the app reports is the signed one")
    func theSignedPlanIsWhatCounts() throws {
        let cache = Fixture.cacheHolding(profile: Self.tampered())
        let loaded = try #require(cache.load())

        #expect(loaded.entitlement.plan == .free)
        #expect(loaded.subscription.effectivePlan == .pro)
    }

    @Test("and access is decided without reading the unsigned half at all")
    func accessIgnoresTheUnsignedHalf() {
        let honest = Fixture.profile(for: Fixture.entitlement(expiring: -3600, plan: .free))
        let claimsPro = Profile(
            account: honest.account,
            subscription: Profile.Subscription(
                plan: .pro, status: .active, currentPeriodEnd: nil, effectivePlan: .pro,
                limits: honest.subscription.limits),
            devices: honest.devices, entitlement: honest.entitlement,
            fetchedAt: honest.fetchedAt, validator: honest.validator)

        // Both entitlements are the same expired free one, so both must answer the same
        // whatever the document around them claims.
        let expected = EntitlementGate(profiles: Fixture.cacheHolding(profile: honest))
            .access(at: Fixture.noon, networkIsReachable: true)
        let tampered = EntitlementGate(profiles: Fixture.cacheHolding(profile: claimsPro))
            .access(at: Fixture.noon, networkIsReachable: true)

        #expect(tampered == expected)
        #expect(tampered == .allowedPendingSignIn)
    }

    @Test("an entitlement signed for somebody else is refused outright")
    func anotherAccountsEntitlementIsRefused() {
        let honest = Fixture.profile(for: Fixture.entitlement(expiring: 3600))
        let stolen = Profile(
            account: Fixture.account("u_2"), subscription: honest.subscription,
            devices: honest.devices, entitlement: honest.entitlement,
            fetchedAt: honest.fetchedAt, validator: honest.validator)

        #expect(stolen.isInternallyConsistent == false)
        #expect(Fixture.cacheHolding(profile: stolen).load() == nil)
    }
}

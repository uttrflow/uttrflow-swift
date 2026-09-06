// Tests for EntitlementGate: who may dictate, and that an expired entitlement never locks anybody out.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAccount

/// The answers of ``EntitlementGate/access`` over signed-in, signed-out and local-account states.
@Suite("May this person dictate?")
struct EntitlementGateTests {
    /// A gate over a cache holding `entitlement`, or nothing.
    private func gate(holding entitlement: Entitlement?) -> EntitlementGate {
        EntitlementGate(profiles: Fixture.cacheHolding(entitlement))
    }

    /// Rule 1: the first launch is the only one that needs a server.
    @Test("refuses when nobody has ever signed in")
    func neverSignedIn() {
        let access = gate(holding: nil).access(at: Fixture.noon, networkIsReachable: true)
        #expect(access == .refused)
        #expect(access.permitsDictation == false)
    }

    /// A first launch offline is still a first launch; ``AccountError/serverUnreachable`` explains it.
    @Test("refuses on a first launch whether or not there is a network")
    func neverSignedInOffline() {
        #expect(gate(holding: nil).access(at: Fixture.noon, networkIsReachable: false) == .refused)
    }

    /// Rule 2: nothing on this path reaches a server, so the answer cannot depend on one.
    @Test("allows a current entitlement with no network anywhere in sight")
    func signedInAndCurrent() {
        let gate = gate(holding: Fixture.entitlement(expiring: 86_400))
        #expect(gate.access(at: Fixture.noon, networkIsReachable: false) == .allowed)
        #expect(gate.access(at: Fixture.noon, networkIsReachable: true) == .allowed)
    }

    /// Rule 3, second half: with a network the user is asked to sign in again, and still dictates.
    @Test("asks an expired user to sign in again when there is a network, and lets them speak")
    func expiredWithNetwork() {
        let access = gate(holding: Fixture.entitlement(expiring: -1))
            .access(at: Fixture.noon, networkIsReachable: true)
        #expect(access == .allowedPendingSignIn)
        #expect(access.permitsDictation)
    }

    /// A cached entitlement is believed on its signature alone, so one signed by anybody else is no session.
    @Test("refuses an entitlement somebody else signed")
    func forgedEntitlement() {
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)
        let storage = MemoryStorage()
        // Saved past the verifier on purpose: a forgery reaches the disk only by editing the file by hand.
        let credulous = UserDefaultsProfileCache(storage: storage, verifier: CredulousVerifier())
        try? credulous.save(Fixture.profile(for: forgery))

        let gate = EntitlementGate(
            profiles: UserDefaultsProfileCache(storage: storage, verifier: Fixture.verifier))
        #expect(gate.access(at: Fixture.noon, networkIsReachable: false) == .refused)
    }

    /// Being current is the only thing that separates ``DictationAccess/allowed`` from the two after it.
    @Test("treats the instant of expiry as expired and the instant before as current")
    func boundary() {
        #expect(
            gate(holding: Fixture.entitlement(expiring: 0))
                .access(at: Fixture.noon, networkIsReachable: false) == .allowedAwaitingNetwork)
        #expect(
            gate(holding: Fixture.entitlement(expiring: 1))
                .access(at: Fixture.noon, networkIsReachable: false) == .allowed)
    }
}

/// The product's most important promise; fix the code, never these tests. See Docs/entitlements.md.
@Suite("An expired entitlement degrades; it never locks")
struct ExpiredEntitlementNeverLocksTests {
    /// Rule 3: somebody on a plane whose subscription lapsed in the air must still be able to speak.
    @Test("permits dictation when the entitlement has expired and there is no network")
    func expiredAndOfflineStillDictates() {
        let store = Fixture.cacheHolding(Fixture.entitlement(expiring: -1))
        let access = EntitlementGate(profiles: store)
            .access(at: Fixture.noon, networkIsReachable: false)

        #expect(access == .allowedAwaitingNetwork)
        #expect(
            access.permitsDictation,
            "an expired entitlement with no network must still permit dictation; see Docs/entitlements.md")
    }

    /// A cut-off measured in days is still a cut-off.
    @Test("permits dictation however long ago the entitlement expired", arguments: [1, 30, 365, 3_650])
    func expiryAgeIsIrrelevant(daysAgo: Int) {
        let store = Fixture.cacheHolding(
            Fixture.entitlement(expiring: -Double(daysAgo) * 86_400))
        let access = EntitlementGate(profiles: store)
            .access(at: Fixture.noon, networkIsReachable: false)
        #expect(access.permitsDictation, "an entitlement \(daysAgo) days stale locked the user out")
    }

    /// A lapsed free account and a lapsed paid one are both already let in once.
    @Test("permits dictation on any plan", arguments: Plan.allCases)
    func planIsIrrelevant(plan: Plan) {
        let store = Fixture.cacheHolding(Fixture.entitlement(expiring: -86_400, plan: plan))
        #expect(
            EntitlementGate(profiles: store)
                .access(at: Fixture.noon, networkIsReachable: false).permitsDictation)
    }

    // MARK: Rule 5 — a person who cannot sign in is not locked out

    /// The point of ``LocalAccount``: the one page that needs a network has a way through that needs nothing.
    @Test("allows somebody who chose this Mac over an account, network or no network")
    func chosenThisMac() {
        let gate = EntitlementGate(
            profiles: Fixture.cacheHolding(nil),
            local: InMemoryLocalAccountStore(LocalAccount(name: "Naveen", since: Fixture.noon)))
        for reachable in [true, false] {
            let access = gate.access(at: Fixture.noon, networkIsReachable: reachable)
            #expect(access == .allowedOnThisMac)
            #expect(access.permitsDictation)
        }
    }

    /// A present, empty store answers exactly as no store does, or wiring one in would sign everybody in.
    @Test("a local store nobody has written to still refuses")
    func localStoreButNoLocalAccount() {
        let gate = EntitlementGate(
            profiles: Fixture.cacheHolding(nil), local: InMemoryLocalAccountStore())
        #expect(gate.access(at: Fixture.noon, networkIsReachable: true) == .refused)
    }

    /// The unsigned value never overrules the signed one, or a local account could revive a lapsed plan.
    @Test("the entitlement decides even when a local account is also present")
    func entitlementBeatsTheLocalAccount() {
        let local = InMemoryLocalAccountStore(LocalAccount(name: "Naveen", since: Fixture.noon))
        #expect(
            EntitlementGate(
                profiles: Fixture.cacheHolding(Fixture.entitlement(expiring: 86_400)),
                local: local
            ).access(at: Fixture.noon, networkIsReachable: true) == .allowed)
        #expect(
            EntitlementGate(
                profiles: Fixture.cacheHolding(Fixture.entitlement(expiring: -1)), local: local
            ).access(at: Fixture.noon, networkIsReachable: true) == .allowedPendingSignIn)
    }

    /// Guards against a sixth state joining the refusing side, or an aged-out state tidied into `.refused`.
    @Test("stops a dictation in exactly one of its five states, and that state is being signed out")
    func exactlyOneAnswerRefuses() {
        let refusing = DictationAccess.allCases.filter { !$0.permitsDictation }
        #expect(
            refusing == [.refused],
            """
            Exactly one answer may stop a dictation, and it is the one where nobody has \
            signed in and nobody chose to do without. These refuse: \(refusing).
            """)
        #expect(
            DictationAccess.allCases.count == 5,
            "a state was added or removed; decide here whether it costs the user their voice")
    }
}

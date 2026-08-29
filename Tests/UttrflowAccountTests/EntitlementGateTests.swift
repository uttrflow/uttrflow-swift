import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAccount

@Suite("May this person dictate?")
struct EntitlementGateTests {
    private func gate(holding entitlement: Entitlement?) -> EntitlementGate {
        EntitlementGate(profiles: Fixture.cacheHolding(entitlement))
    }

    /// Rule 1. The first launch is the only one that needs a server, and until it has
    /// had one there is nothing to dictate with.
    @Test("refuses when nobody has ever signed in")
    func neverSignedIn() {
        let access = gate(holding: nil).access(at: Fixture.noon, networkIsReachable: true)
        #expect(access == .refused)
        #expect(access.permitsDictation == false)
    }

    /// A first launch with no network is still a first launch: the answer is the same
    /// refusal, and it is ``AccountError/serverUnreachable`` that explains it.
    @Test("refuses on a first launch whether or not there is a network")
    func neverSignedInOffline() {
        #expect(gate(holding: nil).access(at: Fixture.noon, networkIsReachable: false) == .refused)
    }

    /// Rule 2. Nothing on this path reaches a server, so the answer cannot depend on
    /// whether one is reachable.
    @Test("allows a current entitlement with no network anywhere in sight")
    func signedInAndCurrent() {
        let gate = gate(holding: Fixture.entitlement(expiring: 86_400))
        #expect(gate.access(at: Fixture.noon, networkIsReachable: false) == .allowed)
        #expect(gate.access(at: Fixture.noon, networkIsReachable: true) == .allowed)
    }

    /// Rule 3, second half. There is a connection, so the renewal is worth attempting
    /// and the user is worth asking — but the answer still permits the dictation.
    @Test("asks an expired user to sign in again when there is a network, and lets them speak")
    func expiredWithNetwork() {
        let access = gate(holding: Fixture.entitlement(expiring: -1))
            .access(at: Fixture.noon, networkIsReachable: true)
        #expect(access == .allowedPendingSignIn)
        #expect(access.permitsDictation)
    }

    /// A cached entitlement is believed on its signature, so one signed by anybody else
    /// is not a session at all. This is the state that makes the offline promise safe
    /// to keep rather than merely convenient.
    @Test("refuses an entitlement somebody else signed")
    func forgedEntitlement() {
        let forgery = Fixture.entitlement(expiring: 86_400, signedBy: Fixture.impostor)
        let storage = MemoryStorage()
        // Saved past the verifier deliberately: this is a file edited behind the app's
        // back, which is the only way a forgery ever reaches the disk.
        let credulous = UserDefaultsProfileCache(storage: storage, verifier: CredulousVerifier())
        try? credulous.save(Fixture.profile(for: forgery))

        let gate = EntitlementGate(
            profiles: UserDefaultsProfileCache(storage: storage, verifier: Fixture.verifier))
        #expect(gate.access(at: Fixture.noon, networkIsReachable: false) == .refused)
    }

    /// Expiry is a backstop against a cancelled subscription, not a clock the app runs
    /// down. Being current is the *only* thing that separates ``DictationAccess/allowed``
    /// from the two that follow it.
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

/// The rule this whole module exists to get right.
///
/// If any test in this file is failing, do not adjust it to match the code. The
/// behaviour it describes is the product's most important promise, and the failure
/// means somebody has taken it away.
@Suite("An expired entitlement degrades; it never locks")
struct ExpiredEntitlementNeverLocksTests {
    /// Rule 3. Somebody on a plane, whose subscription lapsed while they were in the
    /// air, must still be able to speak.
    ///
    /// The one that matters. Holding a person's own words hostage to an authentication
    /// server they cannot reach is the worst failure this product could have — worse
    /// than a wrong transcript, worse than a crash, because it is the app deciding it
    /// knows better than the user about words the user already said. A gate that
    /// returned ``DictationAccess/refused`` here would look tidier and would be a
    /// betrayal of the only claim Uttrflow makes.
    @Test("permits dictation when the entitlement has expired and there is no network")
    func expiredAndOfflineStillDictates() {
        let store = Fixture.cacheHolding(Fixture.entitlement(expiring: -1))
        let access = EntitlementGate(profiles: store)
            .access(at: Fixture.noon, networkIsReachable: false)

        #expect(access == .allowedAwaitingNetwork)
        #expect(
            access.permitsDictation,
            """
            An expired entitlement with no network must still permit dictation. \
            Read the suite comment above before changing this.
            """)
    }

    /// However long ago it lapsed. A cut-off measured in days is still a cut-off, and
    /// the point at which the product starts refusing is the point at which it stops
    /// being a thing that runs on your own machine.
    @Test("permits dictation however long ago the entitlement expired", arguments: [1, 30, 365, 3_650])
    func expiryAgeIsIrrelevant(daysAgo: Int) {
        let store = Fixture.cacheHolding(
            Fixture.entitlement(expiring: -Double(daysAgo) * 86_400))
        let access = EntitlementGate(profiles: store)
            .access(at: Fixture.noon, networkIsReachable: false)
        #expect(access.permitsDictation, "an entitlement \(daysAgo) days stale locked the user out")
    }

    /// Neither does the plan. A lapsed free account and a lapsed paid one have both
    /// already been let in once, and neither is a reason to keep somebody's words.
    @Test("permits dictation on any plan", arguments: Plan.allCases)
    func planIsIrrelevant(plan: Plan) {
        let store = Fixture.cacheHolding(Fixture.entitlement(expiring: -86_400, plan: plan))
        #expect(
            EntitlementGate(profiles: store)
                .access(at: Fixture.noon, networkIsReachable: false).permitsDictation)
    }

    // MARK: Rule 5 — a person who cannot sign in is not locked out

    /// The whole point of ``LocalAccount``: the one page in the product that needs a
    /// network has a way through it that needs nothing.
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

    /// A store that is present and empty is not a local account, and must answer exactly
    /// as no store at all does. Otherwise merely wiring one in would sign everybody in.
    @Test("a local store nobody has written to still refuses")
    func localStoreButNoLocalAccount() {
        let gate = EntitlementGate(
            profiles: Fixture.cacheHolding(nil), local: InMemoryLocalAccountStore())
        #expect(gate.access(at: Fixture.noon, networkIsReachable: true) == .refused)
    }

    /// The unsigned value never overrules the signed one. If it could, a local account
    /// would be a way to talk an expired subscription into looking current.
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

    /// The guard against a sixth state quietly joining the refusing side, and against
    /// either aged-out state being "tidied" into the first one.
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

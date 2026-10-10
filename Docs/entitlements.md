# What somebody is allowed to do, and how that is known offline

After the first sign-in, a launch needs no network. What a person may do is decided from a
signed copy of their profile on this Mac, which has to be worth believing without asking
anybody. The code is in `Sources/UttrflowAccount/` (`Profile.swift`, `EntitlementSignature.swift`,
`EntitlementGate.swift`, `ProfileCache.swift`) and `Sources/UttrflowUX/SessionGate.swift`; the
app shell applies it in `AppDelegate.show` and `AppDelegate.followSession`.

Uttrflow is free and open source. Sign-in is required; there are no subscriptions or paid
tiers. The existing `plan` and `subscription` fields are legacy backend-contract data, not
payment requirements. Their wire names remain part of the signed-profile contract.

## Only the entitlement is signed

`Entitlement` (the account, the plan and the expiry) carries an Ed25519 signature from the
backend. **Everything else in `Profile` is unsigned**: the `subscription` with its limits, the
device list, the display name. The profile cache sits in `UserDefaults`, which anybody with the
Mac can edit.

`Entitlement.signedPayload` is **length-prefixed**, not joined by a separator, because a
separator is something a value can contain: an account identifier holding the delimiter could
otherwise be read as a different account and a different plan, and one signature would cover
two meanings.

The payload is `uttrflow-entitlement-v1` followed by four length-prefixed fields: the account
identifier, the provider, the plan and the expiry in whole seconds since 1970 (rounded down).
Whole seconds are the only form a backend in another language reproduces byte for byte. Each
side's own tests can only check its own reading of the contract against itself, so
`BackendContractTests` runs this verifier over entitlements the backend signed, and compares
the payload bytes with the backend's canonical form. It runs when a backend checkout is on the
machine and reports a skip, with the reason, when one is not.

## The rule that makes the unsigned half safe

**The unsigned half is displayed, never enforced.** `EntitlementGate`, the one place that
answers "may this person dictate?", reads `profile.entitlement` and nothing else. The Account
page shows no plan; from the unsigned half it shows only `profile.account.createdAt`, and only
when the document names the signed account. Nothing in the app reads `profile.subscription`.

`Profile.isInternallyConsistent` does **not** enforce this. It checks one thing: that the
document names the account the entitlement was signed for, which stops somebody pairing their
own document with a stranger's entitlement. **It does not compare the plans**, so an
entitlement inside a document claiming a different legacy plan passes it and verifies. A
gate written on `subscription.effectivePlan` would therefore be an escalation anybody could perform with a text
editor and a restart.

`UnsignedHalfTests` builds exactly that tampered document and checks that the answer does not
move.

## The verifier key is never 32 zero bytes

`Ed25519EntitlementVerifier.releasePublicKeyBytes` decodes `releasePublicKeyBase64`, and is
empty, **not 32 zero bytes**, when that is not a key. The all-zero Ed25519 public key decodes to
a point of order four and CryptoKit verifies without the cofactor, so an all-zero *signature*
satisfies the equation against it for roughly one message in four: a forged signed profile
for anybody willing to try their account identifier a few times.

Bytes that are not a key verify nothing, which is the only safe thing for a placeholder to be.
`rejectsTheDegenerateKeyThatWouldAcceptAForgery` in `EntitlementSignatureTests` keeps it that way.

## No session, nothing but sign-in

Signed in means a signed profile in the cache, never a local choice, and there is no way to
work without an account. `SessionGate` is the one rule every way in asks: `AppDelegate.show`
routes every `Destination` through it, so the Dock icon, Window ▸ Uttrflow, ⌘, (Settings),
Help, the Home and Account pages and every menu item land on the onboarding window's sign-in
page while signed out. The menu bar icon stays, and its menu offers only **Sign In…** and
**Quit Uttrflow**. `SessionSurfaces` decides what runs in the background (the dictation
shortcut, the claimed shortcuts, the clipboard recorder, tab-to-complete and the floating
button) and answers no to all of them without a session.

Signing out, or a 401 that survives a refresh, clears the profile and runs
`AppDelegate.followSession`, which closes the main window and every panel, stops listening and
opens sign-in. A refresh that cannot reach the server changes nothing: a signed, cached session
keeps working offline. A sign-in that completes in onboarding runs the same function the other
way, before the setup pages after it.

## Expiry never locks anybody out

An aged-out entitlement still permits dictation, so nobody's own words depend on reaching a
server. Only the absence of a signed profile refuses. `EntitlementGate.access(at:networkIsReachable:)` is a pure
function of the moment and whether a network exists, and its four answers differ only in what
the interface says:

| `DictationAccess` | When | Dictation |
|---|---|---|
| `refused` | no signed profile in the cache | no |
| `allowed` | entitlement current | yes |
| `allowedAwaitingNetwork` | expired, no network | yes |
| `allowedPendingSignIn` | expired, network reachable | yes |

## Rotating the key

Rotating the signing key is a new **release**, not a deployment: every cached entitlement was
signed by the key's partner, and a build carrying the wrong public key signs everybody out.
`/v1/health` publishes `entitlementPublicKey`; `uttrflow-dev sign-in` reads it and verifies
against that key rather than an assumed one.

Related: [account-session.md](account-session.md), [account-keychain.md](account-keychain.md),
[logging.md](logging.md).

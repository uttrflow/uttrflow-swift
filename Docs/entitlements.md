# What somebody is allowed to do, and how that is known offline

The product's promise is that the second launch needs no network. So what a person may do
is decided from a copy on this Mac, and the copy has to be worth believing without asking
anybody.

## Only the entitlement is signed

`Entitlement` — the account, the plan and the expiry — carries an Ed25519 signature from
the backend. **Everything around it is unsigned**: the `subscription`, the device list,
the limits, the display name. All of it sits in `UserDefaults`, which anybody with the Mac
can edit.

`Entitlement.signedPayload` is **length-prefixed**, not joined by a separator, because a
separator is something a value can contain: an account identifier holding the delimiter
could otherwise be read as a different account and a different plan, and one signature
would cover two meanings.

## The rule that makes the unsigned half safe

**The unsigned half is displayed, never enforced.** `EntitlementGate` — the one place that
answers "may this person dictate?" — reads `profile.entitlement` and nothing else. The
Account page shows `entitlement.plan`. Nothing in the app reads `profile.subscription` at
all.

`Profile.isInternallyConsistent` does **not** enforce this. It checks one thing: that the
document names the account the entitlement was signed for, which stops somebody pairing
their own document with a stranger's entitlement. **It does not compare the plans**, so a
free entitlement inside a document claiming Pro passes it and verifies perfectly.

That was worth writing down because the doc comments used to claim the opposite — that the
consistency check closed the plan-mismatch hole. It does not, and a future gate written on
`subscription.effectivePlan` in the belief that it did would be a real escalation: a text
editor and a restart.

`UnsignedHalfTests` is where the rule is checked rather than asserted. It builds exactly
that tampered document and proves the answer does not move.

## The placeholder that was a forgery oracle

`Ed25519EntitlementVerifier.releasePublicKeyBytes` is empty when no key is configured,
**not 32 zero bytes**. The all-zero Ed25519 public key decodes to a point of order four
and CryptoKit verifies without the cofactor, so an all-zero *signature* satisfies the
equation against it for roughly one message in four — a subscription for anybody willing
to try their account identifier a few times, with a signature they could type from memory.

Bytes that are not a key at all verify nothing, which is the only safe thing for a
placeholder to be. `rejectsTheDegenerateKeyThatWouldAcceptAForgery` keeps it that way.

## Expiry never locks anybody out

An aged-out entitlement still permits dictation. There is nothing to ask of somebody on a
train, and holding their own words hostage to a server neither of you can reach is the
worst thing this product could do. The four answers differ only in what the interface
says — `EntitlementGate.access` is a pure function of the moment and whether a network
exists.

Rotating the key is a new **release**, not a deployment: every cached entitlement was
signed by its partner, and a build carrying the wrong one signs everybody out. `/v1/health`
publishes the fingerprint so a build can be checked against the deployment it was made for.

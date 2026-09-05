# The refresh token in the Keychain: what `KeychainTokenStore` promises

`KeychainTokenStore` is a delete, an add and a read against the macOS Keychain. Nothing in
it can be exercised by a test that does not touch the login keychain of whoever runs it,
so reading it is the review. This page holds the four decisions the code makes and the
measurement behind the one that looks like an over-complication.

## `kSecAttrAccessibleAfterFirstUnlock`

The app relaunches at login and refreshes in the background; `WhenUnlocked` fails those
and looks like a spontaneous sign-out. The item is not `ThisDeviceOnly`, so a Mac restored
from an encrypted backup keeps its session, which is what a person expects from a machine
that replaced another.

## The data-protection keychain first, the file-based one second

`kSecUseDataProtectionKeychain` is asked for first, because without it the item lands in
the file-based keychain where a signed build and an unsigned one see different items. It
cannot be insisted on: it needs a keychain-access-group entitlement, that needs a team
identifier, and an ad-hoc build (every local build, every build a developer runs) has
neither. `SecItemAdd` answers `errSecMissingEntitlement` (-34018) and the sign-in is lost.
Adding the entitlement anyway is worse than not having it: the process is killed on
launch. So both keychains are tried, for writing and for reading, and a token that lands
in neither is reported as `AccountError.sessionCouldNotBeKept` rather than swallowed.

Reading asks both in order rather than only the one that took the write. Which keychain a
build can use is a property of how it is signed, so a token written by an ad-hoc build and
read by a notarised one (the same Mac, after an update) is in one keychain and looked for
in the other. Asking both makes that update keep the session instead of silently ending it.

A Developer ID build never reaches the fallback: it has a team identifier, so the
data-protection keychain takes the token on the first attempt.

## Delete then add, not `SecItemUpdate`

Rotation happens hourly. An update that misses leaves the previous token behind, which is
a live credential nobody is tracking any more.

## Why the file-based item is named after this build

The file-based keychain guards each item with an access control list naming the
application that created it, and for ad-hoc code that name is pinned to the code directory
hash, which changes on every build. Pinning the designated requirement to the bundle
identifier (what keeps TCC grants alive across a rebuild) does not help: the keychain's
list is not the designated requirement. Both were measured on macOS 26.5.1 with two ad-hoc
builds of one bundle sharing an item:

    read   -25293  errSecAuthFailed      (a login-password dialog, with UI allowed)
    delete -25244  cannot remove it
    add    -25299  errSecDuplicateItem

One shared name is therefore a trap. The first build to sign in owns the item for ever;
every later build is refused all three operations, and because `store` deletes before
adding and the delete is refused too, every later sign-in ends in
`AccountError.sessionCouldNotBeKept` with no way out but deleting the item by hand in
Keychain Access. Suppressing the dialog is not on offer: `SecKeychainSetUserInteractionAllowed`
is the switch for it, it is deprecated, and this package compiles warnings as errors.

Naming each build's item after its own code directory hash closes all of it. A rebuild
finds nothing of its own (-25300, no list consulted, no dialog), signs in once, and keeps
its session from then on. Verified by compiling the store into two ad-hoc-signed app
bundles differing only in code hash: one stores, relaunches and rotates; the other reads
nil silently, signs in, and keeps its own; neither disturbs the other; both sign out clean.

A build that cannot read its own code identity gets no file-based item at all, rather
than one that shares a name with another build.

The cost is one stale item per ad-hoc build that ever signed in, which `clear()` cannot
reach because it belongs to a build that does not exist any more. They are harmless and
visible under the service name; to sweep them:

    security delete-generic-password -s com.uttrflow.session.refresh-token.v1

## Why the store throws

A token that cannot be stored does not cost one sign-in; it costs every sign-in, and from
the user's chair it does not look like a Keychain problem. It looks like signing in does
nothing at all: the empty read that follows is reported upwards as "signed out". Throwing
`sessionCouldNotBeKept` is what makes the failure visible where somebody can act on it.

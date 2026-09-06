# Ad-hoc-signed builds and the data-protection keychain

`SecItemAdd` against the data-protection keychain answers `errSecMissingEntitlement` for an
ad-hoc-signed build (`codesign --sign -`). That keychain needs a keychain-access-group
entitlement, which needs a team identifier an ad-hoc signature does not carry. Every local
build is ad-hoc-signed, so a `KeychainTokenStore` that discards the `OSStatus` never stores
the refresh token there, and the next launch finds no credential.

## What the tests pin

- `KeychainFallbackTests`: a store that cannot keep the token throws
  `AccountError.sessionCouldNotBeKept` instead of reporting success, and the real store
  round-trips through whichever keychain the runner's signature allows. Which keychain took
  the token is a property of the signature, not the code, so it is not asserted.
- `HTTPAuthenticationServiceTests.noCredentialIsNotASignOut` and
  `AccountRefreshTests.noCredentialIsNotASignOut`: a Mac holding no refresh token answers
  `ProfileRefresh.noCredential`, never `.signedOut`. A `.signedOut` answer makes
  `AccountRefresh` delete a cached profile the server still honours, which shows as
  "Not signed in" immediately after a completed sign-in.
- `HTTPAuthenticationServiceTests.anEmptyKeychainKeepsTheProfile`: the same rule end to end,
  with a real service and a real `AccountRefresh` over an empty token store.

See also `Docs/account-keychain.md` for the rules `KeychainTokenStore` itself keeps.

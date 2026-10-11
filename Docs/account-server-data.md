# Account data on the server: what is kept, for how long, and how it is deleted

Dictation, the clipboard and AI suggestions never reach the server. Signing in does: the
account service keeps a small record per person so that sign-in, entitlement and the list of
signed-in Macs work. This page lists that record from the backend's schema and routes, so the
answer to "and what does leave my Mac?" has one home. What the app itself sends is in
[account-telemetry.md](account-telemetry.md) and [account-transport.md](account-transport.md).

## What is stored per account

| Data | Fields | Why | Kept until |
|---|---|---|---|
| Account | id, display name, email address and whether it is verified, avatar location at the provider, created and updated times | identify the person and show who is signed in | account deletion clears name, email and avatar |
| Provider identity | the sign-in provider's stable id for the person, first and last seen | find the account at the next sign-in | deleted with the account |
| Sessions | a hash of each refresh token, issue, expiry and revocation times, the device it belongs to | keep the app signed in | refresh token expires after 90 days; revoked on sign-out; deleted with the account |
| Devices | a typed device name, platform, app version, first and last seen | the list of signed-in Macs | removed when forgotten; deleted with the account |
| Subscription | plan, status, end of the current period | entitlement | kept: accounting record |
| Entitlement issuances | issue and expiry time of each signed entitlement | accounting | kept: accounting record |
| Usage statistics (opt-in) | counts and timings only, see [account-telemetry.md](account-telemetry.md) | product measurement | kept; detached from the account on deletion |

Short-lived sign-in records (authorization codes, device codes, pending authorizations,
sign-in handoffs) hold a hash and an expiry measured in minutes.

Access tokens live one hour. The avatar is fetched from the provider on request and not
copied to the server.

## How a person sees it

`GET v1/me` returns the whole account document: account fields, subscription and limits,
and every device with its name, app version, first and last seen. The app reads it through
`HTTPAuthenticationService` (`Sources/UttrflowAccount/HTTPAuthenticationService.swift`).

## How a person deletes it

| Route | Effect |
|---|---|
| `DELETE v1/me/devices/{id}` | forgets one Mac and its sessions |
| `DELETE v1/me` | deletes the account, answers `204` |

Deleting the account clears name, email and avatar, removes provider identities, sessions
and devices, and detaches usage statistics. Subscription and entitlement rows stay as
accounting records with nothing that names the person. Signing in again afterwards creates a
new account: neither the provider identity nor the email address can find the old one.

In the app, **Delete account** on the Account page asks once, then calls `DELETE v1/me`
through `HTTPAuthenticationService.deleteAccount()`: two actions from the Account page. This Mac
signs out only after the server answered with success; a refusal leaves the session and says so.

## Not provided

- No export route: the account document from `GET v1/me` is the full per-person record
  except usage statistics, which have no read route.
- No retention limit on usage statistics or on revoked and expired session rows.

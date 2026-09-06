# The account session: what `HTTPAuthenticationService` promises

`HTTPAuthenticationService` is four HTTP calls — start a sign-in, claim it, refresh the
session, read the profile — and a handful of rules it keeps while making them. The code
says what each call does; this page says why the rules are the way they are.

## A missing network is never a refusal

The transport throws only when a request did not happen. Every answer the server gave,
including `401` and `502`, comes back as a response. That distinction is the offline
promise: a Mac that cannot reach the server keeps its cached profile, and a Mac that has
been *told* its session is over does not.

A `5xx` is deliberately not treated as unreachable. The server was reached and it
failed; calling that "no connection" would send the user to check their Wi-Fi over an
outage they cannot do anything about, and would hide the outage.

## The access token is never written down

The access token lives about an hour and stays in memory. Only the ninety-day refresh
token reaches the Keychain, behind the system's own lock. A process that ends has nothing
to leak but the one credential it must keep.

Rotation means the previous refresh token is already dead once a new session arrives, so
storing the new one is the session, not housekeeping. A Keychain that refuses to store it
fails the sign-in with `AccountError.sessionCouldNotBeKept`: an account that appears,
works, and is gone at the next launch is worse than a reported failure.

## Nothing is believed without a signature

A profile is refused unless its entitlement verifies against the key compiled into this
build, and unless the entitlement names the same account as the document carrying it.
The check runs on a fresh sign-in as well as on a cached copy read off the disk, so a
profile that cannot be believed fails the sign-in that produced it — where there is
somebody to tell — rather than surfacing as a mysterious sign-out on a later launch.

## One renewal, and only one

An access token rejected with `401` is usually one minted before a rotation. The service
renews once and retries; a second `401` after a fresh token means the session itself is
gone. If the credential vanished between the two requests, another caller met a `401`
first and cleared it, and that caller is the one entitled to act on it; this one reports
`noCredential` rather than deleting a cached profile on the strength of a race.

## The port is bound before the browser opens

Binding the loopback listener is the one step that fails for reasons nothing else in the
flow shares — SSH sessions, containers, security software that refuses any listener.
Finding that out after sending somebody to a sign-in page would leave a tab open with
nowhere to return to, so the port is bound first, and a Mac that cannot bind one signs in
by RFC 8628 device code instead: the flow a television uses, needing no port, URL scheme or
operating-system permission.

While polling for device approval, `authorization_pending` is the ordinary answer rather
than a failure (RFC 8628 spells it as an error because a token endpoint has no other
vocabulary), and `slow_down` lengthens the interval by five seconds.

## The avatar is fetched quietly

The avatar path comes from the profile document but is still checked to be a path on this
API rather than an address of its own, so a document from somewhere unexpected cannot
point the app at another host. Every failure — a `404` for an account with no picture, a
`502` from a slow provider, a body that is not an image — answers `nil`; none of them is
worth a message to somebody looking at their own initials.

## Sign-out is local first

A person asking to be signed out is signed out whatever the network is doing. The request
that revokes the refresh token at the server is worth making and not worth waiting on;
the token expires on its own regardless.

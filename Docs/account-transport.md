# The transport: why `URLSessionTransport` has no cache

`URLSessionTransport` is the one place the account module opens a socket. It puts a
`BackendRequest` on the wire and hands back whatever came off, and every decision worth
getting wrong (which path, which header, what body) is in the request handed to it. Two
settings on its session are load-bearing.

## No cache, and `reloadIgnoringLocalCacheData`

`URLSession` does HTTP caching itself. Given a cached response it revalidates on its own,
and when the server answers `304` it does not tell the caller: it returns the cached body
as a `200`, which is correct behaviour for a browser and exactly wrong here. This app
sends its own `If-None-Match` and needs to see the `304`, because that answer is what
tells it the cached profile is current. With a cache in the way every launch looks like a
change: the profile is rewritten and the entitlement re-signed, for ever, silently. Only
the one test that runs against a real backend can see it.

So `urlCache` is `nil` and the cache policy ignores local data.

## Ephemeral, on purpose

The default session is `URLSessionConfiguration.ephemeral`. A disk cache would write
copies of the profile, which names the person and their plan, into a cache directory
nothing else in the app knows about or clears. A cookie store would keep state for a
service that authenticates with a bearer token and sets no cookies.

## Twenty seconds, and no waiting for connectivity

`timeoutIntervalForRequest` is 20 seconds: long enough to survive a slow hotel connection,
short enough that a first-run sign-in on a dead network fails while the user is still
watching. `waitsForConnectivity` is off for the same reason.

## Every `URLSession` failure is "the request did not happen"

No network, DNS, TLS, a timeout, a cancellation, a response that is not HTTP: none of
them is the server saying no, and the transport throws `BackendUnreachable` for all of
them. Every answer the server gave, `401` and `502` included, comes back as a
`BackendResponse`. That difference decides whether this Mac keeps working offline; see
`Docs/account-session.md` for what the service does with it.

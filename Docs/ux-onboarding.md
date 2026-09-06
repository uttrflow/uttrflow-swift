# Onboarding: the rules the flow is built on

`OnboardingFlow` in `Sources/UttrflowUX` drives first-run onboarding without a screen. The
window above it only draws. These are the decisions that shape it and that a reader
changing it needs to keep.

## Two rules

- Nothing is remembered about the system. A permission is read from its gate at the
  moment it matters, never carried forward from the click that asked for it.
- No page is a dead end. Whatever the user has refused, there is always a control that
  moves them on, and what refusing cost them is said plainly on the last page.

## Offline

The sign-in page is the only page that needs a server, which is why `NetworkReachability`
is asked before the provider buttons are drawn live. Whether somebody is *already* signed
in is never asked of a server: `EntitlementGate` answers it from a cached, signed
entitlement, so every launch after the first works with Wi-Fi off. An entitlement that has
aged out still counts as signed in; it degrades, it does not lock.

## Sign-in is one awaited call

The whole exchange — start, open the browser, wait for the backend to say the browser half
is done, read the profile — is one awaited sequence rather than two halves joined by a URL
the operating system delivers. No token ever travels through the browser: the app collects
the session over its own connection, using a claim token the browser never saw.

What that buys: the app is not reachable through a URL scheme any other program on the Mac
can invoke, there is no callback that can arrive after the user has walked away, and the
sign-in either completes in the flow or does not happen at all. Cancelling the task is what
makes the Cancel button real; the browser tab stays open and the backend forgets the
attempt within ten minutes.

A Mac that cannot bind a loopback port (SSH, a container, security software) is given a
code to type instead, and the page says so.

The provider's page opens in the user's own browser, never a web view: a password is typed
there, and the only window in which that is safe is one whose address bar the user can see
and whose password manager they already trust.

## Working without an account

"Continue on this Mac" saves a `LocalAccount` named after the macOS user. It is offered on
the same page as the providers rather than only after a failure, because a choice that
appears only once something has gone wrong reads as a consolation prize. Any sign-in still
waiting in a browser tab is abandoned first, so two answers to the same question cannot
arrive minutes apart. A real sign-in clears the local account, and only after the profile
has been saved.

`resume(askingToSignIn: true)` makes a local account *not* count as signed in, because
somebody who pressed Sign In on the Account page is asking for an Uttrflow account.

## Finishing writes no preference

`finish` does not turn `opensAtLogin` on. `Settings` ships with it `true`, and a stored
`false` can only have been written by the switch on the Settings screen, so every write
here would be either a no-op or an override of the user's choice.

## Generations

Both the download and the sign-in outlive the click that started them. Each is guarded by
a generation counter bumped when the user walks away, so a late result cannot redraw a page
that is no longer on screen. The one exception is a sign-in that completes after Cancel:
the user is signed in, and the page moves on regardless.

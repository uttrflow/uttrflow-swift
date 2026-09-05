# UX test harness traps

## The end-to-end harness owns no lifetime

`PanelEndToEndTests.Harness` in `Tests/UttrflowUXTests/PanelEndToEndTests.swift` is a plain
struct with no `deinit`, and each test removes the temporary folder through `defer`.

It was once a `~Copyable` struct whose `deinit` deleted the folder. Every method on it is
`await`ed, so its lifetime ended at the last syntactic use rather than at the end of the
test, and the deallocation landed *during* an in-flight call on the store. The symptom was
a segmentation fault deep in `Sequence.first(where:)` and `seed(_:)`, over memory freed
underneath them. It passed only for as long as the layout happened to be lucky: adding one
unused property to `ClipboardStore` was enough to crash it. Making it a class was not
enough either; the deallocation simply moved.

The rule that follows: nothing in a test harness may own a lifetime that an awaited call
depends on. Write the clean-up down at a point in time (`defer { harness.cleanUp() }`)
rather than inferring it from a value going out of scope.

## Onboarding doubles are gated, not raced

`Tests/UttrflowUXTests/OnboardingSupport.swift` holds calls open with `Gate` so a test can
act while a download or a sign-in is in flight. Proving the flow's generation guards work
means being *inside* the call when the user walks away, which a test cannot reach by
winning a race. `settle(until:)` yields rather than sleeps, because there is no wall clock
anywhere in the flow to wait on.

`FakeAuthenticationService` is gated by default, so `Harness.choose` leaves the flow
waiting on a browser; a test that wants the sign-in to finish says so by calling
`returnFromBrowser`, which waits for the call to reach the gate before opening it, since a
gate nothing has reached yet would open for nobody.

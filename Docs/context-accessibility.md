# What applications actually answer

`MacContextEngine` gathers a context from two sources with very different costs, and the split
between them is what makes the degradation guarantee real rather than hoped for. The evidence here
comes from a probe run against the running desktop; a CLI is not a representative test bed for the
Accessibility API, and a well-behaved application never exercises the broken path.

## Identity is free; the window is not

| Source | Cost | Permission | Can hang |
| --- | --- | --- | --- |
| `NSWorkspace` — name and bundle identifier | free | none | no |
| Accessibility — window title, selection, caret text | a message to another app | required | yes |

A probe running as an unsigned app with **no Accessibility grant at all** still read back `Claude`
/ `com.anthropic.claudefordesktop` from `NSWorkspace`, while every Accessibility call it made
returned `kAXErrorAPIDisabled`.

So the two are gathered in that order and recorded as they arrive: identity first and banked the
moment it lands, then the window read, which is the part allowed to hang. Whatever the budget
interrupts, the application name is already in hand.

## Applications answer the two halves separately

`FocusedWindow`'s title and selection are separately optional because applications answer them
separately. In the probe:

| Application | Window title | Selection |
| --- | --- | --- |
| Chrome | yes | refused (`kAXErrorNoValue`) |
| Terminal | yes | yes |
| Slack | no | no |

Hence the reads are issued separately and each half is kept on its own: an application that names
its window but hides its selection still yields the half it was willing to give.

## macOS will not say what is behind the front window

`MacContextEngine` remembers the last application in front of the user that was not Uttrflow,
rather than looking it up, because there is no way to ask. `runningApplications` comes back in
launch order, not activation order. Watching the front change is the only honest source.

This matters because Uttrflow is never the right answer for a context: its own window comes
forward for settings, for onboarding, for a permission repair prompt, and "you are dictating into
Uttrflow" is both useless and false — the words are on their way somewhere else. The application
that was in front before is the honest answer; when there has not been one, nothing at all is.
And with Uttrflow's own window in front, the focused window is Uttrflow's, so it is not read at
all: filing its title under the application behind it would be a confident lie.

Uttrflow is recognised two ways because either can be missing. The bundle identifier is the
reliable one but is absent when Uttrflow runs unbundled, from the command line; the process
identifier always holds. The bundle identifiers are compared only once ours is known, so an
application that reports no bundle identifier never matches an Uttrflow that has none either.

## Core Foundation casts

Every element and value that comes back from Accessibility is checked by type ID and then
`unsafeDowncast`. A conditional cast cannot express this: Swift treats `as?` on a Core Foundation
type as always succeeding, so it would silently accept a non-element.

## Why the `+System` files are excluded from coverage

`Scripts/coverage_report.py` excludes `MacContextEngine+System.swift`, `SurfaceProbe+System.swift`,
`FocusedFieldReader+System.swift` and `CompositionProbe+System.swift` with a stated reason each:
every line reaches into another running application or asks the window server about one. What they
must never do — wait — is decided in `MacContextEngine` and `Deadline`, and tested there. They are
kept short enough that reading them is a sufficient review.

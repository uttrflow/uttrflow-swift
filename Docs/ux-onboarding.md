# Onboarding: the rules the flow is built on

First-run onboarding takes a new user from sign-in to a first dictation. `OnboardingFlow` in
`Sources/UttrflowUX/` drives it without a screen and `OnboardingPresenter` decides what each page
says; the window in `Sources/Uttrflow/Onboarding/` (`OnboardingWindowController`,
`OnboardingView`) only draws. These are the decisions that shape it and that a reader changing it
needs to keep. The window's sizes and the provider marks are in
[`app-onboarding.md`](app-onboarding.md); how a session is kept is in
[`account-session.md`](account-session.md).

## Six pages, each answered before it is left

`OnboardingStep`: sign in, clipboard, microphone, Accessibility, speech-model setup, ready. What
Uttrflow is for is said on the sign-in page itself; there is no separate welcome page.

- Nothing is remembered about the system. A permission is read from its gate at the moment it
  matters, never carried forward from the click that asked for it.
- Every page but the last is mandatory. Sign-in has no way past it but an account; a permission
  page offers Continue only once macOS reports it granted; the download page offers Continue only
  once the model is on disk, and its Cancel stops the download and offers Try again rather than
  moving on. `OnboardingFlow` refuses a stray `.advance` on an unanswered page, so the rule holds
  even if a page offered one by mistake.
- The clipboard page follows sign-in, because signing in is what starts recording copies. It says
  how long copies are kept (the stored `clipboardRetentionDays`) and offers Keep and Turn off,
  which save `clipboardEnabled` at once, beside Continue. Keeping is the default, so the setting
  cannot say whether the page was answered: Continue writes that to `OnboardingRecordStore`, and
  the page is passed over from then on.
- The one exception is a device policy (`.restricted`): granting is not on offer at all, so
  Continue is the only answer left, and the last page says what it cost.
- A granted permission and a finished download stay on screen to say so, and the user presses
  Continue; nothing moves the page on by itself.
- A page argues only with somebody who has refused it. `AXIsProcessTrusted` cannot say "not asked
  yet", so the Accessibility page opens at `.denied` with nobody having refused anything;
  `PermissionKind.reportsNotDetermined` is what tells the two apart, and it is why that page's
  first answer is still the ask rather than a trip to System Settings.
- macOS shows no dialog for Accessibility. `AccessibilityPermissionGate.request()` opens System
  Settings and returns the status as it stands, which is almost always still not granted; the
  page re-reads when the user comes back rather than treating that answer as a refusal.

## Offline

The sign-in page is the only page that needs a server, which is why `NetworkReachability` is asked
before the provider buttons are drawn live; offline, the page offers only Try again. Whether
somebody is *already* signed in is never asked of a server: `EntitlementGate` answers it from a
cached, signed entitlement, so every launch after the first works with Wi-Fi off. An entitlement
that has aged out still counts as signed in; it degrades, it does not lock. See
[`entitlements.md`](entitlements.md).

## Sign-in is one awaited call

The whole exchange (start, open the browser, wait for the browser to come back, spend the code,
read the profile) is one awaited sequence in `HTTPAuthenticationService`, not two halves joined
by a URL the operating system delivers. The browser comes back to a loopback port this process
bound, carrying a single-use authorization code that is worthless without the PKCE verifier the
process kept and the state it started with. The app registers no URL scheme for sign-in, so no
other program on the Mac can invoke it, no callback can arrive after the user has walked away, and
the sign-in either completes in the flow or does not happen at all. Cancelling the task is what
makes the Cancel button real: it closes the port and abandons the attempt.

A Mac that cannot bind a loopback port (SSH, a container, security software) signs in by device
code (RFC 8628) instead: it is given a code to type, and the page says so.

The provider's page opens in the user's own browser, never a web view: a password is typed there,
and the only window in which that is safe is one whose address bar the user can see and whose
password manager they already trust.

## No way past sign-in

Sign-in is mandatory and nothing else in the app opens without a session. There is no way to work
without an account. A Mac carrying a local account record from an older build has it removed at
launch (`RetiredLocalAccount.forget()`) and opens on this page, even though its setup is finished.

`OnboardingFlow.onSignIn` fires as soon as the profile is kept, so the rest of the app is switched
on before the remaining setup pages, whose last one asks for a first dictation.

## The welcome

A finished sign-in does not jump straight to the next page. The flow shows
`OnboardingSignInState.welcomed`: the account's circle over one burst of confetti, "You’re in,
<first name>!", the address it signed in with, and a Continue button that names the page it leads
to. `OnboardingWindowController` brings the window forward at that moment, since the browser has
the screen. The welcome moves on by itself after `OnboardingPresenter.welcomeLinger` (3 s, drawn
as a shrinking bar), or at once on Continue. A countdown that ends after the user has left the
page, or after a sign-out, changes nothing.

A sign-out while the window is still open, from the menu bar or the Account page, sends the flow
back to this page through `OnboardingFlow.signedOut()`, whichever page it was on. A download in
flight keeps going, but stops drawing; signing in again joins it on the download page.

## The first try

The last page asks the user to hold their shortcut and talk. It draws the bottom-left keys of a
Mac keyboard with the shortcut's keys lit teal under a "HOLD BOTH" bracket ("HOLD" for one key;
"PRESS BOTH" or "PRESS" for a shortcut that is pressed rather than held). The lit keys press themselves every
1.4 s (`demonstrationBeat`) to show what holding means. A shortcut with a key the corner does not
have, such as Space or Shift, is drawn as plain keycaps instead. `OnboardingWindowController` maps
each `DictationState` to an `OnboardingTrial`: recording is listening, and the words of an
insertion, or of a failed one, since Uttrflow does not type into its own window, fill the page's
field. `OnboardingFlow.tried(_:)` shows them with a small burst of confetti for
`OnboardingPresenter.heardLinger` (3 s) and then closes onboarding, which opens the dashboard;
"Open dashboard" does it at once. Empty words go back to waiting. "Skip to dashboard" is a
full-width button and closes onboarding at any time.

## Finishing writes no preference

`finish` does not turn `opensAtLogin` on. The settings store ships with it `true`
(`SettingsStore`), and a stored `false` can only have been written by the switch on the Settings
screen, so every write here would be either a no-op or an override of the user's choice.

## Generations

Both the download and the sign-in outlive the click that started them. Each is guarded by a
generation counter (`installGeneration`, `signInGeneration`) bumped when the user walks away, so a
late result cannot redraw a page that is no longer on screen. The one exception is a sign-in that
completes after Cancel: the user is signed in, and the page moves on regardless.

## Closing the window during the download

Closing the onboarding window, with its red button or otherwise, does not stop the speech model's
download: it keeps running and stays visible. The app owns the one download
(`SharedModelInstall`), and every onboarding window joins it rather than starting another, so
reopening setup mid-download shows the same download instead of writing a second copy into
staging. While it runs, the menu bar and the floating button show "Setting up…" with the
percentage; when it lands the model is loaded without a relaunch, and when it fails they go back
to saying setup has not finished. Only the page's Cancel button stops it.

The app forgets the onboarding window however it closes, so an update waiting for a quiet moment is
not held back by a window that is no longer on screen.

# Onboarding window: sizes and the provider marks

The onboarding window is drawn by `Sources/Uttrflow/Onboarding/` (`OnboardingWindowController`,
`OnboardingView`, `OnboardingBackdrop`, `OnboardingPieces`); its colours are
`BrandPalette.Onboarding`. What each page says and when it moves on is in
[`ux-onboarding.md`](ux-onboarding.md).

## Window and card

| Value | Points | Constant in `OnboardingView` |
| --- | --- | --- |
| Window | 860 × 560 | `windowWidth`, `windowHeight` |
| Card width | 390 | `cardWidth` |
| Card inset from the right and bottom edges | 40 | `cardTrailing`, `cardBottom` |

The window is drawn dark whatever the Mac is set to (`window.appearance = .darkAqua`). The aurora
behind everything takes its colours from the page's `OnboardingMood` (brand, live, waiting,
warning, failure, offline); it turns once every forty seconds and holds still under Reduce Motion,
Low Power Mode or thermal pressure (`MotionBudget.demonstrationMoves`). The problem moods
(warning, failure, offline) are drawn dimmer, so bad news is never the brightest thing on screen.
No animation pulses: the waveform, the sign-in arc and the typing field move, and all of them are
gated by the same budget.

The logo top-left is `UttrflowMarkView` on a dark tile beside `BrandWordmark`; there is no
second logo asset. The card holds a picture on top, then the heading, round buttons, a hint and
one dot per step.

## The Google mark

Google's mark is a third-party trademark, so `Scripts/fetch-provider-marks.sh` fetches it from the
artwork Google publishes for its sign-in button, and `.gitignore` keeps it (`GoogleG.png`,
`GoogleMark.png` under `Sources/Uttrflow/Resources/`) out of the repository. Shipping it inside an
app that implements Google Sign-In is what it is published for; redistributing it in public source
is a different act.

It is never recoloured, rotated or redrawn. That is why it is a picture rather than a `Path`
somebody would later be tempted to tint; redrawing it as a vector is the one thing the terms do
not permit.

`image(forResource:)` returning `nil` is a supported state. A checkout that has not run the script
draws a plain `person.fill` symbol in the round button with the provider's name under it, which is
also what any provider without a fetched mark draws.

## Providers

Only the providers in `SignInProvider.offered` (`Sources/UttrflowAccount/Account.swift`) are drawn,
and that list is `[.google]`, so the sign-in page draws one round button. `SignInProvider` also has
`.gitHub`, which the backend client can speak to; a deployment offers only the providers it has
credentials for, and adding a provider to `offered` puts its button beside Google's.

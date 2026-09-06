# Onboarding window: sizes and the provider marks

## Window size

760 × 520. The sign-in page carries a glyph, a three-line subtitle, the provider stack, a note
and the terms; at 620 × 470 that came to more than the window held once the two 34-point
spacers were counted. One provider is offered today and `SignInProvider` names three; turning
on a second adds 47 points to a window that clips rather than scrolls (fixed size, hosting view
`sizingOptions = []`).

The column is 400 points wide so the body runs to three lines rather than two very wide ones.

## Colours

`onboardingAccentInk` has two values because this window follows the system appearance:
`dockAccentLight` is unreadable on a white page and `dockAccent` is dull on a near-black one.
The dark half is the panel's foreground teal (`#5FE0D3`); the light half (`#0E6B64`) is
deepened until it clears 4.5:1 on `#F3F2F7`. The fineprint is `mainMuted`, not the dimmest
grey, because it is the one line a person is agreeing to; at 2.9:1 it read as not saying
something while appearing to.

## The Google mark

Apple's mark ships with the system. Google's is somebody else's trademark, so
`Scripts/fetch-provider-marks.sh` fetches it from the artwork Google publishes for exactly this
button and `.gitignore` keeps it out of the repository. Shipping it inside an app that
implements Google Sign-In is what it is published for; redistributing it in public source is a
different act.

It is never recoloured, rotated or redrawn. That is why it is a picture rather than a `Path`
somebody would later be tempted to tint; redrawing it as a vector is the one thing the terms do
not permit.

`image(forResource:)` returning `nil` is a supported state. A checkout that has not run the
script draws the wording alone, which is what the GitHub button does in every build: its mark
is not fetched either, and a stand-in symbol would be somebody else's logo by implication.

#!/usr/bin/env bash
#
# Fetches the sign-in provider marks that this repository deliberately does not carry.
#
# Google's four-colour G is Google's trademark. Shipping it inside an app that implements
# Google Sign-In is what it is published for; redistributing it in a public source
# repository is a different act, and not one the asset terms clearly allow. So the mark is
# gitignored and fetched from the source Google publishes it at, by whoever is building.
#
# The same reasoning covers GitHub's Invertocat. Apple's mark needs nothing: it ships with
# the system as the `apple.logo` SF Symbol.
#
# Nothing here is required to build or run the app. `ProviderMark` in OnboardingView.swift
# renders nothing when the resource is absent, so a build without these marks gets sign-in
# buttons carrying their wording alone — which is exactly what the GitHub button does
# today. Run this if you want the buttons to look like the shipping app.
#
# Usage:  ./Scripts/fetch-provider-marks.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Sources/Uttrflow/Resources"
GOOGLE_MARK="$DEST/GoogleG.png"
# The boxed tile an older fetch saved; the app no longer reads it.
STALE_MARK="$DEST/GoogleMark.png"

GOOGLE_ASSETS="https://developers.google.com/static/identity/images/signin-assets.zip"
GITHUB_ASSETS="https://brand.github.com/GitHub_Logos.zip"

note() { printf '  %s\n' "$*"; }

rm -f "$STALE_MARK"

if [[ -f "$GOOGLE_MARK" ]]; then
    python3 "$ROOT/Scripts/provider_mark.py" verify-mark
    note "GoogleG.png matches its registered digest; nothing to fetch."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '\nFetching the Google mark\n'
note "from $GOOGLE_ASSETS"

if ! curl --fail --location --silent --show-error "$GOOGLE_ASSETS" --output "$TMP/google.zip"; then
    printf '\ncould not download the asset pack.\n'
    note "Get it by hand from: $GOOGLE_ASSETS"
    note "and save the square four-colour G as: $GOOGLE_MARK"
    exit 1
fi

python3 "$ROOT/Scripts/provider_mark.py" verify-archive --archive "$TMP/google.zip"
unzip -q -o "$TMP/google.zip" -d "$TMP/google"

MARK="$("$ROOT/Scripts/select-google-mark.sh" "$TMP/google")"

if [[ -z "$MARK" ]]; then
    printf '\nthe asset pack downloaded, but no standalone G was recognisable in it.\n'
    note "Google has changed the layout. Look in: $TMP/google"
    note "and save the square four-colour G as: $GOOGLE_MARK"
    note "Then update the search in this script so the next person does not repeat this."
    # Keep the extraction around for the person reading this message.
    trap - EXIT
    exit 1
fi

mkdir -p "$DEST"
DARK="$("$ROOT/Scripts/select-google-mark.sh" "$TMP/google" Dark)"
# A light and a dark tile of one mark lift the bare G off its tile; a pack with a bare G is copied.
if [[ "$MARK" == *"Theme=Light"* && "$DARK" == *"Theme=Dark"* ]]; then
    swift "$ROOT/Scripts/lift-google-mark.swift" "$MARK" "$DARK" "$GOOGLE_MARK"
else
    cp "$MARK" "$GOOGLE_MARK"
fi
python3 "$ROOT/Scripts/provider_mark.py" verify-mark
note "saved $(basename "$MARK") -> Sources/Uttrflow/Resources/GoogleG.png"

printf '\nGitHub'"'"'s Invertocat is not fetched automatically.\n'
note "Its pack is a designed set rather than a predictable archive: $GITHUB_ASSETS"
note "The GitHub button carries its wording alone until someone places one, which is fine."

printf '\nDone. The marks are gitignored; they are never committed.\n\n'

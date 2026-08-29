#!/usr/bin/env bash
#
# Publishes a built disk image to the public downloads repository.
#
#   ./Scripts/publish.sh                       publish the one image in dist/
#   ./Scripts/publish.sh dist/Uttrflow-X.dmg   publish that one
#   ./Scripts/publish.sh --dry-run             say exactly what would happen, change nothing
#
# This was a GitHub Actions workflow for about an hour. It is a script because the
# workflow could not run: macOS runners bill at ten times Linux, this project's included
# minutes went in two days, and jobs stopped starting. Rather than pay for a runner to do
# what this Mac was going to do anyway, it happens here.
#
# Which turns out to be simpler rather than merely cheaper. A runner needs the Developer
# ID certificate uploaded as a base64 secret, its password as a second secret, an Apple
# app-specific password as a third, and a personal access token as a fourth — because
# GITHUB_TOKEN cannot write to another repository. All four already exist on the machine
# that built the image: the certificate is in the keychain, the notary credentials are in
# a keychain profile, and `gh` is logged in. Nothing has to be copied anywhere to be used.
#
# What this does NOT do is build or notarise. `make release` does that, and this refuses
# to publish anything it has not been able to check. The division is deliberate: building
# is slow and repeatable, publishing is fast and public.
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

DOWNLOADS_REPO="${UTTRFLOW_DOWNLOADS_REPO:-uttrflow/releases}"
# No version in the asset name, and that is the whole mechanism behind a permanent
# download link: GitHub resolves /releases/latest/download/<asset> to the newest release
# carrying an asset of exactly that name. A version here would 404 that URL tomorrow.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET="Uttrflow.dmg"
# What the updater fetches. Like the image, no version in the name: the appcast carries
# the version, and a constant name keeps the release layout the same every time.
ARCHIVE="Uttrflow.zip"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
GENERATE_KEYS=".build/artifacts/sparkle/Sparkle/bin/generate_keys"

DRY_RUN=no
EXPLICIT=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=yes ;;
        -*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
        *) EXPLICIT="$arg" ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

command -v gh >/dev/null 2>&1 || fail "the GitHub CLI is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in — run: gh auth login"

# ---------------------------------------------------------------------------
# What is being published
# ---------------------------------------------------------------------------

step "Reading the image"

# Never "the first one". `ls` sorts alphabetically, so with a calendar version in the
# filename an old 0.1.0 image sorts *before* 2026.8.25.19.0 and would be published in its
# place — silently, with the right-looking command and the wrong build. Publishing the
# wrong artefact is not a mistake that announces itself, so ambiguity is refused outright.
if [[ -n "$EXPLICIT" ]]; then
    IMAGE="$EXPLICIT"
    [[ -f "$IMAGE" ]] || fail "no disk image at $IMAGE"
else
    FOUND=()
    while IFS= read -r found; do FOUND+=("$found"); done \
        < <(find dist -maxdepth 1 -name 'Uttrflow-*.dmg' 2>/dev/null | LC_ALL=C sort)

    (( ${#FOUND[@]} > 0 )) || fail "$(
        printf 'no disk image in dist/.\n'
        printf '  Build one first:\n'
        printf '    make release   Developer ID, notarised — the thing users download\n'
        printf '    make app-hardened && make dmg   a test build, no certificate needed'
    )"

    (( ${#FOUND[@]} == 1 )) || fail "$(
        printf 'more than one disk image in dist/, and no way to tell which you meant:\n'
        printf '%s\n' "${FOUND[@]}" | sed 's/^/    /'
        printf '  Name one:      ./Scripts/publish.sh dist/Uttrflow-<version>.dmg\n'
        printf '  Or start over: make clean'
    )"

    IMAGE="${FOUND[0]}"
fi

# Everything about the release is read out of the artefact rather than passed in, so the
# tag, the version and the notes cannot disagree with the file they describe.
MOUNTED=""
cleanup() { [[ -n "$MOUNTED" ]] && hdiutil detach "$MOUNTED" -quiet -force >/dev/null 2>&1 || true; }
trap cleanup EXIT

MOUNT_OUTPUT="$(hdiutil attach "$IMAGE" -readonly -noverify -nobrowse -mountrandom /tmp)" \
    || fail "$IMAGE will not mount"
MOUNTED="$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/tmp/[^[:space:]]*' | head -1)"
APP="$(find "$MOUNTED" -maxdepth 1 -name '*.app' | head -1)"
[[ -n "$APP" ]] || fail "there is no application inside $IMAGE"

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")"
# Sparkle compares CFBundleVersion and displays the short string. An appcast with
# only one of the two either cannot decide what is newer or cannot say what it is.
BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")"
# The commit the image was built from, read from the image rather than from the checkout.
# A tag naming the terminal's HEAD says nothing about the artifact beside it.
BUILD_COMMIT="$(plutil -extract UttrflowBuildCommit raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$BUILD_COMMIT" ]] \
    || fail "$(
        printf 'the image carries no UttrflowBuildCommit, so this release cannot be named\n'
        printf '  after the commit it was built from. Rebuild with Scripts/bundle.sh.'
    )"
[[ "$BUILD_COMMIT" == *-dirty ]] \
    && fail "the image was built from a dirty checkout ($BUILD_COMMIT); commit first"

# Notarised or not is a property of the file, not a matter of intent. Asked of the image,
# because the image is what somebody downloads and what Gatekeeper is shown first.
#
# It decides the TAG and the wording, and deliberately NOT the visibility. Every build
# published here is a full release, so GitHub's /releases/latest/download/ URL resolves to
# the newest one and the download button needs no change when a build is notarised for the
# first time. The unsigned window is a stated cost of that: until a Developer ID exists,
# the address on the site serves a build macOS calls damaged.
if xcrun stapler validate "$IMAGE" >/dev/null 2>&1; then
    NOTARISED=yes
else
    NOTARISED=no
fi

# Sparkle's tools arrive with the package, not with the build: `make app` goes through
# xcodebuild into .build/xcode, which never populates SwiftPM's own artifacts. A fresh
# clone therefore reaches this point with no signing tool at all — resolved here rather
# than left as a precondition nobody knew about.
if [[ ! -x "$SIGN_UPDATE" ]]; then
    printf '  resolving Sparkle for its signing tool\n'
    swift package resolve >/dev/null 2>&1 \
        || fail "could not resolve the package to get $SIGN_UPDATE"
fi
[[ -x "$SIGN_UPDATE" ]] || fail "$(
    printf '%s is missing even after resolving.\n' "$SIGN_UPDATE"
    printf '  Without it the archive cannot be signed, and an unsigned archive is one\n'
    printf '  every installed copy will refuse.'
)"

# The zip the updater fetches, built from the app *inside the image* and before it is
# detached — so the two assets in the release cannot be different builds. Staged here and
# uploaded further down with everything else.
ARCHIVE_STAGE="$(mktemp -d -t uttrflow-archive)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_STAGE/$ARCHIVE" \
    || fail "could not build $ARCHIVE"

hdiutil detach "$MOUNTED" -quiet; MOUNTED=""

SIZE="$(stat -f%z "$IMAGE")"

# The archive's own signature and length, which is what an appcast enclosure carries.
# Signed with the EdDSA key in this Mac's login keychain — see Docs/releasing.md ("Updating"). This
# signature, and not the code signature, is what an updating app checks: it is why an
# ad-hoc build can update itself safely, and it is the whole of this feature's security
# until there is a Developer ID.
SIGNATURE="$("$SIGN_UPDATE" "$ARCHIVE_STAGE/$ARCHIVE" 2>/dev/null)" || SIGNATURE=""
[[ -n "$SIGNATURE" ]] || fail "$(
    printf 'could not sign %s.\n' "$ARCHIVE"
    printf '  The private key lives in this Mac'"'"'s login keychain. On a new machine run\n'
    printf '    %s\n' "$GENERATE_KEYS"
    printf '  — but note that a *new* key means every installed copy stops accepting\n'
    printf '  updates, because the public half is compiled into them.'
)"

if [[ "$NOTARISED" == "yes" ]]; then
    TAG="v$VERSION"
    GATEKEEPER="notarised"
    NOTES="Notarised by Apple. Opens with a double-click on macOS 26 or later."
else
    # A test build never takes a bare version tag: that tag belongs to the real release of
    # that version, which may not exist yet.
    # An unsigned build still never takes a bare version tag: that tag belongs to the
    # notarised release of that version, which may not exist yet. Distinct tags are what
    # let the real v$VERSION publish later without colliding with this one — and, being a
    # full release, it takes over /releases/latest/download/ the moment it lands.
    TAG="v$VERSION-test.$BUILD_COMMIT"
    GATEKEEPER="unsigned"
    NOTES="$(cat <<EOF
Test build from \`$BUILD_COMMIT\` — **not notarised**.

macOS will say the app is damaged. It is not. Drag Uttrflow to Applications, then run:

\`\`\`
xattr -dr com.apple.quarantine /Applications/Uttrflow.app
\`\`\`

Sending it with scp, rsync or a USB stick sets no quarantine and needs none of this.
EOF
)"
fi

printf '  image        %s (%s)\n' "$IMAGE" "$(du -h "$IMAGE" | cut -f1)"
printf '  archive      %s (%s) — signed, what an installed copy will fetch\n' \
    "$ARCHIVE" "$(du -h "$ARCHIVE_STAGE/$ARCHIVE" | cut -f1)"
printf '  version      %s\n' "$VERSION"
printf '  gatekeeper   %s\n' "$GATEKEEPER"
printf '  tag          %s\n' "$TAG"
printf '  repository   %s\n' "$DOWNLOADS_REPO"
printf '  latest.json  will be rewritten to point at this release\n'
if [[ "$NOTARISED" != "yes" ]]; then
    # Said here rather than left to be discovered on the site, because this is the one
    # consequence that is invisible from the command being typed.
    printf '  download     THIS UNSIGNED BUILD BECOMES uttrflow.com/download\n'
    printf '               macOS will call it damaged; every visitor needs the xattr command\n'
fi

# Refuses to publish over an existing tag rather than working out which of the two files
# is the real one afterwards.
if gh release view "$TAG" --repo "$DOWNLOADS_REPO" >/dev/null 2>&1; then
    fail "$(
        printf '%s already exists in %s.\n' "$TAG" "$DOWNLOADS_REPO"
        printf '  Bump CFBundleShortVersionString, or delete the release first:\n'
        printf '    gh release delete %s --repo %s --cleanup-tag' "$TAG" "$DOWNLOADS_REPO"
    )"
fi

if [[ "$DRY_RUN" == "yes" ]]; then
    printf '\nDry run — nothing was published.\n'
    exit 0
fi

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------

step "Publishing"

STAGE="$(mktemp -d -t uttrflow-publish)"
cp "$IMAGE" "$STAGE/$ASSET"

cp "$ARCHIVE_STAGE/$ARCHIVE" "$STAGE/$ARCHIVE"

gh release create "$TAG" "$STAGE/$ASSET" "$STAGE/$ARCHIVE" \
    --repo "$DOWNLOADS_REPO" \
    --title "Uttrflow $VERSION" \
    --notes "$NOTES" \
    || fail "could not create the release"

# ---------------------------------------------------------------------------
# The manifest
# ---------------------------------------------------------------------------
# Rewritten by every publish, so the version named on the site matches the file the
# download button serves. The manifest only decorates that URL — it never carries it — so
# a stale or blocked manifest costs a version label rather than the download itself.

step "Pointing latest.json at $VERSION"

CLONE="$(mktemp -d -t uttrflow-downloads)"
gh repo clone "$DOWNLOADS_REPO" "$CLONE" -- --depth 1 --quiet \
    || fail "could not clone $DOWNLOADS_REPO"

    SIZE="$SIZE" VERSION="$VERSION" TAG="$TAG" REPO="$DOWNLOADS_REPO" ASSET="$ASSET" \
    GATEKEEPER="$GATEKEEPER" \
    python3 - "$CLONE/latest.json" <<'PY'
import datetime, json, os, sys, pathlib

repo, asset = os.environ["REPO"], os.environ["ASSET"]
manifest = {
    "version": os.environ["VERSION"],
    "published": datetime.datetime.now(datetime.UTC).replace(microsecond=0)
        .isoformat().replace("+00:00", "Z"),
    "notes": f"https://github.com/{repo}/releases/tag/{os.environ['TAG']}",
    "builds": [{
        "os": "macos",
        # arm64 only: Scripts/bundle.sh builds for this Mac's architecture, and the
        # speech stack is Apple Silicon in practice.
        "architecture": "appleSilicon",
        "version": os.environ["VERSION"],
        # The constant, deliberately not the tagged URL — this is the address that goes
        # on keeping when the next version lands.
        "url": f"https://github.com/{repo}/releases/latest/download/{asset}",
        "size": int(os.environ["SIZE"]),
        "requires": "macOS 26",
        "gatekeeper": os.environ["GATEKEEPER"],
    }],
}
pathlib.Path(sys.argv[1]).write_text(json.dumps(manifest, indent=2) + "\n")
PY

# The appcast, beside the manifest. Read by the backend rather than by the app —
# `internal/api/updates.go` explains why the address the app asks is ours and not this
# one — but written here, because this is where a release is made and where the archive
# and its signature exist.
#
# One item, always. An appcast with a history is a feed carrying several answers to "what
# should I install"; Sparkle takes the newest regardless, and the older entries only name
# archives that later releases have replaced.
step "Writing the appcast"

ARCHIVE_SIZE="$(stat -f%z "$ARCHIVE_STAGE/$ARCHIVE")"
NOTES_URL="https://github.com/$DOWNLOADS_REPO/releases/tag/$TAG"

ARCHIVE_SIZE="$ARCHIVE_SIZE" ARCHIVE_NAME="$ARCHIVE" SIGNATURE="$SIGNATURE" \
    VERSION="$VERSION" BUILD="$BUILD" REPO="$DOWNLOADS_REPO" NOTES_URL="$NOTES_URL" \
    MINIMUM_SYSTEM="26.0" \
    python3 "$SCRIPT_DIR/appcast.py" "$CLONE/appcast.xml" \
    || fail "could not write the appcast"

git -C "$CLONE" add latest.json appcast.xml
if git -C "$CLONE" diff --cached --quiet; then
    echo "  already current"
else
    git -C "$CLONE" commit -q -m "Uttrflow $VERSION"
    git -C "$CLONE" push -q || fail "could not push latest.json"
    echo "  updated"
fi
rm -rf "$CLONE"

cat <<EOF

Published Uttrflow $VERSION.

  release   https://github.com/$DOWNLOADS_REPO/releases/tag/$TAG
EOF

cat <<EOF
  download  https://github.com/$DOWNLOADS_REPO/releases/latest/download/$ASSET
            (permanent — it follows every future release)

uttrflow.com/download names this version as soon as the manifest propagates.
EOF

if [[ "$NOTARISED" != "yes" ]]; then
    cat <<EOF

That address now serves an UNSIGNED build. Anyone downloading it through a browser gets
"Uttrflow is damaged and can't be opened" until they run:

  xattr -dr com.apple.quarantine /Applications/Uttrflow.app

Publishing a notarised image of any version replaces it, with no change to the site.
EOF
fi

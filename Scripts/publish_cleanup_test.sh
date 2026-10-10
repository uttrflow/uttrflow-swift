#!/usr/bin/env bash
#
# Proves Scripts/publish.sh leaves no release-sized temporary behind: not after a dry
# run, not after a successful publish, and not after a failure before or after
# `gh release create` runs. Everything here is local — a real dmg built with hdiutil, a
# bare git repo standing in for the downloads repository, and mocked `gh` and `xcrun` —
# so it never reaches GitHub or Apple.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

# A temporary directory of its own, which publish.sh's `mktemp -t` follows: a publish or another
# test running beside this one never shows here, and this never removes theirs.
export TMPDIR="$test_root/tmp"
mkdir -p "$TMPDIR"
tmp_scratch="$TMPDIR"

leftover() {
    # Anything matching the prefixes publish.sh stages its temporaries under.
    find "$tmp_scratch" -maxdepth 1 \
        \( -name 'uttrflow-archive*' -o -name 'uttrflow-publish*' -o -name 'uttrflow-downloads*' \) \
        2>/dev/null || true
}

assert_no_leftover() {
    local label="$1"
    local found
    found="$(leftover)"
    if [[ -n "$found" ]]; then
        echo "error: $label left temporary directories behind:" >&2
        printf '%s\n' "$found" >&2
        exit 1
    fi
}

# --- A sandbox that mirrors the layout publish.sh expects relative to its own path ---

sandbox="$test_root/sandbox"
mkdir -p "$sandbox/Scripts" "$sandbox/.build/artifacts/sparkle/Sparkle/bin" "$sandbox/dist"
cp "$repo_root/Scripts/publish.sh" "$sandbox/Scripts/publish.sh"
cp "$repo_root/Scripts/appcast.py" "$sandbox/Scripts/appcast.py"
cp "$repo_root/Scripts/update_feed_gate.py" "$sandbox/Scripts/update_feed_gate.py"
chmod +x "$sandbox/Scripts/publish.sh"

cat > "$sandbox/.build/artifacts/sparkle/Sparkle/bin/sign_update" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
archive="$1"
[[ "$archive" == -s ]] && archive="$3"
size="$(stat -f%z "$archive")"
echo "sparkle:edSignature=\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==\" length=\"$size\""
EOF
chmod +x "$sandbox/.build/artifacts/sparkle/Sparkle/bin/sign_update"

# --- A real, tiny, locally-built disk image: no network involved in making one ---

work="$test_root/work"
app="$work/Uttrflow.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>2026.1.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UttrflowBuildCommit</key>
    <string>abc123</string>
</dict>
</plist>
EOF
printf '#!/bin/sh\n' > "$app/Contents/MacOS/Uttrflow"
chmod +x "$app/Contents/MacOS/Uttrflow"

image="$sandbox/dist/Uttrflow-2026.1.1.dmg"
hdiutil create -volname Uttrflow -srcfolder "$work" -ov -format UDZO -quiet "$image" \
    || { echo "error: could not build the test disk image" >&2; exit 1; }

# --- A bare repo standing in for the downloads repository `gh repo clone` fetches ---

downloads_bare="$test_root/downloads.git"
git init --bare -q "$downloads_bare"
downloads_seed="$test_root/downloads-seed"
git init -q -b main "$downloads_seed"
git -C "$downloads_seed" config user.name "Publish Test"
git -C "$downloads_seed" config user.email "publish-test@example.invalid"
git -C "$downloads_seed" remote add origin "$downloads_bare"
echo '{}' > "$downloads_seed/latest.json"
printf '<?xml version="1.0"?><rss></rss>\n' > "$downloads_seed/appcast.xml"
git -C "$downloads_seed" add latest.json appcast.xml
git -C "$downloads_seed" commit -qm seed
git -C "$downloads_seed" push -q origin main

# --- Mocks: gh (release lookups, creation, and the downloads clone) and xcrun (stapler) ---

mock_bin="$test_root/bin"
mkdir -p "$mock_bin"
gh_log="$test_root/gh.log"
: > "$gh_log"

cat > "$mock_bin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "auth status" ]]; then
    exit 0
fi
if [[ "\$1 \$2" == "release view" ]]; then
    [[ "\${GH_RELEASE_EXISTS:-0}" == "1" ]] && exit 0 || exit 1
fi
if [[ "\$1 \$2" == "release create" ]]; then
    echo "release create: \$*" >> "$gh_log"
    [[ "\${GH_RELEASE_CREATE_FAIL:-0}" == "1" ]] && exit 1
    exit 0
fi
if [[ "\$1 \$2" == "repo clone" ]]; then
    [[ "\${GH_CLONE_FAIL:-0}" == "1" ]] && exit 1
    dest="\$4"
    git clone --quiet "$downloads_bare" "\$dest"
    exit 0
fi
echo "gh mock: unhandled invocation: \$*" >&2
exit 1
EOF
chmod +x "$mock_bin/gh"

# Notarisation is judged locally by `xcrun stapler validate`; this test never notarises,
# so the mock always answers "no" without touching Apple's network at all.
cat > "$mock_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$mock_bin/xcrun"

export PATH="$mock_bin:$PATH"
export GIT_AUTHOR_NAME="Publish Test" GIT_AUTHOR_EMAIL="publish-test@example.invalid"
export GIT_COMMITTER_NAME="Publish Test" GIT_COMMITTER_EMAIL="publish-test@example.invalid"
export UTTRFLOW_DOWNLOADS_REPO="uttrflow-test/releases"

run_publish() {
    ( cd "$sandbox" && "./Scripts/publish.sh" "$@" )
}

# --- Scenario 1: dry run leaves nothing behind, including the archive stage ---

output="$(GH_RELEASE_EXISTS=0 run_publish --dry-run "$image" 2>&1)" && status=0 || status=$?
[[ "$status" -eq 0 ]] || { echo "error: dry run failed unexpectedly:" >&2; echo "$output" >&2; exit 1; }
grep -Fq 'Dry run' <<< "$output" || { echo "error: dry run did not say so:" >&2; echo "$output" >&2; exit 1; }
grep -Fq 'THIS UNSIGNED BUILD BECOMES uttrflow.com/download' <<< "$output" \
    || { echo "error: stable unsigned release warning disappeared:" >&2; echo "$output" >&2; exit 1; }
output="$(GITHUB_REF_NAME=v2026.1.1-rc.1 GH_RELEASE_EXISTS=0 run_publish --dry-run "$image" 2>&1)" \
    && status=0 || status=$?
[[ "$status" -eq 0 ]] || { echo "error: prerelease dry run failed unexpectedly:" >&2; echo "$output" >&2; exit 1; }
grep -Fq 'this prerelease address serves an unsigned build; the website stays unchanged' <<< "$output" \
    || { echo "error: prerelease warning does not describe its tag-only address:" >&2; echo "$output" >&2; exit 1; }
if grep -Fq 'THIS UNSIGNED BUILD BECOMES uttrflow.com/download' <<< "$output"; then
    echo "error: prerelease warning falsely says the website moves:" >&2
    echo "$output" >&2
    exit 1
fi
assert_no_leftover "a dry run"

# --- Scenario 2: a successful publish cleans the archive stage, the upload stage, and the clone ---

output="$(GH_RELEASE_EXISTS=0 GH_CLONE_FAIL=0 GH_RELEASE_CREATE_FAIL=0 run_publish "$image" 2>&1)" \
    && status=0 || status=$?
[[ "$status" -eq 0 ]] || { echo "error: publish failed unexpectedly:" >&2; echo "$output" >&2; exit 1; }
grep -Fq 'release create' "$gh_log" || { echo "error: gh release create was never called" >&2; exit 1; }
assert_no_leftover "a successful publish"

# --- Scenario 3: a failure before `gh release create` (an existing tag) still cleans the archive stage ---

: > "$gh_log"
output="$(GH_RELEASE_EXISTS=1 run_publish "$image" 2>&1)" && status=0 || status=$?
[[ "$status" -ne 0 ]] || { echo "error: publish over an existing tag did not fail" >&2; exit 1; }
grep -Fq 'already exists' <<< "$output" || { echo "error: wrong failure reason:" >&2; echo "$output" >&2; exit 1; }
[[ ! -s "$gh_log" ]] || { echo "error: gh release create ran despite the existing tag" >&2; exit 1; }
assert_no_leftover "a failure before release creation"

# --- Scenario 4: a failure after `gh release create` (the downloads clone fails) cleans everything ---

: > "$gh_log"
output="$(GH_RELEASE_EXISTS=0 GH_CLONE_FAIL=1 GH_RELEASE_CREATE_FAIL=0 run_publish "$image" 2>&1)" \
    && status=0 || status=$?
[[ "$status" -ne 0 ]] || { echo "error: publish with a failing clone did not fail" >&2; exit 1; }
grep -Fq 'release create' "$gh_log" || { echo "error: the release-creation step never ran before the clone failed" >&2; exit 1; }
grep -Fq 'could not clone' <<< "$output" || { echo "error: wrong failure reason:" >&2; echo "$output" >&2; exit 1; }
assert_no_leftover "a failure after release creation"

printf 'publish cleanup test passed\n'

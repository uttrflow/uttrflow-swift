#!/usr/bin/env bash
#
# Keeps other people's personal data out of a repository that is about to be public.
#
# Two things were found in this tree and removed, and both had been here for weeks
# without anybody noticing, because both looked exactly like the sample data they were
# sitting among:
#
#   A real residential address — a real apartment complex, on a real road, with a real
#   pincode — used as the sample expansion for the "my address" snippet. It belonged to
#   somebody who has no connection to this project and never agreed to appear in it. By
#   the time it was found it had spread to eleven files, and to both sides of the Design
#   generator, because sample data gets copied.
#
#   The owner's personal email address, used as the account fixture in the tests and
#   drawn into the account artboards.
#
# Neither was a mistake anybody made carelessly. Fixture data has to look real to be
# useful, and the most available realistic value is one you can see from where you are
# sitting. That is why this is a gate and not a note in a review checklist: the next
# person needing a plausible address will reach for the same thing, and a convention
# lasts exactly as long as the person who remembers it.
#
# What raises the stakes is publication. Committing a stranger's address to a private
# repository is a mistake that can be quietly fixed. Publishing it cannot be — a public
# repository is cloned, cached and indexed within minutes, and history rewriting does
# not reach any of those copies.
#
# This audit is deliberately narrow. It looks for personal data, not for credentials:
# `Tests/UttrflowClipboardTests/SecretDetectionTests.swift` is full of secret-shaped
# strings that must stay, because the clipboard's whole job there is recognising them.
# Those fixtures are checked by the tests around them, and the real credential question
# is answered structurally by `EvaluationSeparationTests` and `Scripts/offline_audit.sh`.
#
# Usage:  ./Scripts/pii_audit.sh        (also runs as part of `make verify`)
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

failures=0

# Each failure says what broke and why it matters. The same shape as offline_audit.sh,
# and for the same reason: "pii_audit.sh: FAILED" tells the next person nothing they can
# act on at the moment they are blocked by it.
fail() {
    printf '\n  ✗ %s\n' "$1" >&2
    shift
    for line in "$@"; do printf '    %s\n' "$line" >&2; done
    failures=$((failures + 1))
}

pass() { printf '  ✓ %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 0. The scan must actually be looking at something.
# ---------------------------------------------------------------------------
#
# This check exists because of a bug this repository has already had once, in a different
# suite: `BackendContractTests` returned nil when its fixture was missing, so a wrong path
# and an absent backend were indistinguishable, and it sat green and dead for days. An
# audit that silently scans nothing is worse than no audit, because it reports success.
#
# `--others --exclude-standard` here, and `--untracked` on every git grep below, because
# a file that has been written but not yet staged is exactly the file most likely to have
# a fresh address in it. This project has been caught by that before: a sweep used plain
# `git grep`, reported clean, and had silently skipped four new files that were not added
# yet. Ignored paths stay out — .build, dist and Models are not ours to police.
SCANNED="$(git ls-files --cached --others --exclude-standard | wc -l | tr -d ' ')"

printf 'What is being scanned\n'

if [[ "$SCANNED" -lt 100 ]]; then
    fail "only $SCANNED files found — this is not the Uttrflow tree" \
        "Either this is not a git checkout, or it is a partial one. Every check below" \
        "would pass trivially on an empty file list, which is why this stops here."
    printf '\npii audit: could not run.\n\n' >&2
    exit 1
fi
pass "$SCANNED files (tracked, plus written-but-not-yet-staged)"

# ---------------------------------------------------------------------------
# 1. No email address outside the domains reserved for documentation.
# ---------------------------------------------------------------------------
#
# The rule is a whitelist of domains rather than a blacklist of people, because a
# blacklist only ever contains the addresses somebody already thought of, and the next
# one to appear will belong to a beta tester or a bug reporter.
#
# Reserved by RFC 2606 for exactly this use: `example.com`, `.example`, `.invalid`,
# `.test`. Also allowed are `.local` (mDNS, so `you@other-mac.local` is a real thing to
# write in a test) and `.internal` (private networks by convention). Any label `example`
# anywhere in the domain counts, which is what lets the connection-string fixtures use
# `db.example.com` and `cluster0.example.mongodb.net`.
#
# If you need a plausible address in a fixture, `someone@example.com` is plausible.
EMAIL_SHAPE='(^|[^/[:alnum:]._%+-])[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}'

# `example` as a domain label, or a reserved TLD. Matched against the address, so the
# `@` anchors it to the domain and a local part called "example" does not slip through.
RESERVED='(^|@|\.)([[:alnum:]-]+\.)*example(\.[[:alnum:].]+)?$|\.(invalid|test|local|internal|localdomain)$'

printf '\nEmail addresses\n'

# The leading character captured by EMAIL_SHAPE is stripped back off: it is there to
# prove the match is not the userinfo half of a URL — `https://token@github.com/...` is
# a credential-shaped URL, not somebody's address — and is not part of the address.
found_emails="$(
    git grep --untracked -hoIE "$EMAIL_SHAPE" -- . 2>/dev/null \
        | sed -E 's/^[^[:alnum:]]//' \
        | sort -u \
        | grep -vEi "$RESERVED" || true
)"

if [[ -n "${found_emails//[[:space:]]/}" ]]; then
    # Locate each one, so the message names files rather than leaving a search to do.
    locations=""
    while IFS= read -r address; do
        [[ -z "$address" ]] && continue
        locations+="$(git grep --untracked -nIF "$address" -- . | head -5 || true)"$'\n'
    done <<<"$found_emails"

    fail "an email address outside the reserved domains is in the tree" \
        "This repository is going public. An address committed here is published," \
        "and publishing cannot be undone by a later commit." \
        "" \
        "If it is fixture data, use example.com — it is reserved for this and it is" \
        "no less plausible. If it belongs to a real person, it does not belong here" \
        "at all." \
        "" $'\n'"$locations"
else
    pass "every address is on a domain reserved for documentation"
fi

# ---------------------------------------------------------------------------
# 2. The address that was removed has not come back.
# ---------------------------------------------------------------------------
#
# Check 1 cannot catch this: a postal address is not email-shaped and has no syntax to
# key on. So this half is specific, and specific to what was actually found.
#
# The terms are stored base64, and that is not obfuscation — it is the only way this
# file can name them without defeating its own purpose. A plain-text list here would
# republish, inside the gate, the exact address the gate exists to keep out; it would
# also match itself on every run, so the audit could never pass. Decoded at runtime, the
# strings exist only in memory.
#
# Decode them if you need to see them:  echo '<token>' | base64 -d
FORBIDDEN_B64=(
    UHJlc3RpZ2UgQWNyb3BvbGlz  # the complex
    SG9zdXIgUm9hZA==          # the road
    NTYwMDI5                  # the pincode
)

printf '\nThe address that was removed\n'

offenders=""
for token_b64 in "${FORBIDDEN_B64[@]}"; do
    token="$(printf '%s' "$token_b64" | base64 -d 2>/dev/null || true)"
    if [[ -z "$token" ]]; then
        fail "a forbidden term did not decode" \
            "One of the base64 constants in this script is malformed, so the term it" \
            "stands for is not being checked at all. Fix the constant."
        continue
    fi
    # -F: these are literal strings, and one of them is a number that would otherwise be
    # read as a pattern. Case-insensitive, because a fixture is as likely to be lower.
    hits="$(git grep --untracked -nIFi "$token" -- . || true)"
    # if/fi rather than `[[ ... ]] && ...`, which returns 1 when the test is false and
    # would end the script here under `set -e` — on the good path, silently.
    if [[ -n "$hits" ]]; then
        offenders+="$hits"$'\n'
    fi
done

# One line can hold several of the terms, and reporting it once per term reads as
# three separate problems. Deduplicated so the count matches what is actually wrong.
offenders="$(printf '%s' "$offenders" | sort -u)"

if [[ -n "${offenders//[[:space:]]/}" ]]; then
    fail "the residential address that was removed from this tree is back in it" \
        "It is a real address belonging to somebody with no connection to this" \
        "project, and it was sample data for the \"my address\" snippet, so it spreads" \
        "wherever that sample is copied." \
        "" \
        "Use the invented one already in the fixtures:" \
        "  Flat 402, Example Residences, Sample Road, Bengaluru 560001" \
        "" $'\n'"$offenders"
else
    pass "none of the ${#FORBIDDEN_B64[@]} removed address terms appears anywhere"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [[ "$failures" -gt 0 ]]; then
    printf 'pii audit: %s check(s) failed. Nothing above may be published.\n\n' "$failures" >&2
    exit 1
fi

printf 'pii audit: no personal data in %s files.\n\n' "$SCANNED"

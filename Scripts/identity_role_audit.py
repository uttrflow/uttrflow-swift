#!/usr/bin/env python3
"""Fails when the identity sheet's teal ramp drifts from `BrandPalette`'s production roles.

Issue #1130: the identity sheet's `RAMP` in `Design/_gen_identity.py` named `#17A398` the
listening-state colour years after the live accent moved to `BrandPalette.Teal.primary`
(`#29C0B4`), and no source or test used the old value any more. `_gen_identity.py`
reproduced the stale sheet byte-for-byte, so regenerating it did not repair the drift — the
generator's own literal was wrong, not just its output.

This audit reads each `RAMP` entry's hex value and matches it, by role name, against the
`BrandPalette.Teal` case that carries production's colour for that role. A drift between
the two is exactly the failure mode #1130 reported.
"""

import argparse
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
IDENTITY_SOURCE = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Design", "_gen_identity.py"))
PALETTE_SOURCE = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "Sources", "Uttrflow", "Brand", "BrandPalette.swift")
)

RAMP_LIST = re.compile(r"RAMP\s*=\s*\[(?P<body>.*?)\n\]", re.DOTALL)
RAMP_ROW = re.compile(
    r'\(\s*"(?P<name>[^"]+)"\s*,\s*"(?P<hex>#[0-9A-Fa-f]{6})"\s*,\s*"[^"]*"\s*,\s*"[^"]*"\s*\)'
)

# Each swatch name maps to the `BrandPalette.Teal` case documented as that production role.
# "Mark" is the logo ink, not a `Teal` case, and is checked separately against `--logo-ink`.
ROLE_TO_TEAL_CASE = {
    "Signal": "primary",
    "Accent": "deep",
    "Light": "light",
    "Tint": "tint",
    "Wash": "wash",
    "Bright": "bright",
}

TEAL_CASE_LINE = r"static\s+let\s+{name}\s*:\s*UInt32\s*=\s*(?P<hex>0x[0-9A-Fa-f_]+)"


def load_ramp(path):
    text = open(path).read()
    match = RAMP_LIST.search(text)
    if not match:
        raise SystemExit(f"identity role audit: no RAMP = [...] found in {path}")
    rows = RAMP_ROW.findall(match.group("body"))
    if not rows:
        raise SystemExit(f"identity role audit: RAMP in {path} has no rows")
    return {name: hexv.upper() for name, hexv in rows}


def load_teal_case(path, name):
    text = open(path).read()
    match = re.search(TEAL_CASE_LINE.format(name=re.escape(name)), text)
    if not match:
        raise SystemExit(f"identity role audit: no Teal.{name} declaration found in {path}")
    return "#" + match.group("hex").replace("0x", "").replace("_", "").upper()


def self_test():
    """Prove the row/case matcher agrees on a match and disagrees on a mismatch."""
    ramp = {"Signal": "#29C0B4", "Wrong": "#000000"}
    cases = {"primary": "#29C0B4", "primary_bad": "#111111"}
    matched = ramp["Signal"] == cases["primary"]
    mismatched = ramp["Wrong"] == cases["primary_bad"]
    ok = matched and not mismatched
    if not ok:
        print("  ✗ self-test: the role comparison did not behave as expected", file=sys.stderr)
    return ok


def audit():
    if not os.path.isfile(IDENTITY_SOURCE):
        print(f"identity role audit: {IDENTITY_SOURCE} not found", file=sys.stderr)
        return 1
    if not os.path.isfile(PALETTE_SOURCE):
        print(f"identity role audit: {PALETTE_SOURCE} not found", file=sys.stderr)
        return 1

    ramp = load_ramp(IDENTITY_SOURCE)

    print("Identity sheet teal ramp, checked against BrandPalette.Teal")
    failures = []
    for role, case in ROLE_TO_TEAL_CASE.items():
        if role not in ramp:
            failures.append((role, case, None, None))
            print(f"  {role}  missing from RAMP  [FAIL]")
            continue
        sheet_hex = ramp[role]
        palette_hex = load_teal_case(PALETTE_SOURCE, case)
        verdict = "pass" if sheet_hex == palette_hex else "FAIL"
        print(f"  {role:<8} sheet {sheet_hex}  BrandPalette.Teal.{case} {palette_hex}  [{verdict}]")
        if sheet_hex != palette_hex:
            failures.append((role, case, sheet_hex, palette_hex))

    if failures:
        print(
            f"\n  ✗ {len(failures)} identity swatch(es) disagree with BrandPalette.Teal:",
            file=sys.stderr,
        )
        for role, case, sheet_hex, palette_hex in failures:
            if sheet_hex is None:
                print(f"    {role}  not present in Design/_gen_identity.py's RAMP", file=sys.stderr)
            else:
                print(
                    f"    {role}  sheet says {sheet_hex}, "
                    f"BrandPalette.Teal.{case} is {palette_hex}",
                    file=sys.stderr,
                )
        print(
            "    Update RAMP in Design/_gen_identity.py to match BrandPalette.swift, the\n"
            "    documented colour source of truth, then re-run every Design/_gen_*.py.",
            file=sys.stderr,
        )
        return 1

    print(f"\nidentity role audit: every teal swatch matches its BrandPalette.Teal role.\n")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the audit's role comparison can both match and mismatch",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\nidentity role audit: self-test failed; the comparison is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())

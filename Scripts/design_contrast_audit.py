#!/usr/bin/env python3
"""Fails when a selected app palette pair falls below WCAG contrast.

The check reads explicit role pairs from `Sources/Uttrflow/Brand/BrandPalette.swift`: body text
roles against the app's ground, card, control and rail surfaces in both appearances, at 4.5:1,
and the text ghost and teal mark roles against those same surfaces at the 3:1 non-text
threshold.
"""

import argparse
import os
import re
import sys
import tempfile


REQUIRED_RATIO = 4.5
NONTEXT_REQUIRED_RATIO = 3.0
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WHITE = (1.0, 1.0, 1.0)
APP_PALETTE_SOURCE = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "Sources", "Uttrflow", "Brand", "BrandPalette.swift")
)

def hex_to_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))


def linearize(channel):
    return channel / 12.92 if channel <= 0.03928 else ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb):
    r, g, b = (linearize(channel) for channel in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg, bg):
    light = relative_luminance(fg)
    dark = relative_luminance(bg)
    lighter, darker = max(light, dark), min(light, dark)
    return (lighter + 0.05) / (darker + 0.05)


# A foreground / composited-background pair that fails or passes 4.5:1; the self-test exercises
# both the pass and the fail arms so the audit cannot regress to a no-op.
SELF_TEST_PAIRS = (
    ("#793F15", (0.827, 0.863, 0.886), REQUIRED_RATIO, 5.97, "pass"),
    ("#C2560C", (0.827, 0.863, 0.886), REQUIRED_RATIO, 3.27, "fail"),
)

# A tile fill against white, at the 3:1 non-text threshold; same pass/fail shape as above.
NONTEXT_SELF_TEST_PAIRS = (
    ("#C25E00", WHITE, NONTEXT_REQUIRED_RATIO, 4.29, "pass"),
    ("#FF8D28", WHITE, NONTEXT_REQUIRED_RATIO, 2.31, "fail"),
)

APP_TEXT_ROLES = (("Text", "primary"), ("Text", "muted"), ("Text", "dim"))
APP_MARK_ROLES = (("Text", "ghost"), ("Teal", "ink"))
APP_SURFACE_ROLES = (("Surface", "ground"), ("Surface", "card"), ("Surface", "control"), ("Surface", "rail"))


def enum_body(source, name):
    """Return one enum's body, counting braces from its declaration."""
    match = re.search(rf"\benum\s+{re.escape(name)}\s*\{{", source)
    if not match:
        raise SystemExit(f"design contrast audit: enum {name} not found in BrandPalette.swift")
    start = match.end()
    depth = 1
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise SystemExit(f"design contrast audit: enum {name} is not closed in BrandPalette.swift")


def palette_value(source, scope, name, appearance, seen=()):
    """Read one UInt32 or BrandTone role from an explicit palette scope."""
    if name in seen:
        raise SystemExit(f"design contrast audit: cyclic palette reference {scope}.{name}")
    body = enum_body(source, scope)
    declaration = re.search(
        rf"static\s+let\s+{re.escape(name)}\b(?:\s*:\s*[^=]+)?\s*=\s*"
        rf"(?P<value>[^\n]+(?:\n(?!\s*static\s+let).+)*)",
        body,
    )
    if not declaration:
        raise SystemExit(f"design contrast audit: no {scope}.{name} role in BrandPalette.swift")
    value = declaration.group("value").strip()
    if value.startswith("BrandTone("):
        token = re.search(rf"\b{appearance}\s*:\s*(0x[\da-fA-F_]+|[A-Za-z_]\w*)", value)
        if not token:
            raise SystemExit(
                f"design contrast audit: no {appearance} value for {scope}.{name} in BrandPalette.swift"
            )
        value = token.group(1)
        if not value.startswith("0x"):
            value = palette_value(source, scope, value, appearance, seen + (name,))
    else:
        token = re.match(r"(0x[\da-fA-F_]+|[A-Za-z_]\w*)", value)
        if token:
            value = token.group(1)
    if value.startswith("#"):
        return value
    if not re.fullmatch(r"0x[\da-fA-F_]+", value):
        raise SystemExit(f"design contrast audit: unsupported {scope}.{name} value {value!r}")
    digits = value[2:].replace("_", "")
    if len(digits) != 6:
        raise SystemExit(f"design contrast audit: {scope}.{name} is not a 24-bit colour")
    return f"#{int(digits, 16):06X}"


def audit_app_palette(path=APP_PALETTE_SOURCE):
    """Check the text and mark pairs the app's palette documents on shared surfaces."""
    try:
        with open(path, encoding="utf-8") as palette_file:
            source = palette_file.read()
    except OSError as error:
        raise SystemExit(f"design contrast audit: cannot read app palette {path}: {error}")

    rows = []
    failures = []
    pairs = [
        (
            "text", foreground_scope, foreground_name, surface_scope, surface_name,
            REQUIRED_RATIO,
        )
        for foreground_scope, foreground_name in APP_TEXT_ROLES
        for surface_scope, surface_name in APP_SURFACE_ROLES
    ] + [
        (
            "mark", foreground_scope, foreground_name, surface_scope, surface_name,
            NONTEXT_REQUIRED_RATIO,
        )
        for foreground_scope, foreground_name in APP_MARK_ROLES
        for surface_scope, surface_name in APP_SURFACE_ROLES
    ]
    for role, fg_scope, fg_name, bg_scope, bg_name, threshold in pairs:
        for appearance in ("light", "dark"):
            foreground = palette_value(source, fg_scope, fg_name, appearance)
            background = palette_value(source, bg_scope, bg_name, appearance)
            ratio = contrast_ratio(hex_to_rgb(foreground), hex_to_rgb(background))
            label = f"{role} {fg_scope}.{fg_name} on {bg_scope}.{bg_name} ({appearance})"
            rows.append((label, foreground, background, ratio, threshold))
            if ratio < threshold:
                failures.append((label, foreground, background, ratio, threshold))
    return rows, failures


def app_palette_self_test():
    """Prove a too-light primary text value is reported against its exact surface pair."""
    with open(APP_PALETTE_SOURCE, encoding="utf-8") as palette_file:
        source = palette_file.read()
    original = "static let primary = BrandTone(dark: 0xF4_F4F6, light: 0x17_1320)"
    changed = "static let primary = BrandTone(dark: 0xF4_F4F6, light: 0xFF_FFFF)"
    if original not in source:
        print("design contrast audit: app-palette self-test cannot find Text.primary", file=sys.stderr)
        return False
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as fixture:
        fixture.write(source.replace(original, changed, 1))
        fixture.flush()
        _, failures = audit_app_palette(fixture.name)
    expected = "text Text.primary on Surface.ground (light)"
    passed = any(label == expected for label, *_ in failures)
    if not passed:
        print(
            f"design contrast audit: app-palette self-test did not report {expected}",
            file=sys.stderr,
        )
    return passed


def self_test():
    wrong = []
    for fg_hex, bg_rgb, threshold, expected, outcome in SELF_TEST_PAIRS + NONTEXT_SELF_TEST_PAIRS:
        ratio = contrast_ratio(hex_to_rgb(fg_hex), bg_rgb)
        passes = ratio >= threshold
        if outcome == "pass" and not passes:
            wrong.append((fg_hex, ratio, outcome))
        if outcome == "fail" and passes:
            wrong.append((fg_hex, ratio, outcome))
    for fg_hex, ratio, outcome in wrong:
        print(
            f"  ✗ self-test: {fg_hex} ratio {ratio:.3f}:1 expected to {outcome}",
            file=sys.stderr,
        )
    return not wrong and app_palette_self_test()


def audit_app_palette_report():
    rows, failures = audit_app_palette()
    print("App palette text and mark contrast against shared surfaces")
    for label, foreground, background, ratio, threshold in rows:
        verdict = "pass" if ratio >= threshold else "FAIL"
        print(
            f"  {label}  {foreground} on {background}  {ratio:.2f}:1, "
            f"needs {threshold:.1f}:1  [{verdict}]"
        )
    if failures:
        print("\n  ✗ app palette pairs fall below their contrast threshold:", file=sys.stderr)
        for label, foreground, background, ratio, threshold in failures:
            print(
                f"    {label}  {foreground} on {background}  {ratio:.2f}:1, needs {threshold:.1f}:1",
                file=sys.stderr,
            )
        return 1
    print("\ndesign contrast audit: app palette pairs clear their contrast thresholds.\n")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the audit catches both a passing and a failing contrast pair",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\ndesign contrast audit: self-test failed; the ratio predicate is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit_app_palette_report()


if __name__ == "__main__":
    sys.exit(main())

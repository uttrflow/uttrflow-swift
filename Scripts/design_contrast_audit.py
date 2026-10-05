#!/usr/bin/env python3
"""Fails when an artboard or selected app palette pair falls below WCAG contrast.

The design checks read `Design/`; the app check reads explicit role pairs from
`Sources/Uttrflow/Brand/BrandPalette.swift`:

1. The menu bar artboard draws a translucent native-style menu (`rgba(250,250,253,0.72)`)
   over a radial gradient with three declared stops. The two text rows in the attention
   state — the status row and the recovery action — must clear 4.5:1 against every
   composited background the gradient can produce, because the backdrop blur cannot lift
   the menu above the gradient's brightest source stop.
2. The errors artboard draws every repair-state glyph in white on an opaque tile. Each
   tile's fill must clear 3:1 against white, the WCAG non-text threshold for an icon that
   carries meaning on its own.
3. The shared `--red-ink` token (`.btn.destructive` and any row that highlights an
   over-threshold count) must clear 4.5:1 against the opaque window background it is drawn
   on, light and dark, so it stays the readable critical ink rather than the bright
   `--red` fill.
4. Body text roles are checked against the app's ground, card and rail surfaces in both
   appearances. The text ghost and teal mark roles are checked at the non-text threshold
   against those same surfaces.

Sources: `Design/_gen_menubar.py`, `Design/_gen_errors.py`, `Design/_gen_common.py`,
`Design/_gen_shell.py`, and `BrandPalette.swift`. Each artboard generator writes a single
static file, so every artboard check runs against the generator rather than any one `.dc.html`
file; the regeneration contract — a second generator run leaves the worktree clean — is
`Scripts/docs_audit.sh`'s to enforce, not this script's.
"""

import argparse
import os
import re
import sys
import tempfile


GRADIENT = re.compile(
    r"radial-gradient\(\s*[^,]+,\s*(?P<a>#[0-9A-Fa-f]{6})\s+0%,\s*"
    r"(?P<b>#[0-9A-Fa-f]{6})\s+45%,\s*(?P<c>#[0-9A-Fa-f]{6})\s+100%\s*\)"
)
MENU_FILL = re.compile(
    r"\.menu\s*\{[^}]*background:\s*rgba?\(\s*"
    r"(?P<r>\d+)\s*,\s*(?P<g>\d+)\s*,\s*(?P<b>\d+)\s*(?:,\s*(?P<a>[\d.]+)\s*)?\)",
    re.DOTALL,
)
ATTENTION_STYLE = re.compile(
    r"ATTENTION_MENU\s*=\s*menu\(f?\"\"\"(?P<body>.*?)\"\"\"\s*\)", re.DOTALL
)
INLINE_COLOR = re.compile(r'style="color:\s*(?P<color>#[0-9A-Fa-f]{6}|var\(--[\w-]+\))"')
BANNER_CALL = re.compile(
    r'banner\(\s*(?:"(?P<fill>#[0-9A-Fa-f]{6})"|(?P<fill_name>[A-Za-z_]\w*))\s*,\s*'
    r'\w+\s*,\s*"(?P<title>[^"]*)"'
)
FILL_CONSTANT = re.compile(r'^(?P<name>[A-Z_]\w*)\s*=\s*"(?P<hex>#[0-9A-Fa-f]{6})"', re.MULTILINE)


REQUIRED_RATIO = 4.5
NONTEXT_REQUIRED_RATIO = 3.0
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Design", "_gen_menubar.py"))
ERRORS_SOURCE = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Design", "_gen_errors.py"))
WHITE = (1.0, 1.0, 1.0)
COMMON_SOURCE = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Design", "_gen_common.py"))
SHELL_SOURCE = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Design", "_gen_shell.py"))
APP_PALETTE_SOURCE = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "Sources", "Uttrflow", "Brand", "BrandPalette.swift")
)

TOKEN_HEX_LINE = r"--{name}:\s*(?P<hex>#[0-9A-Fa-f]{{6}});"


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


def composite(fg_rgba, bg_opaque):
    """Composite a translucent fill over an opaque background (Porter-Duff over)."""
    fr, fg_, fb, fa = fg_rgba
    br, bg_, bb = bg_opaque
    return (
        br * (1 - fa) + fr * fa,
        bg_ * (1 - fa) + fg_ * fa,
        bb * (1 - fa) + fb * fa,
    )


def load_colors(path):
    """Pull the gradient stops, the menu fill, and the two attention-row text colors.

    Returns (stops, fill, [(label, fg_hex)]) where each `fg_hex` is a 6-digit string and the
    `label` is the menu-row text that identifies the foreground.
    """
    text = open(path).read()

    gradient = GRADIENT.search(text)
    if not gradient:
        raise SystemExit(f"design contrast audit: no radial-gradient found in {path}")
    stops = [hex_to_rgb(gradient.group(k)) for k in ("a", "b", "c")]

    fill = MENU_FILL.search(text)
    if not fill:
        raise SystemExit(f"design contrast audit: no .menu background fill found in {path}")
    r = int(fill.group("r")) / 255.0
    g = int(fill.group("g")) / 255.0
    b = int(fill.group("b")) / 255.0
    a = float(fill.group("a") or "1")
    menu_fill = (r, g, b, a)

    attention = ATTENTION_STYLE.search(text)
    if not attention:
        raise SystemExit(f"design contrast audit: ATTENTION_MENU not found in {path}")

    rows = []
    for match in INLINE_COLOR.finditer(attention.group("body")):
        color = match.group("color")
        rows.append((match.string[match.start():match.end()], color))

    if len(rows) != 2:
        raise SystemExit(
            f"design contrast audit: expected two attention-row text colors in {path}, found {len(rows)}"
        )

    return stops, menu_fill, rows


def load_error_tiles(path):
    """Pull each error tile's fill colour and title from `banner(...)` calls.

    Returns [(title, fill_hex)]. A tile's fill is either an inline hex literal or a
    module-level `NAME = "#hex"` constant, resolved against the constants in the same file.
    """
    text = open(path).read()
    constants = {name: hexv for name, hexv in FILL_CONSTANT.findall(text)}

    tiles = []
    for match in BANNER_CALL.finditer(text):
        title = match.group("title")
        fill = match.group("fill")
        if fill is None:
            name = match.group("fill_name")
            if name not in constants:
                raise SystemExit(
                    f"design contrast audit: unknown fill constant {name!r} in {path}"
                )
            fill = constants[name]
        tiles.append((title, fill))

    if not tiles:
        raise SystemExit(f"design contrast audit: no banner(...) tiles found in {path}")

    return tiles


# Resolve a foreground token. The accent is the only `var(--…)` token the menu uses as text;
# if a future generator routes the recovery row through a deeper accent, the check stays
# pinned to whatever the file says.
TOKEN_HEX = {
    "--accent": "#128077",
}


def resolve(color):
    if color.startswith("var("):
        name = color[4:].rstrip(")")
        if name not in TOKEN_HEX:
            raise SystemExit(
                f"design contrast audit: unknown token {color!r}; add it to TOKEN_HEX"
            )
        return hex_to_rgb(TOKEN_HEX[name])
    return hex_to_rgb(color)


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


def load_token(path, name):
    text = open(path).read()
    match = re.search(TOKEN_HEX_LINE.format(name=re.escape(name)), text)
    if not match:
        raise SystemExit(f"design contrast audit: no --{name} declaration found in {path}")
    return match.group("hex")


# The shared destructive/critical-count text role, checked against the opaque window
# background it sits on in each appearance — light from `_gen_common.py`'s root tokens,
# dark from `_gen_shell.py`'s `.theme-dark` override of the same token names.
DESTRUCTIVE_SURFACES = (
    ("light", COMMON_SOURCE, COMMON_SOURCE),
    ("dark", SHELL_SOURCE, SHELL_SOURCE),
)


def audit_destructive_text():
    failures = []
    rows = []
    for theme, ink_source, bg_source in DESTRUCTIVE_SURFACES:
        ink_hex = load_token(ink_source, "red-ink")
        bg_hex = load_token(bg_source, "window-bg")
        ratio = contrast_ratio(hex_to_rgb(ink_hex), hex_to_rgb(bg_hex))
        verdict = "pass" if ratio >= REQUIRED_RATIO else "FAIL"
        rows.append((theme, ink_hex, bg_hex, ratio, verdict))
        if ratio < REQUIRED_RATIO:
            failures.append((theme, ink_hex, bg_hex, ratio))
    return rows, failures


def audit():
    if not os.path.isfile(SOURCE):
        print(f"design contrast audit: {SOURCE} not found", file=sys.stderr)
        return 1

    stops, fill, rows = load_colors(SOURCE)
    composited = [composite(fill, stop) for stop in stops]

    print("Menu-bar attention state, text contrast against composited backgrounds")
    print(f"  gradient stops: {len(stops)}")
    print(f"  menu fill alpha: {fill[3]:.2f}")
    failures = []
    for fg_label, fg_color in rows:
        fg = resolve(fg_color)
        ratios = [contrast_ratio(fg, bg) for bg in composited]
        worst = min(ratios)
        verdict = "pass" if worst >= REQUIRED_RATIO else "FAIL"
        print(f"  {fg_label}  {fg_color}  worst {worst:.2f}:1  [{verdict}]")
        if worst < REQUIRED_RATIO:
            failures.append((fg_label, fg_color, worst))

    if failures:
        print(
            f"\n  ✗ {len(failures)} attention row(s) fall below WCAG AA text contrast "
            f"({REQUIRED_RATIO:.2f}:1) over the menu's composited backgrounds:",
            file=sys.stderr,
        )
        for fg_label, fg_color, worst in failures:
            print(
                f"    {fg_label}  {fg_color}  worst {worst:.2f}:1",
                file=sys.stderr,
            )
        print(
            "    The menu is translucent over a gradient; backdrop blur cannot lift the backing\n"
            "    above the gradient's brightest stop, so every stop is a real worst case.\n"
            "    Pick a deeper foreground and re-run; see `Design/_gen_menubar.py`.",
            file=sys.stderr,
        )
        return 1

    print(f"\ndesign contrast audit: every attention text row clears {REQUIRED_RATIO:.2f}:1.\n")

    print("Destructive/critical-count text, contrast against the window background")
    destructive_rows, destructive_failures = audit_destructive_text()
    for theme, ink_hex, bg_hex, ratio, verdict in destructive_rows:
        print(f"  {theme}  {ink_hex} on {bg_hex}  {ratio:.2f}:1  [{verdict}]")

    if destructive_failures:
        print(
            f"\n  ✗ {len(destructive_failures)} destructive/critical-count text role(s) fall "
            f"below WCAG AA text contrast ({REQUIRED_RATIO:.2f}:1):",
            file=sys.stderr,
        )
        for theme, ink_hex, bg_hex, ratio in destructive_failures:
            print(f"    {theme}  {ink_hex} on {bg_hex}  {ratio:.2f}:1", file=sys.stderr)
        print(
            "    `--red-ink` is the readable text role; `--red` is the bright fill and never\n"
            "    carries text. See `Design/_gen_common.py` and `Design/_gen_shell.py`.",
            file=sys.stderr,
        )
        return 1

    print(f"\ndesign contrast audit: destructive/critical-count text clears {REQUIRED_RATIO:.2f}:1.\n")
    return 0


def audit_errors():
    if not os.path.isfile(ERRORS_SOURCE):
        print(f"design contrast audit: {ERRORS_SOURCE} not found", file=sys.stderr)
        return 1

    tiles = load_error_tiles(ERRORS_SOURCE)

    print("Errors artboard, white glyph contrast against each tile fill")
    failures = []
    for title, fill_hex in tiles:
        ratio = contrast_ratio(WHITE, hex_to_rgb(fill_hex))
        verdict = "pass" if ratio >= NONTEXT_REQUIRED_RATIO else "FAIL"
        print(f"  {title}  {fill_hex}  {ratio:.2f}:1  [{verdict}]")
        if ratio < NONTEXT_REQUIRED_RATIO:
            failures.append((title, fill_hex, ratio))

    if failures:
        print(
            f"\n  ✗ {len(failures)} error tile(s) fall below the WCAG non-text contrast "
            f"threshold ({NONTEXT_REQUIRED_RATIO:.2f}:1) for their white glyph:",
            file=sys.stderr,
        )
        for title, fill_hex, ratio in failures:
            print(f"    {title}  {fill_hex}  {ratio:.2f}:1", file=sys.stderr)
        print(
            "    Use the semantic warning fill role for a white warning glyph; see\n"
            "    `Design/_gen_errors.py` and `BrandPalette.Semantic.warningFill`.",
            file=sys.stderr,
        )
        return 1

    print(f"\ndesign contrast audit: every error tile glyph clears {NONTEXT_REQUIRED_RATIO:.2f}:1.\n")
    return 0


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

    menubar_result = audit()
    errors_result = audit_errors()
    app_result = audit_app_palette_report()
    return menubar_result or errors_result or app_result


if __name__ == "__main__":
    sys.exit(main())

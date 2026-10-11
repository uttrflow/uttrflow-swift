#!/usr/bin/env python3
"""Fails when a colour or a brand typeface is defined outside its one home.

`Docs/agents/design.md` names the homes: every colour the app draws is a role in
`Sources/Uttrflow/Brand/BrandPalette.swift`, and every bundled typeface is reached through
`Sources/Uttrflow/Brand/BrandFont.swift`. The design generators in `Design/` draw from the same
palette, and `Docs/redesign-tokens.md` quotes it. This audit reads all four and fails on:

  colour-constructor   a Swift colour built from literal channels, a hex helper, a colour
                       literal or an asset-catalogue colour, outside BrandPalette.swift
  colour-hex           a 6- or 8-digit hex literal in presentation code outside BrandPalette.swift
  colour-named         a hued system or SwiftUI colour (`.systemRed`, `Color.orange`) in Swift
  font-custom          a custom font built outside BrandFont.swift
  font-family          a bundled family name spelled outside BrandFont.swift
  generator-hex        a hex in a Design/ generator that is no BrandPalette value
  generator-annotation a generator token that says it matches a BrandPalette role and does not
  docs-token           a value in Docs/redesign-tokens.md that disagrees with BrandPalette.Redesign
  allowlist            an ALLOWED entry that no longer matches anything (stale)
  structure            an expected source structure the audit can no longer find

Exceptions live only in ALLOWED and SCENERY below, each with its reason; there is no inline
suppression. Usage:

    python3 Scripts/design_source_audit.py              (part of `make design-audit`)
    python3 Scripts/design_source_audit.py --self-test  proves each rule passes and fails
"""

import argparse
import re
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PALETTE = Path("Sources/Uttrflow/Brand/BrandPalette.swift")
FONT = Path("Sources/Uttrflow/Brand/BrandFont.swift")
TOKENS_DOC = Path("Docs/redesign-tokens.md")
# The targets that draw: the hex rule is scoped to them so that hashes and masks elsewhere pass.
PRESENTATION = (Path("Sources/Uttrflow"), Path("Sources/UttrflowUX"))

# (path, rule, the matched text) -> why the platform or architecture needs it.
ALLOWED = {
    ("Sources/Uttrflow/MenuBar/MenuBarController.swift", "colour-named", "NSColor.systemGreen"):
        "the status item's clipboard badge sits in the system menu bar and uses the system's"
        " dynamic colours, which follow the bar's own appearance rather than the app's",
    ("Sources/Uttrflow/MenuBar/MenuBarController.swift", "colour-named", "NSColor.systemGray"):
        "the status item's clipboard badge, off state; as above",
    ("Sources/Uttrflow/MenuBar/MenuBarController.swift", "colour-named", "NSColor.systemBlue"):
        "the development build's menu-bar title, in the menu bar's dynamic system colour",
    ("Sources/Uttrflow/MenuBar/MenuBarController.swift", "colour-named", "NSColor.systemOrange"):
        "the menu-bar attention tint: the system orange survives the bar's dark contrast",
    ("Sources/Uttrflow/Suggestion/SuggestionPanelController.swift", "font-custom", "NSFont(name:"):
        "the ghost line mirrors the focused field's own face, read from the host app",
    ("Sources/Uttrflow/Suggestion/SuggestionView.swift", "font-custom", ".custom("):
        "the ghost line mirrors the focused field's own face, read from the host app",
    ("Sources/UttrflowContext/FocusedFieldReader+TypeStyle.swift", "font-custom", "CTFontCreateWithName("):
        "reads the host field's font traits; it draws nothing",
}

SCENERY_REASON = "the desktop or stage the artboard sits on; production draws no such surface"
CHROME_REASON = "another app's window or the macOS window controls, drawn as context"
MARK_REASON = "another product's own mark, drawn as the provider it names"
MATH_REASON = "a contrast calculation or a comment, never drawn"
UNTIED_REASON = (
    "a canvas colour with no BrandPalette role yet; to retire it, tie it to a role"
    " (or add the role in Swift first) and delete the entry"
)


def _entries(path, reason, *hexes):
    return {(path, h): reason for h in hexes}


# (generator, hex) -> reason. A hex here is not a BrandPalette value on purpose.
SCENERY = {
    **_entries("Design/_gen_common.py", MATH_REASON, "1E1E1E"),
    **_entries("Design/_gen_common.py", SCENERY_REASON, "E8E8ED", "F2F1F6", "DFDEE6", "CFCEDA"),
    **_entries("Design/_gen_common.py", CHROME_REASON, "FF5F57", "FEBC2E", "28C840"),
    **_entries("Design/_gen_dock.py", SCENERY_REASON, "6E97A8", "466673", "2B4049"),
    **_entries("Design/_gen_dock.py", UNTIED_REASON, "04100F"),
    **_entries("Design/_gen_errors.py", SCENERY_REASON, "EFEFF3", "F4F4F8", "E9E9EF"),
    **_entries("Design/_gen_errors.py", UNTIED_REASON, "8E8E93"),
    **_entries(
        "Design/_gen_identity.py", SCENERY_REASON, "EFEFF3", "F5F4F8", "E9E8EE", "4A6773", "2B4049"),
    **_entries("Design/_gen_identity.py", UNTIED_REASON, "1B2024", "0A0D0F", "0B1F1D", "1D1D1F"),
    **_entries("Design/_gen_menubar.py", SCENERY_REASON, "6E909E", "446370", "273840"),
    **_entries("Design/_gen_menubar.py", UNTIED_REASON, "793F15", "0F5751"),
    **_entries("Design/_gen_onboarding.py", MATH_REASON, "1E1E1E"),
    **_entries(
        "Design/_gen_onboarding.py", UNTIED_REASON,
        "F4F4F7", "E7E7EC", "F5FAF9", "4BD46B", "2FB84E", "3A3A3D", "2C2C2E"),
    **_entries(
        "Design/_gen_placement.py", SCENERY_REASON,
        "EFEFF3", "F4F4F8", "E8E8EE", "6E97A8", "466673", "2B4049"),
    **_entries(
        "Design/_gen_predict.py", CHROME_REASON, "1D1D1F", "1C1C1E", "E8E8ED", "2C2C2E", "F5F5F7"),
    **_entries("Design/_gen_predict.py", MATH_REASON, "1E1E1E", "F6F6F8", "2C2C2F"),
    **_entries("Design/_gen_predict.py", UNTIED_REASON, "262628"),
    **_entries("Design/_gen_settings.py", UNTIED_REASON, "5B8090", "334B55"),
    **_entries("Design/_gen_shell.py", SCENERY_REASON, "1B1B21", "3E3E4A", "26262F", "16161B"),
    **_entries("Design/_gen_shell.py", UNTIED_REASON, "A85300", "FFB067", "1E7B36", "5EDC80"),
    **_entries("Design/_gen_shell.py", CHROME_REASON, "4A154B", "0F6CBD", "1D6F42", "D93025"),
    **_entries("Design/_gen_shell.py", MARK_REASON, "4285F4", "34A853", "FBBC05", "EA4335"),
}

COLOUR_TYPE = r"(?<![\w.])(?:SwiftUI\.)?(?:Color|NSColor|CGColor|UIColor)"
CONSTRUCTOR = re.compile(COLOUR_TYPE + r"\s*\((?P<args>[^()]*(?:\([^()]*\)[^()]*)*)\)")
CHANNEL_LABEL = re.compile(
    r"\b(?:red|srgbRed|calibratedRed|deviceRed|displayP3Red|white|calibratedWhite|deviceWhite"
    r"|genericGrayGamma2_2Gray|hue|calibratedHue|deviceHue|saturation|brightness|hex|rgb)\s*:"
)
LITERAL = re.compile(r"-?(?:\d+(?:\.\d+)?|0x[0-9A-Fa-f_]+)")
OTHER_COLOUR = re.compile(
    r"#colorLiteral|(?<![\w.])(?:Color|NSColor)\s*\(\s*\"|NSColor\s*\(\s*named\s*:"
    r"|(?<![\w.])Color\s*\(\s*hex\s*:"
)
HEX_LITERAL = re.compile(r"(?<![\w])0x(?:[0-9A-Fa-f]_?){6}(?:[0-9A-Fa-f]{2})?(?![0-9A-Fa-f_])")
HUES = "Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Brown|Mint|Cyan|Gray"
NAMED = re.compile(
    rf"(?<![\w])NSColor\.system(?:{HUES})\b"
    rf"|(?<![\w])Color\.(?:{HUES.lower()})\b"
    rf"|\.(?:foregroundStyle|foregroundColor|fill|stroke|strokeBorder|background|tint|accentColor)"
    rf"\(\s*\.(?:{HUES.lower()})\b"
)
CUSTOM_FONT = re.compile(r"(?<![\w])(?:Font)?\.custom\(|NSFont\(name:|CTFontCreateWithName\(")
FAMILY_DECL = re.compile(r"static let \w*[Ff]amily\s*=\s*\"([^\"]+)\"")


def strip_comment(line):
    """Drops a `//` comment that is not inside a string literal."""
    in_string = False
    for index, char in enumerate(line):
        if char == '"':
            in_string = not in_string
        elif not in_string and line.startswith("//", index):
            return line[:index]
    return line


def swift_lines(root, directory):
    for path in sorted((root / directory).rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        for number, line in enumerate(path.read_text().splitlines(), 1):
            yield relative, number, strip_comment(line)


class Findings:
    def __init__(self):
        self.items = []
        self.used = set()

    def add(self, path, number, rule, text, message):
        key = (path, rule, text)
        if key in ALLOWED:
            self.used.add(key)
            return
        self.items.append(f"{path}:{number}: [{rule}] {message}")


# --- BrandPalette.swift ------------------------------------------------------------------------


def palette_declarations(text):
    """Every `static let` in BrandPalette.swift by dotted path from `BrandPalette`, with its expression."""
    declarations = {}
    stack = []
    depth = 0
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = strip_comment(lines[index])
        opened = re.match(r"\s*(?:enum|extension)\s+([\w.]+)\s*\{", line)
        if opened:
            names = opened.group(1).split(".")
            if names[0] == "BrandPalette":
                names = names[1:]
            stack.append((depth, names))
        declaration = re.match(r"\s*(?:private\s+)?static let (\w+)(?:\s*:\s*[\w\[\]]+)?\s*=\s*(.*)", line)
        if declaration:
            expression = declaration.group(2)
            balance = expression.count("(") - expression.count(")")
            while balance > 0 and index + 1 < len(lines):
                index += 1
                extra = strip_comment(lines[index]).strip()
                expression += " " + extra
                balance += extra.count("(") - extra.count(")")
            scope = [name for _, names in stack for name in names]
            declarations[".".join(scope + [declaration.group(1)])] = expression.strip()
        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][0]:
            stack.pop()
        index += 1
    return declarations


def _hex(value):
    return value.replace("0x", "").replace("_", "").upper()[-6:]


def _split_arguments(text):
    parts, depth, current = [], 0, ""
    for char in text:
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def resolve(declarations, expression, scope):
    """A palette expression as ('tone', dark, light) or ('layer', dark, light, dark_op, light_op)."""
    expression = expression.strip()
    if re.fullmatch(r"0x[0-9A-Fa-f_]+", expression):
        return ("tone", _hex(expression), _hex(expression))
    call = re.fullmatch(r"(BrandTone|BrandLayer)\((.*)\)", expression, re.S)
    if call:
        arguments = {}
        positional = []
        for part in _split_arguments(call.group(2)):
            labelled = re.match(r"(\w+)\s*:\s*(.*)", part, re.S)
            if labelled and not part.startswith("0x"):
                arguments[labelled.group(1)] = labelled.group(2)
            else:
                positional.append(part)
        if call.group(1) == "BrandTone":
            if positional:
                fixed = resolve(declarations, positional[0], scope)
                return fixed and ("tone", fixed[1], fixed[1])
            dark = resolve(declarations, arguments.get("dark", ""), scope)
            light = resolve(declarations, arguments.get("light", ""), scope)
            return dark and light and ("tone", dark[1], light[2])
        tone = resolve(declarations, arguments.get("tone", ""), scope)
        if not tone:
            return None
        return ("layer", tone[1], tone[2], float(arguments["darkOpacity"]), float(arguments["lightOpacity"]))
    name = re.sub(r"^(?:BrandPalette\.|R\.)", "", expression)
    if expression.startswith("R."):
        name = "Redesign." + name
    if not re.fullmatch(r"[\w.]+", name):
        return None
    candidates = [".".join(scope[:cut] + [name]) for cut in range(len(scope), -1, -1)]
    for candidate in candidates:
        if candidate in declarations:
            return resolve(declarations, declarations[candidate], candidate.split(".")[:-1])
    return None


def resolve_path(declarations, path):
    if path not in declarations:
        return None
    return resolve(declarations, declarations[path], path.split(".")[:-1])


def palette_hexes(text):
    return {_hex(match) for match in re.findall(r"0x[0-9A-Fa-f_]{6,9}", text)}


# --- the checks --------------------------------------------------------------------------------


def check_swift(root, findings):
    palette_path = PALETTE.as_posix()
    font_path = FONT.as_posix()
    font_text = (root / FONT).read_text() if (root / FONT).is_file() else ""
    families = FAMILY_DECL.findall(font_text)
    if not families:
        findings.items.append(
            f"{font_path}: [structure] no `static let …family = \"…\"` found; BrandFont moved or"
            " was renamed, so the font rules cannot run. Update this audit with it.")
    for path, number, line in swift_lines(root, Path("Sources")):
        if path == palette_path:
            continue
        for match in CONSTRUCTOR.finditer(line):
            arguments = match.group("args")
            values = [part.split(":", 1)[-1].strip() for part in _split_arguments(arguments)]
            if CHANNEL_LABEL.search(arguments) and any(LITERAL.fullmatch(v) for v in values):
                findings.add(path, number, "colour-constructor", match.group(0),
                             f"`{match.group(0).strip()}` builds a colour from literal values;"
                             " add the role to BrandPalette.swift and read it from there")
        for match in OTHER_COLOUR.finditer(line):
            findings.add(path, number, "colour-constructor", match.group(0),
                         f"`{match.group(0)}` defines a colour outside BrandPalette.swift")
        if any(path.startswith(p.as_posix() + "/") for p in PRESENTATION):
            for match in HEX_LITERAL.finditer(line):
                findings.add(path, number, "colour-hex", match.group(0),
                             f"`{match.group(0)}` is a colour-shaped hex outside BrandPalette.swift")
        for match in NAMED.finditer(line):
            text = match.group(0)
            findings.add(path, number, "colour-named", text,
                         f"`{text}` is a hued system colour; use the BrandPalette role for it")
        if path != font_path:
            for match in CUSTOM_FONT.finditer(line):
                findings.add(path, number, "font-custom", match.group(0),
                             f"`{match.group(0)}` builds a custom font outside BrandFont.swift")
            for family in families:
                if f'"{family}"' in line:
                    findings.add(path, number, "font-family", family,
                                 f"\"{family}\" is a BrandFont family; reach it through BrandFont")


def check_generators(root, findings, palette_text, declarations):
    known = palette_hexes(palette_text)
    used = set()
    generators = sorted((root / "Design").glob("_gen_*.py"))
    if not generators:
        findings.items.append("Design: [structure] no _gen_*.py generators found")
    for generator in generators:
        relative = generator.relative_to(root).as_posix()
        lines = generator.read_text().splitlines()
        for number, line in enumerate(lines, 1):
            for match in re.finditer(r"(?<![&\w])#([0-9A-Fa-f]{6})\b", line):
                value = match.group(1).upper()
                if value in known:
                    continue
                if (relative, value) in SCENERY:
                    used.add((relative, value))
                    continue
                findings.items.append(
                    f"{relative}:{number}: [generator-hex] #{value} is no BrandPalette value; draw"
                    " the palette role production draws, or add the role in Swift first")
            note = re.search(r"[Mm]atches BrandPalette\.([\w.]+)\.(light|dark)", line)
            if note and number < len(lines):
                token = re.search(r"--[\w-]+:\s*#([0-9A-Fa-f]{6});", lines[number])
                resolved = resolve_path(declarations, note.group(1))
                if not token or not resolved:
                    findings.items.append(
                        f"{relative}:{number}: [generator-annotation] BrandPalette.{note.group(1)}"
                        " cannot be resolved, or no `--token: #hex;` follows the note")
                    continue
                expected = resolved[1] if note.group(2) == "dark" else resolved[2]
                if token.group(1).upper() != expected:
                    findings.items.append(
                        f"{relative}:{number + 1}: [generator-annotation] says BrandPalette."
                        f"{note.group(1)}.{note.group(2)} (#{expected}), draws #{token.group(1).upper()}")
    for key in sorted(set(SCENERY) - used):
        findings.items.append(f"{key[0]}: [allowlist] SCENERY entry #{key[1]} matches nothing; delete it")


CELL = re.compile(r"^`?(#[0-9A-Fa-f]{6}|white|black)`?(?:\s+at\s+([\d.]+)%)?$")


def _cell(text):
    text = text.strip()
    match = CELL.match(text)
    if not match:
        return None
    colour = {"white": "FFFFFF", "black": "000000"}.get(match.group(1), match.group(1)[1:].upper())
    opacity = float(match.group(2)) / 100 if match.group(2) else 1.0
    return colour, opacity


def check_tokens_doc(root, findings, declarations):
    path = root / TOKENS_DOC
    if not path.is_file():
        findings.items.append(f"{TOKENS_DOC}: [structure] missing")
        return
    checked = 0
    for number, line in enumerate(path.read_text().splitlines(), 1):
        row = re.match(r"\|\s*`(\w+)`\s*\|([^|]*)\|([^|]*)\|", line)
        if not row:
            continue
        name = row.group(1)
        candidates = [k for k in declarations if k.startswith("Redesign.") and k.split(".")[-1] == name]
        if not candidates:
            findings.items.append(
                f"{TOKENS_DOC}:{number}: [docs-token] `{name}` is not a BrandPalette.Redesign token")
            continue
        resolved = resolve_path(declarations, sorted(candidates, key=len)[0])
        if not resolved:
            continue
        dark_text, light_text = row.group(2), row.group(3)
        if light_text.strip().startswith("same"):
            light_text = dark_text
        for theme, text, slot in (("dark", dark_text, 1), ("light", light_text, 2)):
            cell = _cell(text)
            if not cell:
                continue
            colour, opacity = cell
            actual_opacity = 1.0
            if resolved[0] == "layer":
                actual_opacity = resolved[3] if theme == "dark" else resolved[4]
            checked += 1
            if colour != resolved[slot] or abs(opacity - actual_opacity) > 0.0005:
                findings.items.append(
                    f"{TOKENS_DOC}:{number}: [docs-token] `{name}` {theme} says #{colour} at"
                    f" {opacity:.3f}; BrandPalette has #{resolved[slot]} at {actual_opacity:.3f}")
    if checked == 0:
        findings.items.append(f"{TOKENS_DOC}: [structure] no token cell could be checked")


def audit(root):
    findings = Findings()
    palette_file = root / PALETTE
    if not palette_file.is_file():
        return [f"{PALETTE}: [structure] missing; the colour rules cannot run"]
    palette_text = palette_file.read_text()
    declarations = palette_declarations(palette_text)
    if not resolve_path(declarations, "Redesign.pageGround") and root == REPO_ROOT:
        findings.items.append(f"{PALETTE}: [structure] Redesign.pageGround no longer resolves")
    check_swift(root, findings)
    check_generators(root, findings, palette_text, declarations)
    if (root / TOKENS_DOC).is_file() or root == REPO_ROOT:
        check_tokens_doc(root, findings, declarations)
    for key in sorted(set(ALLOWED) - findings.used):
        if (root / key[0]).is_file() or root == REPO_ROOT:
            findings.items.append(f"{key[0]}: [allowlist] ALLOWED entry {key[1]} `{key[2]}` matches nothing; delete it")
    return findings.items


# --- self-test ---------------------------------------------------------------------------------

FIXTURE_PALETTE = """\
enum BrandPalette {
    enum Teal {
        static let primary: UInt32 = 0x29_C0B4
        static let ink = BrandTone(dark: primary, light: 0x0E_6B64)
    }
    enum Redesign {
        static let pageGround = BrandTone(dark: 0x0B_0C10, light: 0xF2_F1EC)
        static let film = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.08, lightOpacity: 1)
    }
}
"""
FIXTURE_FONT = 'enum BrandFont {\n    static let family = "Outfit"\n}\n'
FIXTURE_DOC = "| `pageGround` | `#0B0C10` | `#F2F1EC` |\n| `film` | white at 8% | `#FFFFFF` |\n"
FIXTURE_GENERATOR = "TOKENS = '''\n  /* Matches BrandPalette.Teal.ink.light. */\n  --ink: #0E6B64;\n'''\n"


def _tree(scratch, view="", generator=FIXTURE_GENERATOR, doc=FIXTURE_DOC, font=FIXTURE_FONT):
    root = Path(scratch)
    files = {
        PALETTE: FIXTURE_PALETTE,
        FONT: font,
        Path("Sources/Uttrflow/Main/View.swift"): view,
        Path("Design/_gen_page.py"): generator,
        TOKENS_DOC: doc,
    }
    for path, text in files.items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_text(text)
    return root


def _rules(items):
    return sorted({re.search(r"\[([\w-]+)\]", item).group(1) for item in items})


def self_test():
    global SCENERY
    saved = SCENERY
    SCENERY = {}
    cases = [
        ("a view drawing palette roles passes",
         dict(view="let a = Color(rgb: BrandPalette.Teal.primary)\n.foregroundStyle(.white)\n"), []),
        ("a computed colour passes",
         dict(view="Color(.sRGB, red: c.red, green: c.green, blue: c.blue)\n"), []),
        ("a comment naming a colour passes", dict(view="// Color(red: 1, green: 0, blue: 0)\n"), []),
        ("literal channels fail", dict(view="Color(red: 1, green: 0.5, blue: 0)\n"), ["colour-constructor"]),
        ("a hue literal fails", dict(view="Color(hue: h, saturation: 0.5, brightness: 0.6)\n"),
         ["colour-constructor"]),
        ("an asset colour fails", dict(view='Color("Accent")\n'), ["colour-constructor"]),
        ("a hex in a view fails", dict(view="let tint: UInt32 = 0x12_8077\n"), ["colour-hex"]),
        ("a short hex in a view passes", dict(view="let mask = 0x7F\n"), []),
        ("a hued system colour fails", dict(view="NSColor.systemRed.setFill()\n"), ["colour-named"]),
        ("a hued shorthand fails", dict(view=".foregroundStyle(.orange)\n"), ["colour-named"]),
        ("a custom font fails", dict(view='Font.custom(name, size: 12)\n'), ["font-custom"]),
        ("a brand family literal fails", dict(view='let f = "Outfit"\n'), ["font-family"]),
        ("BrandFont without a family fails safe", dict(font="enum BrandFont {}\n"), ["structure"]),
        ("a generator hex off the palette fails",
         dict(generator=FIXTURE_GENERATOR + "X = '#123456'\n"), ["generator-hex"]),
        ("an HTML entity in a generator passes",
         dict(generator=FIXTURE_GENERATOR + "X = '&#128279;'\n"), []),
        ("a generator token drifting from its role fails",
         dict(generator=FIXTURE_GENERATOR.replace("#0E6B64", "#29C0B4")), ["generator-annotation"]),
        ("a docs value drifting from the palette fails",
         dict(doc=FIXTURE_DOC.replace("#F2F1EC", "#F2F1ED")), ["docs-token"]),
        ("a docs opacity drifting from the palette fails",
         dict(doc=FIXTURE_DOC.replace("8%", "9%")), ["docs-token"]),
        ("a docs token that does not exist fails",
         dict(doc=FIXTURE_DOC + "| `gone` | `#000000` | same |\n"), ["docs-token"]),
        ("a docs table with nothing checkable fails safe", dict(doc="no table\n"), ["structure"]),
    ]
    failed = 0
    try:
        for name, kwargs, expected in cases:
            with tempfile.TemporaryDirectory() as scratch:
                got = _rules(audit(_tree(scratch, **kwargs)))
            ok = got == expected
            failed += not ok
            print(f"  {'✓' if ok else '✗'} {name}" + ("" if ok else f": expected {expected}, got {got}"))

        allowed_key = ("Sources/Uttrflow/Main/View.swift", "colour-named", "NSColor.systemPink")
        ALLOWED[allowed_key] = "self-test"
        try:
            with tempfile.TemporaryDirectory() as scratch:
                passed = _rules(audit(_tree(scratch, view="NSColor.systemPink.set()\n"))) == []
            with tempfile.TemporaryDirectory() as scratch:
                stale = _rules(audit(_tree(scratch, view="\n"))) == ["allowlist"]
        finally:
            del ALLOWED[allowed_key]
        for ok, name in ((passed, "an allowed exception passes"), (stale, "a stale exception fails")):
            failed += not ok
            print(f"  {'✓' if ok else '✗'} {name}")

        SCENERY = {("Design/_gen_page.py", "ABCDEF"): "self-test"}
        with tempfile.TemporaryDirectory() as scratch:
            ok = _rules(audit(_tree(scratch))) == ["allowlist"]
        failed += not ok
        print(f"  {'✓' if ok else '✗'} a stale SCENERY entry fails")
        with tempfile.TemporaryDirectory() as scratch:
            ok = _rules(audit(Path(scratch))) == ["structure"]
        failed += not ok
        print(f"  {'✓' if ok else '✗'} a missing BrandPalette.swift fails safe")
    finally:
        SCENERY = saved
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        print("design_source_audit self-test")
        if not self_test():
            print("design_source_audit: self-test FAILED; fix the audit, not the source", file=sys.stderr)
            return 1
        print("design_source_audit: self-test passed")
        return 0
    items = audit(REPO_ROOT)
    if items:
        print(f"design_source_audit: FAILED ({len(items)})", file=sys.stderr)
        for item in items:
            print(f"  {item}", file=sys.stderr)
        print("  The rules and their homes are in Docs/agents/design.md.", file=sys.stderr)
        return 1
    untied = sum(1 for reason in SCENERY.values() if reason == UNTIED_REASON)
    print(
        f"design_source_audit: colours and typefaces stay in their homes; {len(ALLOWED)} allowed"
        f" exceptions, {len(SCENERY)} canvas-only generator colours ({untied} untied to a role)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Fails when the design shell's chrome drifts from `MainWindowStrip` / `OrbitPageHeader`.

#1138 found `Design/_gen_shell.py`'s shared main-window shell still drawing the retired
44px `<div class="toolbar"><h2>` band — a title plus optional controls — instead of the
two pieces that ship: `MainWindowStrip`, the top band with the sidebar toggle and account
chip (`Sources/Uttrflow/Main/MainWindowView.swift:142-170`), and `OrbitPageHeader`, the
112-point header with kicker, title, purpose caption and ordered scope/search/add controls
(`Sources/Uttrflow/Main/MainWindowView.swift:174-217`). All 28 `Main-*.dc.html` artboards
inherited that toolbar, and none carried a page's `MainPageChrome.caption`.

This reads each page's caption straight out of its own presenter source and fails unless
`Design/_gen_shell.py`, `Design/_gen_main.py` and `Design/_gen_app.py` spell it verbatim
somewhere in the generator set, and fails outright if the shell still draws the retired
`<div class="toolbar"><h2>` band, or if it has lost the `.strip` (sidebar toggle + account
chip) or `.header` (kicker/title/caption, then scope/search/add) structure — so neither the
obsolete shell nor a missing caption can silently return.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
SHELL_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_shell.py")
GENERATOR_SOURCES = [
    SHELL_SOURCE,
    os.path.join(REPO_ROOT, "Design", "_gen_main.py"),
    os.path.join(REPO_ROOT, "Design", "_gen_app.py"),
]

# Pages whose caption sits inline in a `MainPageChrome(title: "X", caption: "...")` call.
INLINE_CAPTION_PAGES = [
    ("Dictation", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "MainDictationPresentation.swift")),
    ("Dictionary", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "DictionaryPresentation.swift")),
    ("Corrections", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "CorrectionsPresentation.swift")),
    ("Insights", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "InsightsPresentation.swift")),
    ("Snippets", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "SnippetsPresentation.swift")),
    ("Style", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "StylePagePresentation.swift")),
    ("Account", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "AccountPagePresentation.swift")),
]

# Pages whose chrome caption is a named `static let caption` the window controller reads,
# rather than spelled inline at the call site (`Sources/Uttrflow/Main/MainWindowController.swift`).
REFERENCED_CAPTION_PAGES = [
    ("History", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "HistoryPresentation.swift")),
    ("Diagnostics", os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "DiagnosticsPresentation.swift")),
]

INLINE_CAPTION = r'title:\s*"{page}",\s*caption:\s*"(?P<c>[^"]+)"'
REFERENCED_CAPTION = r'static let caption\s*=\s*"(?P<c>[^"]+)"'


def load_inline_caption(page, path):
    if not os.path.isfile(path):
        raise SystemExit(f"chrome contract audit: {path} not found")
    text = open(path).read()
    match = re.search(INLINE_CAPTION.format(page=re.escape(page)), text)
    if not match:
        raise SystemExit(
            f"chrome contract audit: no {page!r} caption declaration found in {path}"
        )
    return match.group("c")


def load_referenced_caption(path):
    if not os.path.isfile(path):
        raise SystemExit(f"chrome contract audit: {path} not found")
    text = open(path).read()
    match = re.search(REFERENCED_CAPTION, text)
    if not match:
        raise SystemExit(f"chrome contract audit: no caption declaration found in {path}")
    return match.group("c")


def load_page_captions():
    """Returns {page title: caption}, read straight out of each page's own presenter."""
    captions = {}
    for page, path in INLINE_CAPTION_PAGES:
        captions[page] = load_inline_caption(page, path)
    for page, path in REFERENCED_CAPTION_PAGES:
        captions[page] = load_referenced_caption(path)
    return captions


def load_generator_text():
    for path in GENERATOR_SOURCES:
        if not os.path.isfile(path):
            raise SystemExit(f"chrome contract audit: {path} not found")
    return "\n".join(open(path).read() for path in GENERATOR_SOURCES)


def audit_failures(shell_text, generator_text, captions):
    failures = []

    if 'class="toolbar"' in shell_text or "<h2>" in shell_text:
        failures.append(
            'the shell still draws the retired <div class="toolbar"><h2> band instead of '
            "MainWindowStrip and OrbitPageHeader"
        )

    if 'class="strip"' not in shell_text:
        failures.append("the shell has no MainWindowStrip (a .strip element)")

    if 'class="achip"' not in shell_text:
        failures.append("MainWindowStrip has no account chip (a .achip element)")

    if 'class="stoggle"' not in shell_text:
        failures.append("MainWindowStrip has no sidebar toggle (a .stoggle element)")

    if 'class="header"' not in shell_text:
        failures.append("the shell has no OrbitPageHeader (a .header element)")

    if 'class="hkicker"' not in shell_text or 'class="htitle"' not in shell_text:
        failures.append("OrbitPageHeader is missing its kicker or its title")

    # Production draws scope, then search, then the add action, in that fixed order
    # (`Sources/Uttrflow/Main/MainWindowView.swift`'s `OrbitPageHeader.body`).
    if not re.search(r"\{scope\}\{search\}\{add\}", shell_text):
        failures.append(
            "the shell's header does not place scope, search and add controls in that "
            "fixed production order"
        )

    for page, caption in captions.items():
        if caption not in generator_text:
            failures.append(
                f"the generator set never spells {page}'s MainPageChrome caption verbatim "
                f"({caption!r})"
            )

    return failures


def audit_pairs():
    shell_text = open(SHELL_SOURCE).read() if os.path.isfile(SHELL_SOURCE) else ""
    if not shell_text:
        raise SystemExit(f"chrome contract audit: {SHELL_SOURCE} not found")
    generator_text = load_generator_text()
    captions = load_page_captions()
    return audit_failures(shell_text, generator_text, captions)


def self_test():
    """Proves the extractors resolve a known-good fixture and the regressions they catch."""
    ok = True

    inline_fixture = (
        '            chrome: MainPageChrome(\n'
        '                title: "Dictation",\n'
        '                caption: "Everything you said today, and what Uttrflow did with it.",\n'
    )
    match = re.search(INLINE_CAPTION.format(page="Dictation"), inline_fixture)
    if not match or match.group("c") != "Everything you said today, and what Uttrflow did with it.":
        print("  ✗ self-test: inline caption extraction failed", file=sys.stderr)
        ok = False

    referenced_fixture = '    public static let caption = "Every dictation, kept on this Mac."\n'
    match = re.search(REFERENCED_CAPTION, referenced_fixture)
    if not match or match.group("c") != "Every dictation, kept on this Mac.":
        print("  ✗ self-test: referenced caption extraction failed", file=sys.stderr)
        ok = False

    captions = {"Dictation": "A caption."}
    good_shell = (
        'def app_window(...):\n'
        '    return f"""<div class="strip"><div class="stoggle"></div>'
        '<div class="achip"></div></div>\n'
        '        <div class="header"><div class="hkicker">X</div><div class="htitle">X</div>\n'
        '        <div class="tools">{scope}{search}{add}</div></div>"""\n'
    )
    good_generators = good_shell + "A caption."
    if audit_failures(good_shell, good_generators, captions):
        print("  ✗ self-test: a known-good fixture was flagged", file=sys.stderr)
        ok = False

    restored_toolbar = good_shell + '<div class="toolbar"><h2>Dictation</h2></div>'
    if not audit_failures(restored_toolbar, good_generators, captions):
        print('  ✗ self-test: a restored <div class="toolbar"><h2> band was not flagged',
              file=sys.stderr)
        ok = False

    no_strip = good_shell.replace('class="strip"', "class=\"notstrip\"")
    if not audit_failures(no_strip, good_generators, captions):
        print("  ✗ self-test: a missing .strip was not flagged", file=sys.stderr)
        ok = False

    no_chip = good_shell.replace('class="achip"', 'class="notchip"')
    if not audit_failures(no_chip, good_generators, captions):
        print("  ✗ self-test: a missing account chip was not flagged", file=sys.stderr)
        ok = False

    reordered = good_shell.replace("{scope}{search}{add}", "{search}{scope}{add}")
    if not audit_failures(reordered, good_generators, captions):
        print("  ✗ self-test: a reordered scope/search/add was not flagged", file=sys.stderr)
        ok = False

    missing_caption = {"Dictation": "A caption that is not in the generator set."}
    if not audit_failures(good_shell, good_generators, missing_caption):
        print("  ✗ self-test: a missing caption was not flagged", file=sys.stderr)
        ok = False

    return ok


def audit():
    failures = audit_pairs()
    if failures:
        print(f"\n  ✗ {len(failures)} chrome artboard contract violation(s):", file=sys.stderr)
        for message in failures:
            print(f"    {message}", file=sys.stderr)
        print(
            "    Update Design/_gen_shell.py's MainWindowStrip/OrbitPageHeader (or the\n"
            "    caption in Design/_gen_main.py / Design/_gen_app.py) to match\n"
            "    Sources/Uttrflow/Main/MainWindowView.swift and each page's own presenter,\n"
            "    then regenerate every Main-*.dc.html artboard.",
            file=sys.stderr,
        )
        return 1

    print(
        "chrome contract audit: the shell's MainWindowStrip and OrbitPageHeader match "
        "production, with every page's caption spelled verbatim.\n"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the extractors resolve a known-good fixture and catch known regressions",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\nchrome contract audit: self-test failed; the parser is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Fails when the design shell's sidebar drifts from `SidebarPresenter.order`.

#1133 found `Design/_gen_shell.py`'s shared sidebar still drawing ten rows starting with
Dictation and carrying no Home row, plus a "Most recent" transcript card and a "Hold
anywhere" shortcut footer that `SidebarView` draws neither of. All 28 `Main-*.dc.html`
artboards inherit that shell, so nothing about the design set represented the navigation
that ships.

This reads `SidebarPresenter.order`'s destination titles straight out of
`SidebarPresentation.swift` and fails unless `Design/_gen_shell.py`'s `NAV` list spells the
same titles in the same order, or if the shell still draws a "Most recent" card or a "Hold
anywhere" footer — so neither the order nor the two retired pieces can silently return.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
PRESENTER_SOURCE = os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "SidebarPresentation.swift")
GENERATOR_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_shell.py")

# `.page(.home)` -> "home"; `.settings(.general)` -> "settings". Order matches ``ORDER_DECL``.
ORDER_DECL = re.compile(r"static let order: \[SidebarDestination\] = \[(?P<body>.*?)\]\s*\n", re.S)
DESTINATION = re.compile(r"\.(page|settings)\(\.(?P<case>\w+)\)")

# Every title `SidebarPresenter.title(for:)` returns, keyed the same way as ``DESTINATION``.
TITLES = {
    "home": "Home", "dictation": "Dictation", "history": "History", "dictionary": "Dictionary",
    "corrections": "Corrections", "insights": "Insights", "snippets": "Snippets",
    "style": "Style", "diagnostics": "Diagnostics", "account": "Account",
    "general": "Settings",
}

NAV_DECL = re.compile(r"NAV = \[(?P<body>.*?)\]\s*\n", re.S)
NAV_ROW = re.compile(r'\("(?P<title>[^"]+)"')


def load_presenter_order(path):
    """Returns the sidebar's titles, in `SidebarPresenter.order`'s order."""
    text = open(path).read()
    match = ORDER_DECL.search(text)
    if not match:
        raise SystemExit(f"sidebar contract audit: no `order` declaration found in {path}")
    titles = []
    for destination in DESTINATION.finditer(match.group("body")):
        case = destination.group("case")
        if case not in TITLES:
            raise SystemExit(
                f"sidebar contract audit: {path} names a destination ({case!r}) this audit "
                "does not know a title for; add it to TITLES"
            )
        titles.append(TITLES[case])
    return titles


def load_generator_nav(path):
    """Returns the design shell's row titles, in `NAV`'s order."""
    text = open(path).read()
    match = NAV_DECL.search(text)
    if not match:
        raise SystemExit(f"sidebar contract audit: no `NAV` declaration found in {path}")
    return [row.group("title") for row in NAV_ROW.finditer(match.group("body"))]


def audit_failures(generator_text, presenter_order, generator_nav):
    failures = []

    if generator_nav != presenter_order:
        failures.append(
            "the generator's NAV order does not match SidebarPresenter.order: "
            f"generator has {generator_nav!r}, production has {presenter_order!r}"
        )

    if re.search(r"Most recent", generator_text):
        failures.append(
            'the generator still draws a "Most recent" transcript card, which SidebarView '
            "has none of"
        )

    if re.search(r"Hold anywhere", generator_text):
        failures.append(
            'the generator still draws a "Hold anywhere" shortcut footer, which SidebarView '
            "has none of"
        )

    return failures


def audit_pairs():
    if not os.path.isfile(PRESENTER_SOURCE):
        raise SystemExit(f"sidebar contract audit: {PRESENTER_SOURCE} not found")
    if not os.path.isfile(GENERATOR_SOURCE):
        raise SystemExit(f"sidebar contract audit: {GENERATOR_SOURCE} not found")

    presenter_order = load_presenter_order(PRESENTER_SOURCE)
    generator_nav = load_generator_nav(GENERATOR_SOURCE)
    generator_text = open(GENERATOR_SOURCE).read()
    return audit_failures(generator_text, presenter_order, generator_nav)


def self_test():
    """Proves the extractors resolve a known-good fixture and the regressions they catch."""
    ok = True

    presenter_fixture = (
        "    static let order: [SidebarDestination] = [\n"
        "        .page(.home), .page(.dictation), .settings(.general), .page(.account),\n"
        "    ]\n"
    )
    order_match = ORDER_DECL.search(presenter_fixture)
    if not order_match:
        print("  ✗ self-test: order extraction failed", file=sys.stderr)
        ok = False
    else:
        titles = [
            TITLES[d.group("case")] for d in DESTINATION.finditer(order_match.group("body"))
        ]
        if titles != ["Home", "Dictation", "Settings", "Account"]:
            print(f"  ✗ self-test: order resolved wrong ({titles!r})", file=sys.stderr)
            ok = False

    good_generator = (
        'NAV = [\n    ("Home", HOUSE), ("Dictation", MIC), ("Settings", GEAR),\n'
        '    ("Account", PERSON),\n]\n'
    )
    if audit_failures(good_generator, ["Home", "Dictation", "Settings", "Account"],
                       load_generator_nav_from_text(good_generator)):
        print("  ✗ self-test: a known-good fixture was flagged", file=sys.stderr)
        ok = False

    reordered = 'NAV = [\n    ("Dictation", MIC), ("Home", HOUSE),\n]\n'
    if not audit_failures(reordered, ["Home", "Dictation"],
                           load_generator_nav_from_text(reordered)):
        print("  ✗ self-test: a reordered NAV was not flagged", file=sys.stderr)
        ok = False

    missing_home = 'NAV = [\n    ("Dictation", MIC), ("Settings", GEAR),\n]\n'
    if not audit_failures(missing_home, ["Home", "Dictation", "Settings"],
                           load_generator_nav_from_text(missing_home)):
        print("  ✗ self-test: a missing Home row was not flagged", file=sys.stderr)
        ok = False

    restored_recent = (
        'NAV = [\n    ("Home", HOUSE),\n]\n'
        '<div class="recent"><p class="cap">Most recent</p></div>'
    )
    if not audit_failures(restored_recent, ["Home"],
                           load_generator_nav_from_text(restored_recent)):
        print('  ✗ self-test: a restored "Most recent" card was not flagged', file=sys.stderr)
        ok = False

    restored_footer = (
        'NAV = [\n    ("Home", HOUSE),\n]\n'
        '<div class="sidehint"><span>Hold anywhere</span></div>'
    )
    if not audit_failures(restored_footer, ["Home"],
                           load_generator_nav_from_text(restored_footer)):
        print('  ✗ self-test: a restored "Hold anywhere" footer was not flagged', file=sys.stderr)
        ok = False

    return ok


def load_generator_nav_from_text(text):
    """`load_generator_nav`, over a string rather than a file — for the self-test fixtures."""
    match = NAV_DECL.search(text)
    if not match:
        raise SystemExit("sidebar contract audit: self-test fixture has no `NAV` declaration")
    return [row.group("title") for row in NAV_ROW.finditer(match.group("body"))]


def audit():
    failures = audit_pairs()
    if failures:
        print(f"\n  ✗ {len(failures)} sidebar artboard contract violation(s):", file=sys.stderr)
        for message in failures:
            print(f"    {message}", file=sys.stderr)
        print(
            "    Update Design/_gen_shell.py's NAV to match\n"
            "    Sources/UttrflowUX/SidebarPresentation.swift's SidebarPresenter.order,\n"
            "    then regenerate every Main-*.dc.html artboard.",
            file=sys.stderr,
        )
        return 1

    print(
        "sidebar contract audit: the design shell's sidebar matches SidebarPresenter.order, "
        "with no recent-transcript card or shortcut footer.\n"
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
                "\nsidebar contract audit: self-test failed; the parser is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())

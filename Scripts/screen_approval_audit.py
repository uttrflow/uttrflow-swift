#!/usr/bin/env python3
"""Fails when the app shows a screen that has no approved page in `Design/released/`.

`Design/README.md` makes `Design/released/` the design source: a page there is a screen as it
ships, and a new screen reaches it through `Design/next/` before any Swift draws it. This audit
reads each screen list the Swift code declares and the same list in its released page, and fails
on:

  screen-unapproved  Swift shows a step, tab or page the released page does not have
  screen-missing     the released page has one Swift does not show
  screen-order       both have the same ones in a different order
  allowlist          an EXCEPTIONS entry that no longer matches a difference (stale)
  structure          a list the audit can no longer find, in Swift or in a released page

The lists:

  onboarding  `OnboardingStep` titles, by position       Design/released/onboarding.html steps
  settings    `SettingsTab` titles, in case order         Design/released/settings.html tabs
  sidebar     `SidebarPresenter.order` page rows          Design/released/sidebar.html rows
  pages       every `MainTab` title                       Design/released/sidebar.html pages

Exceptions live only in EXCEPTIONS below, each with its reason; there is no inline suppression.
Usage:

    python3 Scripts/screen_approval_audit.py              (part of `make design-audit`)
    python3 Scripts/screen_approval_audit.py --self-test  proves each rule passes and fails
"""

import argparse
import re
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
STEP = Path("Sources/UttrflowUX/OnboardingStep.swift")
SETTINGS_PRESENTER = Path("Sources/UttrflowUX/SettingsPresenter.swift")
LOCATION = Path("Sources/UttrflowUX/AppLocation.swift")
SIDEBAR = Path("Sources/UttrflowUX/SidebarPresentation.swift")
RELEASED = Path("Design/released")

# (list, rule, name) -> why the difference is allowed to stand.
EXCEPTIONS = {}


def _cases(text, enum):
    """The case names of a Swift enum, in declaration order."""
    body = re.search(r"enum " + enum + r"\b[^{]*\{(.*?)\n\}", text, re.S)
    if not body:
        return None
    return re.findall(r"^\s*case (\w+)\s*$", body.group(1), re.M)


def _switch(text, func):
    """`case .name: value` pairs from the switch inside a Swift function or property."""
    start = text.find(func)
    if start < 0:
        return None
    end = text.find("\n    }\n", start)
    return dict(re.findall(r'case \.(\w+): ("[^"]*"|\d+)', text[start:end]))


def _read(root, path):
    file = root / path
    return file.read_text() if file.exists() else None


def swift_lists(root):
    """Each screen list as the app declares it, or None for a list it can no longer find."""
    lists = {}
    step = _read(root, STEP)
    if step:
        titles = _switch(step, "var railTitle")
        positions = _switch(step, "var position")
        if titles and positions and titles.keys() == positions.keys():
            order = sorted(titles, key=lambda case: int(positions[case]))
            lists["onboarding"] = [titles[case].strip('"') for case in order]
    presenter, location = _read(root, SETTINGS_PRESENTER), _read(root, LOCATION)
    if presenter and location:
        titles, cases = _switch(presenter, "func title(of tab: SettingsTab)"), _cases(location, "SettingsTab")
        if titles and cases and all(case in titles for case in cases):
            lists["settings"] = [titles[case].strip('"') for case in cases]
    sidebar = _read(root, SIDEBAR)
    if sidebar and location:
        titles = _switch(sidebar, "func title(for destination: SidebarDestination)")
        order = re.search(r"static let order: \[SidebarDestination\] = \[(.*?)\]", sidebar, re.S)
        pages = _cases(location, "MainTab")
        if titles and order and pages and all(page in titles for page in pages):
            rows = re.findall(r"\.page\(\.(\w+)\)", order.group(1))
            lists["sidebar"] = [titles[row].strip('"') for row in rows if row in titles]
            lists["pages"] = sorted(titles[page].strip('"') for page in pages)
    return lists


def released_lists(root):
    """The same lists in the released pages."""
    lists = {}
    onboarding = _read(root, RELEASED / "onboarding.html")
    if onboarding:
        steps = re.findall(r"\{name:'([^']+)'", onboarding)
        if steps:
            lists["onboarding"] = steps
    settings = _read(root, RELEASED / "settings.html")
    if settings:
        tabs = re.search(r"const CATS\s*=\s*\[(.*?)\];", settings, re.S)
        if tabs:
            lists["settings"] = re.findall(r"\['([^']+)',\s*'[^']*'\]", tabs.group(1))
    sidebar = _read(root, RELEASED / "sidebar.html")
    if sidebar:
        names = re.search(r"T=\{([^}]*)\}", sidebar)
        groups = re.search(r"const GROUPS\s*=\s*\[(.*?)\];", sidebar, re.S)
        if names and groups:
            title = dict(re.findall(r"(\w+):'([^']+)'", names.group(1)))
            rows = re.findall(r"'(\w+)'", re.sub(r"'[A-Z][A-Z ]*'", "", groups.group(1)))
            if rows and all(row in title for row in rows):
                lists["sidebar"] = [title[row] for row in rows]
                lists["pages"] = sorted(title.values())
    return lists


def _compare(name, shipped, approved):
    items = []
    if name == "pages":
        # A page needs a released counterpart; the released set may hold pages not yet built.
        return [(name, "screen-unapproved", page) for page in shipped if page not in approved]
    for screen in shipped:
        if screen not in approved:
            items.append((name, "screen-unapproved", screen))
    for screen in approved:
        if screen not in shipped:
            items.append((name, "screen-missing", screen))
    if not items and shipped != approved:
        items.append((name, "screen-order", " → ".join(shipped)))
    return items


def audit(root):
    """Every difference, as `path: [rule] message` lines; an empty list is a pass."""
    shipped, approved = swift_lists(root), released_lists(root)
    found = []
    for name in ("onboarding", "settings", "sidebar", "pages"):
        if name not in shipped:
            found.append(f"{name}: [structure] the Swift list is gone or no longer parses")
            continue
        if name not in approved:
            found.append(f"{name}: [structure] the released page's list is gone or no longer parses")
            continue
        for key in _compare(name, shipped[name], approved[name]):
            if key in EXCEPTIONS:
                continue
            _, rule, screen = key
            where = "released page" if rule == "screen-missing" else "Swift"
            found.append(f"{name}: [{rule}] “{screen}” is only in the {where}")
    for key in EXCEPTIONS:
        name = key[0]
        if name in shipped and name in approved and key not in _compare(name, shipped[name], approved[name]):
            found.append(f"{name}: [allowlist] the exception for “{key[2]}” matches nothing")
    return found


# A minimal tree that agrees with itself; each self-test case bends one file.
FIXTURE = {
    STEP: """public enum OnboardingStep {
    public var position: Int {
        switch self {
        case .signIn: 1
        case .ready: 2
        }
    }

    public var railTitle: String {
        switch self {
        case .signIn: "Sign in"
        case .ready: "Ready"
        }
    }
""",
    LOCATION: """public enum SettingsTab {
    case general
    case privacy
}

public enum MainTab {
    case home
    case history
}
""",
    SETTINGS_PRESENTER: """    public static func title(of tab: SettingsTab) -> String {
        switch tab {
        case .general: "General"
        case .privacy: "Privacy"
        }
    }
""",
    SIDEBAR: """    public static let order: [SidebarDestination] = [
        .page(.home), .page(.history), .settings(.general),
    ]

    public static func title(for destination: SidebarDestination) -> String {
        switch destination {
        case .settings: "Settings"
        case .page(let page):
            switch page {
            case .home: "Home"
            case .history: "History"
            }
        }
    }
""",
    RELEASED / "onboarding.html": "const S=[\n  {name:'Sign in',ic:'mark'},\n  {name:'Ready',ic:'check'}];\n",
    RELEASED / "settings.html": "const CATS=[['General','gear'],['Privacy','shield']];\n",
    RELEASED / "sidebar.html": "T={home:'Home',hist:'History'};\nconst GROUPS=[[null,['home','hist']]];\n",
}


def _tree(scratch, **bends):
    root = Path(scratch)
    for path, text in FIXTURE.items():
        bend = bends.get(str(path), [])
        if bend == "delete":
            continue
        for old, new in bend:
            text = text.replace(old, new)
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_text(text)
    return root


def _rules(items):
    return sorted({re.search(r"\[([\w-]+)\]", item).group(1) for item in items})


def self_test():
    step, onboarding = str(STEP), str(RELEASED / "onboarding.html")
    settings, location = str(RELEASED / "settings.html"), str(LOCATION)
    cases = [
        ("a tree that matches its released pages passes", {}, []),
        ("a Swift step the released page lacks fails",
         {step: [('case .ready: 2', 'case .clipboard: 2\n        case .ready: 3'),
                 ('case .ready: "Ready"', 'case .clipboard: "Clipboard"\n        case .ready: "Ready"')]},
         ["screen-unapproved"]),
        ("a released step Swift lacks fails",
         {onboarding: [("{name:'Ready'", "{name:'Microphone',ic:'mic'},\n  {name:'Ready'")]}, ["screen-missing"]),
        ("steps in another order fail", {step: [("case .signIn: 1", "case .signIn: 3")]}, ["screen-order"]),
        ("a Settings tab the released page lacks fails",
         {location: [("    case privacy\n", "    case privacy\n    case updates\n")],
          str(SETTINGS_PRESENTER): [('case .privacy: "Privacy"', 'case .privacy: "Privacy"\n        case .updates: "Updates"')]},
         ["screen-unapproved"]),
        ("a page with no released row fails",
         {location: [("    case history\n", "    case history\n    case extra\n")],
          str(SIDEBAR): [('case .history: "History"', 'case .history: "History"\n            case .extra: "Extra"')]},
         ["screen-unapproved"]),
        ("a released settings list that no longer parses fails safe", {settings: [("const CATS", "const TABS")]},
         ["structure"]),
        ("a missing OnboardingStep.swift fails safe", {step: "delete"}, ["structure"]),
    ]
    failed = 0
    for name, bends, expected in cases:
        with tempfile.TemporaryDirectory() as scratch:
            got = _rules(audit(_tree(scratch, **bends)))
        ok = got == expected
        failed += not ok
        print(f"  {'✓' if ok else '✗'} {name}" + ("" if ok else f": expected {expected}, got {got}"))

    key = ("onboarding", "screen-unapproved", "Clipboard")
    EXCEPTIONS[key] = "self-test"
    try:
        bend = {step: cases[1][1][step]}
        with tempfile.TemporaryDirectory() as scratch:
            passed = _rules(audit(_tree(scratch, **bend))) == []
        with tempfile.TemporaryDirectory() as scratch:
            stale = _rules(audit(_tree(scratch))) == ["allowlist"]
    finally:
        del EXCEPTIONS[key]
    for ok, name in ((passed, "an allowed exception passes"), (stale, "a stale exception fails")):
        failed += not ok
        print(f"  {'✓' if ok else '✗'} {name}")
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    options = parser.parse_args()
    if options.self_test:
        print("screen_approval_audit self-test")
        if not self_test():
            print("screen_approval_audit: self-test FAILED; fix the audit, not the source", file=sys.stderr)
            return 1
        print("screen_approval_audit: self-test passed")
        return 0
    items = audit(REPO_ROOT)
    if items:
        print(f"screen_approval_audit: FAILED ({len(items)})", file=sys.stderr)
        for item in items:
            print(f"  {item}", file=sys.stderr)
        print("  A new screen is approved as a page in Design/next/ first; see Design/README.md.", file=sys.stderr)
        return 1
    print(f"screen_approval_audit: every listed screen has its released page; {len(EXCEPTIONS)} allowed exceptions")
    return 0


if __name__ == "__main__":
    sys.exit(main())

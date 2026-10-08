#!/usr/bin/env python3
"""Generates the per-control accessibility table in Docs/accessibility-controls.md from the view code.

Every control constructor under Sources/Uttrflow is one row: its screen, kind, where its accessible
name comes from, and its Full Keyboard Access and Voice Control status. The status is a pass or an
issue number recorded in Scripts/accessibility_controls_status.json once the control has been walked
by hand; a control nobody has walked yet reads "unchecked".

  python3 Scripts/accessibility_controls.py           rewrite the table
  python3 Scripts/accessibility_controls.py --check   exit 1 if the table is stale, a status is
                                                      malformed or names a control that is gone
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = "Sources/Uttrflow"
DOC = "Docs/accessibility-controls.md"
STATUS = "Scripts/accessibility_controls_status.json"
BEGIN = "<!-- accessibility-controls:begin -->"
END = "<!-- accessibility-controls:end -->"

KINDS = (
    "Button", "Toggle", "Picker", "TextField", "SecureField", "Slider", "Stepper", "Link", "Menu",
    "NSButton", "NSPopUpButton", "NSMenuItem", "NSSwitch",
)
CONTROL = re.compile(r"(?<![\w.])(" + "|".join(KINDS) + r")(?:\(| \{)")
LITERAL = re.compile(r'\s*"((?:[^"\\]|\\.)*)"')
NAMED_ARGUMENT = re.compile(r"\s*(action|role|selection|isOn|text|value|in|destination|systemSymbolName)\s*:")
LABEL_CLOSURE = re.compile(r"\blabel\s*:\s*\{|\}\s*label\s*:")
ACCESSIBILITY_LABEL = re.compile(r"\.accessibilityLabel\(|setAccessibilityLabel\(")
# Containers that give the field in their trailing closure their own label as its accessible name.
NAMING_CONTAINER = re.compile(r"(?<![\w.])PageEditorField\(")
LOOKBACK = 4
STATUS_VALUE = re.compile(r"^(pass|#[0-9]+)$")
LOOKAHEAD = 12

SCREENS = {
    "Dock": "Dock",
    "MenuBar": "Menu bar",
    "Main": "Main window",
    "Sidebar": "Main window",
    "Panel": "Panel",
    "Settings": "Settings",
    "Onboarding": "Onboarding",
}


def screen(path):
    parts = path.split("/")
    if len(parts) > 3:
        return SCREENS.get(parts[2], parts[2])
    return "App menu" if parts[-1] == "MainMenu.swift" else "App"


def name_source(lines, index, column):
    tail = lines[index][column:]
    literal = LITERAL.match(tail) if lines[index][column - 1] == "(" else None
    if literal and literal.group(1):
        return f'text "{literal.group(1)}"'
    following = lines[index + 1:index + LOOKAHEAD]
    stop = next((n for n, line in enumerate(following) if CONTROL.search(line)), len(following))
    window = "\n".join([tail, *following[:stop]])
    if ACCESSIBILITY_LABEL.search(window):
        return "accessibilityLabel"
    if LABEL_CLOSURE.search(window):
        return "label view"
    if literal or tail.strip() == "" or tail.lstrip().startswith(")") or NAMED_ARGUMENT.match(tail):
        return "container label" if inside_naming_container(lines, index) else "none found"
    return "expression"


def inside_naming_container(lines, index):
    """Whether the control is the first view in a naming container's trailing closure, opened just above it."""
    above = lines[max(0, index - LOOKBACK):index]
    starts = [n for n, line in enumerate(above) if NAMING_CONTAINER.search(line)]
    if not starts:
        return False
    between = above[starts[-1]:]
    return between[-1].rstrip().endswith("{") and not any(line.strip().startswith("}") for line in between)


def controls(root):
    found = []
    base = os.path.join(root, SOURCES)
    for directory, _, files in sorted(os.walk(base)):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            full = os.path.join(directory, name)
            path = os.path.relpath(full, root)
            with open(full, encoding="utf-8") as handle:
                lines = handle.read().split("\n")
            counts = {}
            for index, raw in enumerate(lines):
                line = "" if raw.lstrip().startswith(("//", "///", "*")) else raw
                for match in CONTROL.finditer(line):
                    kind = match.group(1)
                    counts[kind] = counts.get(kind, 0) + 1
                    found.append({
                        "key": f"{path}#{kind}#{counts[kind]}",
                        "path": path,
                        "line": index + 1,
                        "screen": screen(path),
                        "kind": kind,
                        "name": name_source(lines, index, match.end()),
                    })
    return found


def load_status(root):
    full = os.path.join(root, STATUS)
    if not os.path.exists(full):
        return {}
    with open(full, encoding="utf-8") as handle:
        return json.load(handle)


def problems(found, status):
    keys = {row["key"] for row in found}
    errors = [f"{key}: status names a control that no longer exists" for key in status if key not in keys]
    errors += [f"{key}: status {value!r} is not 'pass' or '#<issue>'" for key, value in status.items()
               if not STATUS_VALUE.match(value)]
    return errors


def table(found, status):
    rows = [
        "| Screen | Control | Kind | Accessible name from | Keyboard and Voice Control |",
        "|---|---|---|---|---|",
    ]
    for row in sorted(found, key=lambda r: (r["screen"], r["path"], r["line"])):
        name = row["name"].replace("|", "\\|")
        rows.append(
            f"| {row['screen']} | `{row['key']}` | {row['kind']} | {name} | {status.get(row['key'], 'unchecked')} |"
        )
    unnamed = sum(1 for row in found if row["name"] == "none found")
    walked = sum(1 for row in found if row["key"] in status)
    summary = f"{len(found)} controls; {walked} walked; {unnamed} with no accessible name found in the source."
    return "\n".join([summary, "", *rows])


def render(document, generated):
    start, finish = document.index(BEGIN) + len(BEGIN), document.index(END)
    return document[:start] + "\n" + generated + "\n" + document[finish:]


def main(argv, root=ROOT):
    found = controls(root)
    status = load_status(root)
    errors = problems(found, status)
    doc = os.path.join(root, DOC)
    with open(doc, encoding="utf-8") as handle:
        current = handle.read()
    wanted = render(current, table(found, status))
    if "--check" in argv:
        if wanted != current:
            errors.append(f"{DOC} is stale: run python3 Scripts/accessibility_controls.py")
        for error in errors:
            print(error, file=sys.stderr)
        return 1 if errors else 0
    for error in errors:
        print(error, file=sys.stderr)
    with open(doc, "w", encoding="utf-8") as handle:
        handle.write(wanted)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

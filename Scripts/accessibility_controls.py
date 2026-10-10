#!/usr/bin/env python3
"""Generates the per-control accessibility table in Docs/accessibility-controls.md from the view code.

Every control constructor under Sources/Uttrflow is one row: its screen, kind, where its accessible
name comes from, and its Full Keyboard Access and Voice Control status. The status is a pass or an
issue number recorded in Scripts/accessibility_controls_status.json once the control has been walked
by hand; a control nobody has walked yet reads "unchecked".

  python3 Scripts/accessibility_controls.py           rewrite the table
  python3 Scripts/accessibility_controls.py --check   exit 1 if the table is stale, a control has
                                                      no accessible name, or a status is malformed
                                                      or names a control that is gone
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
# A return type such as `-> NSMenuItem {` names a kind without building one.
CONTROL = re.compile(r"(?<![\w.])(?<!-> )(" + "|".join(KINDS) + r")(?:\(| \{)")
LITERAL = re.compile(r'\s*"((?:[^"\\]|\\.)*)"\s*(?:,|$)')
POSITIONAL = re.compile(r"\s*(?![A-Za-z_]\w*\s*:)\S")
TITLE_ARGUMENT = re.compile(r"(?:^|,)\s*title\s*:\s*(.+?)\s*(?:,|$)", re.S)
ACCESSIBILITY_LABEL = re.compile(r"\.accessibilityLabel\(|setAccessibilityLabel\(")
HIDDEN = re.compile(r"\.accessibilityHidden\(\s*true\s*\)")
ASSIGNED = re.compile(r"\b(?:let|var)\s+(\w+)\s*=\s*$")
VISIBLE_TEXT = re.compile(r"(?<![\w.])(?:Text|Label)\(")
# Containers that give the field in their trailing closure their own label as its accessible name.
NAMING_CONTAINER = re.compile(r"(?<![\w.])PageEditorField\(")
LOOKBACK = 4
STATUS_VALUE = re.compile(r"^(pass|#[0-9]+)$")

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


class Expression:
    """One control's constructor, read from source: its argument list, trailing closures and modifiers."""

    def __init__(self, text, start):
        self.text, self.at = text, start
        self.arguments = self.group("(", ")") if self.peek("(") else None
        self.closures = []
        while True:
            label = self.match(r"\s*(\w+)\s*:\s*(?=\{)") if self.closures else None
            if not self.peek("{", skip_lines=not self.closures):
                break
            self.closures.append((label, self.group("{", "}")))
        self.modifiers = []
        while self.peek(".", skip_lines=True):
            self.at += 1
            name = self.match(r"(\w+)") or ""
            body = self.group("(", ")") if self.peek("(") else ""
            while self.peek("{"):
                body += self.group("{", "}")
            self.modifiers.append(f".{name}({body})")

    def skip(self, skip_lines):
        while self.at < len(self.text):
            char = self.text[self.at]
            if self.text.startswith("//", self.at):
                end = self.text.find("\n", self.at)
                self.at = len(self.text) if end < 0 else end
            elif char in " \t" or (char == "\n" and skip_lines):
                self.at += 1
            else:
                return

    def peek(self, token, skip_lines=False):
        self.skip(skip_lines)
        return self.text.startswith(token, self.at)

    def match(self, pattern):
        found = re.compile(pattern).match(self.text, self.at)
        if not found:
            return None
        self.at = found.end()
        return found.group(1)

    def group(self, opening, closing):
        """The text between a bracket at the cursor and its partner, skipping strings and comments."""
        depth, start, quoted = 0, self.at + 1, False
        while self.at < len(self.text):
            char = self.text[self.at]
            if quoted:
                if char == "\\":
                    self.at += 1
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif self.text.startswith("//", self.at):
                end = self.text.find("\n", self.at)
                self.at = len(self.text) - 1 if end < 0 else end
            elif char in "({[":
                depth += 1
            elif char in ")}]":
                depth -= 1
                if depth == 0:
                    self.at += 1
                    return self.text[start:self.at - 1]
            self.at += 1
        return self.text[start:]


def name_source(lines, index, column, kind="Button"):
    """Where the control's accessible name comes from, read from the constructor and its modifier chain."""
    expression = Expression("\n".join([lines[index][column - 1:], *lines[index + 1:]]), 0)
    arguments = (expression.arguments or "").strip()
    literal = LITERAL.match(arguments)
    if literal and literal.group(1):
        return f'text "{literal.group(1)}"'
    modifiers = "".join(expression.modifiers)
    if HIDDEN.search(modifiers):
        return "hidden from accessibility"
    labels = [body for label, body in expression.closures if label == "label"]
    content = [body for label, body in expression.closures if label is None]
    named_by_content = kind != "Menu" and not labels
    if ACCESSIBILITY_LABEL.search("".join([modifiers, *labels, *(content if named_by_content else [])])):
        return "accessibilityLabel"
    if labels:
        return "label view"
    title = TITLE_ARGUMENT.search(arguments)
    if title:
        value = LITERAL.match(title.group(1))
        if not value:
            return "expression"
        if value.group(1):
            return f'text "{value.group(1)}"'
    elif arguments and not literal and POSITIONAL.match(arguments):
        return "expression"
    if named_by_content and any(VISIBLE_TEXT.search(body) for body in content):
        return "label view"
    if labelled_later(lines, index, column, kind):
        return "accessibilityLabel"
    return "container label" if inside_naming_container(lines, index) else "none found"


def labelled_later(lines, index, column, kind):
    """Whether a control held in a variable, the AppKit way, is given a label later in the same block."""
    held = ASSIGNED.search(lines[index][:column - len(kind) - 1])
    if not held:
        return False
    labelled = re.compile(r"\b" + re.escape(held.group(1)) + r"\.setAccessibilityLabel\(")
    depth = 0
    for line in lines[index:]:
        if labelled.search(line):
            return True
        depth += line.count("{") - line.count("}")
        if depth < 0:
            return False
    return False


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
                        "name": name_source(lines, index, match.end(), kind),
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
    errors += [f"{row['key']}: no accessible name found; name it with its visible text" for row in found
               if row["name"] == "none found"]
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

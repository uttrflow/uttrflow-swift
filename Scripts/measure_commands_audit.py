#!/usr/bin/env python3
"""Fails when Docs/measure-a-change.md names a command the tree does not have."""
import re
import sys
import tempfile
import unittest
from pathlib import Path

from perf_budget_audit import arguments, blanked, matching

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
PAGE = Path("Docs/measure-a-change.md")
TOOLS = ("uttrflow-eval", "uttrflow-dev", "uttrflow-bakeoff")


def code_spans(text):
    """Every inline code span and every line of every fenced block."""
    spans = []
    fenced = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            spans.append(line)
        else:
            spans.extend(re.findall(r"`([^`]+)`", line))
    return spans


def make_targets(root):
    makefile = (root / "Makefile").read_text(errors="ignore")
    return set(re.findall(r"^([A-Za-z0-9_-]+):", makefile, re.MULTILINE))


def kebab(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()


def command_declarations(root, tool):
    """Module-level command bodies, with comments and strings masked by the shared Swift reader."""
    found = []
    pattern = r"\bstruct\s+(\w+)\s*:[^{}]*\b(?:Async)?ParsableCommand\b[^{}]*\{"
    for source in sorted((root / "Sources" / tool).glob("*.swift")):
        text = source.read_text(encoding="utf-8")
        code = blanked(text)
        for match in re.finditer(pattern, code):
            if code[:match.start()].count("{") != code[:match.start()].count("}"):
                continue
            opening = match.end() - 1
            end = matching(code, opening)
            if end == len(code):
                raise ValueError(f"{tool}: command {match[1]} has an unclosed body")
            main = re.search(r"@main\s*$", code[:match.start()]) is not None
            found.append((match[1], text[opening + 1:end], code[opening + 1:end], main))
    return found


def own_configuration(declaration):
    """Only the selected type's own literal command configuration, never a nested type's."""
    _, text, code, _ = declaration
    headers = [match for match in re.finditer(r"\bstatic\s+(?:let|var)\s+configuration\b", code)
               if code[:match.start()].count("{") == code[:match.start()].count("}")]
    if not headers:
        return {}
    if len(headers) != 1:
        raise ValueError(f"{declaration[0]}: ambiguous command configuration")
    start = headers[0].end()
    constructor = re.match(r"\s*=\s*CommandConfiguration\s*\(", code[start:])
    if constructor is None:
        raise ValueError(f"{declaration[0]}: command configuration is not a literal initializer")
    opening = start + constructor.end() - 1
    if matching(code, opening) == len(code):
        raise ValueError(f"{declaration[0]}: unclosed command configuration")
    return configuration_fields(text, code, opening)


def configuration_fields(text, code, opening):
    """Keeps raw expressions at the offsets the shared argument reader found in masked Swift."""
    fields = {}
    cursor = opening + 1
    for label, expression in arguments(code, opening):
        if label is None and expression == "":
            continue
        if label is None or label in fields:
            raise ValueError("command configuration has an unlabelled or repeated argument")
        name = re.search(rf"\b{re.escape(label)}\s*:\s*", code[cursor:])
        if name is None:
            raise ValueError(f"command configuration has no {label} argument")
        start = code.find(expression, cursor + name.end())
        if start < 0:
            raise ValueError(f"command configuration has no {label} expression")
        cursor = start + len(expression)
        fields[label] = text[start:cursor], expression
    return fields


def registered_types(declaration):
    fields = own_configuration(declaration)
    if "subcommands" not in fields:
        raise ValueError("root command has no literal subcommands registry")
    _, expression = fields["subcommands"]
    if not expression.startswith("[") or not expression.endswith("]"):
        raise ValueError("root subcommands registry is not a literal array")
    names = []
    for entry in expression[1:-1].split(","):
        if not entry.strip():
            continue
        match = re.fullmatch(r"\s*(\w+)\.self\s*", entry)
        if match is None:
            raise ValueError("root subcommands registry has an unresolved type expression")
        names.append(match[1])
    return names


def command_name(declaration):
    fields = own_configuration(declaration)
    if "commandName" not in fields:
        return kebab(declaration[0])
    raw, _ = fields["commandName"]
    name = re.fullmatch(r'"([^"\\]*)"', raw)
    if name is None:
        raise ValueError(f"{declaration[0]}: command name is not a literal string")
    return name[1]


def tool_commands(root, tool):
    """Names actually registered at the tool's root, read from its canonical Swift registry."""
    declarations = command_declarations(root, tool)
    roots = [item for item in declarations if item[3]]
    if len(roots) != 1:
        raise ValueError(f"{tool}: expected one root command, found {len(roots)}")
    names = set()
    for registered in registered_types(roots[0]):
        selected = [item for item in declarations if item[0] == registered]
        if len(selected) != 1:
            raise ValueError(
                f"{tool}: expected one declaration for registered {registered}, found {len(selected)}")
        names.add(command_name(selected[0]))
    return names


def findings(root, page):
    text = (root / page).read_text(errors="ignore")
    targets = make_targets(root)
    problems = []
    named = 0
    for span in code_spans(text):
        for target in re.findall(r"\bmake\s+([A-Za-z0-9_-]+)", span):
            named += 1
            if target not in targets:
                problems.append(f"make {target}: no such Makefile target")
        for script in re.findall(r"\b(Scripts/[A-Za-z0-9_./-]+)", span):
            named += 1
            if not (root / script).is_file():
                problems.append(f"{script}: no such file")
        for tool, sub in re.findall(r"\b(uttrflow-eval|uttrflow-dev|uttrflow-bakeoff)\s+([a-z][a-z-]*)", span):
            named += 1
            try:
                if sub not in tool_commands(root, tool):
                    problems.append(f"{tool} {sub}: no such subcommand in Sources/{tool}")
            except ValueError as error:
                problems.append(str(error))
    if named == 0:
        problems.append(f"{page} names no command, so this audit checked nothing")
    return problems


def self_test():
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        (root / "Docs").mkdir()
        (root / "Scripts").mkdir()
        (root / "Sources" / "uttrflow-dev").mkdir(parents=True)
        (root / "Makefile").write_text("bakeoff: ## x\n\techo\n")
        (root / "Scripts" / "soak.sh").write_text("")
        (root / "Sources" / "uttrflow-dev" / "Bench.swift").write_text("struct Bench: AsyncParsableCommand {}\n")
        (root / "Sources" / "uttrflow-dev" / "Root.swift").write_text(
            "@main\nstruct Root: ParsableCommand { static let configuration = "
            "CommandConfiguration(subcommands: [Bench.self]) }\n")
        (root / PAGE).write_text("Run `make bakeoff` or `Scripts/soak.sh`.\n```\nuttrflow-dev bench jobs.tsv\n```\n")
        good = findings(root, PAGE)
        (root / PAGE).write_text("Run `make bakeof`, `Scripts/gone.sh` and `uttrflow-dev benchmark`.\n")
        bad = findings(root, PAGE)
    if good or len(bad) != 3:
        print(f"measure-a-change self-test failed: good={good} bad={bad}", file=sys.stderr)
        return 1
    from measure_commands_audit_test import RegisteredCommandTests
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RegisteredCommandTests)
    return 0 if unittest.TextTestRunner().run(suite).wasSuccessful() else 1


def main():
    if "--self-test" in sys.argv[1:] and self_test() != 0:
        return 1
    problems = findings(PACKAGE_ROOT, PAGE)
    for problem in problems:
        print(f"{PAGE}  {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

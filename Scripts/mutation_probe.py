#!/usr/bin/env python3
"""Applies one source mutation at a time to a Swift file and records whether any test fails."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

BASELINE = os.path.join("Scripts", "mutation_baseline.json")

# Binary comparisons are written with a space either side, which keeps generics and arrows out.
COMPARISON_FLIPS = {"<": ">=", ">=": "<", ">": "<=", "<=": ">", "==": "!=", "!=": "=="}
COMPARISON = re.compile(r"(?<= )(<=|>=|==|!=|<|>)(?= )")
LOGICAL_FLIPS = {"&&": "||", "||": "&&"}
LOGICAL = re.compile(r"(?<= )(&&|\|\|)(?= )")
# A closure's `$0` is a parameter, not a literal.
NUMBER = re.compile(r"(?<![\w.$])([0-9]+(?:\.[0-9]+)?)(?![\w.])")
REJECTION = re.compile(r"return \.rejected\(.*\)\s*(?:\}\s*)?$")
REJECTION_OPEN = re.compile(r"return \.rejected\(")


def code_spans(line):
    """Yields (start, end) of the parts of a line outside string literals and comments."""
    start, index, quoted = 0, 0, False
    while index < len(line):
        character = line[index]
        if quoted:
            if character == "\\":
                index += 2
                continue
            if character == '"':
                quoted, start = False, index + 1
        elif character == '"':
            yield start, index
            quoted = True
        elif line.startswith("//", index):
            yield start, index
            return
        index += 1
    if not quoted:
        yield start, len(line)


def shifted(literal, step):
    if "." in literal:
        whole, fraction = literal.split(".")
        return f"{int(whole) + step}.{fraction}" if int(whole) + step >= 0 else None
    value = int(literal) + step
    return str(value) if value >= 0 else None


def mutants(lines):
    """Every single-site mutation of the source, as (operator, line, column, original, replacement)."""
    found = []
    for number, line in enumerate(lines, start=1):
        stripped = line.lstrip()
        if stripped.startswith(("//", "///", "import ", "#")):
            continue
        for start, end in code_spans(line):
            segment = line[start:end]
            for match in COMPARISON.finditer(segment):
                found.append(("comparison", number, start + match.start(), match.group(1), COMPARISON_FLIPS[match.group(1)]))
            for match in LOGICAL.finditer(segment):
                found.append(("logical", number, start + match.start(), match.group(1), LOGICAL_FLIPS[match.group(1)]))
            for match in NUMBER.finditer(segment):
                for step in (1, -1):
                    replacement = shifted(match.group(1), step)
                    if replacement is not None:
                        found.append(("literal", number, start + match.start(), match.group(1), replacement))
            for match in REJECTION_OPEN.finditer(segment):
                found.append(("rejection", number, start + match.start(), "return .rejected(", None))
    return found


def apply(lines, mutant):
    """Returns the source with one mutant applied, or None when it cannot be stated on one line."""
    operator, number, column, original, replacement = mutant
    line = lines[number - 1]
    if operator == "rejection":
        tail = line[column:]
        if not REJECTION.match(tail):
            return None
        closing = "}" if tail.rstrip().endswith("}") and tail.count("{") < tail.count("}") else ""
        mutated = line[:column] + "return .accepted" + (" " + closing if closing else "") + "\n"
    else:
        mutated = line[:column] + replacement + line[column + len(original):]
    return lines[: number - 1] + [mutated] + lines[number:]


def describe(mutant):
    operator, number, column, original, replacement = mutant
    target = replacement if replacement is not None else "return .accepted"
    return f"{operator} line {number}:{column + 1} `{original.strip()}` -> `{target}`"


def refuse_outside_worktree(directory):
    """A linked worktree has a git dir apart from the common one; the main checkout does not."""
    def ask(flag):
        result = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", flag], cwd=directory, capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None
    git_dir, common = ask("--git-dir"), ask("--git-common-dir")
    if git_dir is None or git_dir == common:
        sys.exit("mutation_probe: run this from a linked worktree, never the main checkout")


def run(command, cwd, log, timeout):
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        output, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as expired:
        output, code = str(expired.stdout or "") + str(expired.stderr or ""), None
    with open(log, "a") as file:
        file.write(f"$ {' '.join(command)}\n{output}\nexit {code} after {time.monotonic() - started:.0f}s\n")
    return code


def probe(arguments):
    repository = os.getcwd()
    refuse_outside_worktree(repository)
    sandbox = tempfile.mkdtemp(prefix="mutation-probe-")
    subprocess.run(["git", "worktree", "add", "--detach", sandbox, arguments.ref], cwd=repository, check=True,
                   capture_output=True)
    log = os.path.join(tempfile.gettempdir(), "mutation_probe.log")
    open(log, "w").close()
    try:
        target = os.path.join(sandbox, arguments.file)
        with open(target) as file:
            original = file.readlines()
        build = ["swift", "build", "--build-tests"]
        test = ["swift", "test", "--skip-build", "--filter", arguments.filter]
        if run(build, sandbox, log, None) != 0 or run(test, sandbox, log, None) != 0:
            sys.exit(f"mutation_probe: the unmutated tree does not build and pass; see {log}")
        outcomes = []
        candidates = mutants(original)
        for index, mutant in enumerate(candidates[: arguments.limit or None], start=1):
            source = apply(original, mutant)
            if source is None:
                continue
            with open(target, "w") as file:
                file.writelines(source)
            if run(build, sandbox, log, arguments.timeout) != 0:
                verdict = "unviable"
            else:
                code = run(test, sandbox, log, arguments.timeout)
                verdict = "survived" if code == 0 else "killed"
            outcomes.append({"mutant": describe(mutant), "verdict": verdict})
            print(f"[{index}/{len(candidates)}] {verdict}: {describe(mutant)}", flush=True)
        with open(target, "w") as file:
            file.writelines(original)
        return outcomes
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", sandbox], cwd=repository, capture_output=True)
        shutil.rmtree(sandbox, ignore_errors=True)


def score(outcomes):
    killed = sum(1 for item in outcomes if item["verdict"] == "killed")
    survived = sum(1 for item in outcomes if item["verdict"] == "survived")
    return killed, survived, (killed / (killed + survived) if killed + survived else 0.0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", help="the Swift source to mutate, relative to the repository root")
    parser.add_argument("--filter", required=True, help="the `swift test --filter` that selects the module's tests")
    parser.add_argument("--ref", default="HEAD", help="the revision the throwaway worktree is cut from")
    parser.add_argument("--limit", type=int, default=0, help="stop after this many mutants; 0 runs them all")
    parser.add_argument("--timeout", type=int, default=900, help="seconds before a build or test run counts as hung")
    parser.add_argument("--report", help="write every outcome to this JSON file")
    parser.add_argument("--list", action="store_true", help="print the mutants without building anything")
    parser.add_argument("--update-baseline", action="store_true", help="record this score as the floor")
    arguments = parser.parse_args()
    if arguments.list:
        with open(arguments.file) as file:
            lines = file.readlines()
        for mutant in mutants(lines):
            if apply(lines, mutant) is not None:
                print(describe(mutant))
        return 0
    outcomes = probe(arguments)
    killed, survived, ratio = score(outcomes)
    print(f"killed {killed}, survived {survived}, score {ratio:.3f}")
    if arguments.report:
        with open(arguments.report, "w") as file:
            json.dump({"file": arguments.file, "score": ratio, "outcomes": outcomes}, file, indent=2)
    baseline = {}
    if os.path.exists(BASELINE):
        with open(BASELINE) as file:
            baseline = json.load(file)
    floor = baseline.get(arguments.file)
    if arguments.update_baseline:
        if floor is not None and round(ratio, 3) < floor:
            print(f"mutation_probe: refusing to lower the floor from {floor} to {ratio:.3f}", file=sys.stderr)
            return 1
        baseline[arguments.file] = round(ratio, 3)
        with open(BASELINE, "w") as file:
            json.dump(baseline, file, indent=2, sort_keys=True)
            file.write("\n")
        return 0
    if floor is not None and round(ratio, 3) < floor:
        print(f"mutation_probe: score fell from {floor} to {ratio:.3f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

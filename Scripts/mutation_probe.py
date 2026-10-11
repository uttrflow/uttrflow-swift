#!/usr/bin/env python3
"""Applies one source mutation at a time to a Swift file and records whether any test fails."""

import argparse
import json
import os
import re
import shutil
import signal
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


def require_clean_target(repository, target, reference):
    """Only a tracked, unchanged source from the selected current revision may be mutated."""
    relative = os.path.relpath(target, repository)
    if os.path.realpath(target) != target or relative.startswith(".." + os.sep):
        sys.exit("mutation_probe: target must stay inside the linked worktree")
    status = subprocess.run(["git", "status", "--porcelain", "--", relative],
                            cwd=repository, capture_output=True, text=True, check=True)
    revision = subprocess.run(["git", "show", f"{reference}:{relative}"],
                              cwd=repository, capture_output=True, check=True)
    with open(target, "rb") as file:
        current = file.read()
    if status.stdout or current != revision.stdout:
        sys.exit("mutation_probe: target must be clean and match --ref before mutation")


def require_runner(runner):
    if shutil.which(runner) is None:
        sys.exit("mutation_probe: --build-runner must name an executable build/test wrapper")


def interrupted(signum, frame):
    raise KeyboardInterrupt("mutation probe interrupted")


def run(command, cwd, log, timeout):
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
        code = process.returncode
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as failure:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            output, _ = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
        if isinstance(failure, KeyboardInterrupt):
            raise
        code = None
    with open(log, "a") as file:
        file.write(f"$ {' '.join(command)}\n{output}\nexit {code} after {time.monotonic() - started:.0f}s\n")
    return code


def assertion_failure(log):
    with open(log) as file:
        last_command = file.read().rsplit("$ ", 1)[-1]
    return re.search(r"Test run with [0-9]+ tests?.*failed", last_command) is not None


def trial(target, source, commands, log, timeout):
    build, test = commands
    repository = os.getcwd()
    with open(target, "w") as file:
        file.writelines(source)
    code = run(build, repository, log, timeout)
    if code is None:
        sys.exit(f"mutation_probe: build timed out; no score recorded; see {log}")
    if code != 0:
        return "unviable"
    code = run(test, repository, log, timeout)
    if code is None:
        sys.exit(f"mutation_probe: test timed out; no score recorded; see {log}")
    if code != 0 and (code != 1 or not assertion_failure(log)):
        sys.exit(f"mutation_probe: test infrastructure failed; no score recorded; see {log}")
    return "survived" if code == 0 else "killed"


def probe(arguments):
    repository = os.getcwd()
    refuse_outside_worktree(repository)
    require_runner(arguments.build_runner)
    target = os.path.abspath(os.path.join(repository, arguments.file))
    if arguments.report and os.path.realpath(arguments.report) == os.path.realpath(target):
        sys.exit("mutation_probe: the report cannot overwrite the source")
    require_clean_target(repository, target, arguments.ref)
    with open(target, "rb") as file:
        original_bytes = file.read()
    original = original_bytes.decode().splitlines(keepends=True)
    with tempfile.NamedTemporaryFile(prefix="mutation-probe-", suffix=".log", delete=False) as file:
        log = file.name
    print(f"mutation log: {log}", flush=True)
    build = [arguments.build_runner, "build", "--jobs", "4", "--build-tests", "--enable-code-coverage"]
    test = [arguments.build_runner, "test", "--jobs", "4", "--skip-build",
            "--enable-code-coverage", "--filter", arguments.filter]
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        if run(build, repository, log, None) != 0 or run(test, repository, log, None) != 0:
            sys.exit(f"mutation_probe: the unmutated tree does not build and pass; see {log}")
        outcomes = []
        candidates = mutants(original)
        for index, mutant in enumerate(candidates[: arguments.limit or None], start=1):
            source = apply(original, mutant)
            if source is None:
                continue
            verdict = trial(target, source, (build, test), log, arguments.timeout)
            outcomes.append({"mutant": describe(mutant), "verdict": verdict})
            if arguments.report:
                write_report(arguments, outcomes, complete=False)
            print(f"[{index}/{len(candidates)}] {verdict}: {describe(mutant)}", flush=True)
        return outcomes
    finally:
        with open(target, "wb") as file:
            file.write(original_bytes)
        signal.signal(signal.SIGTERM, previous)


def score(outcomes):
    killed = sum(1 for item in outcomes if item["verdict"] == "killed")
    survived = sum(1 for item in outcomes if item["verdict"] == "survived")
    return killed, survived, (killed / (killed + survived) if killed + survived else 0.0)


def write_report(arguments, outcomes, *, complete):
    with open(arguments.report, "w") as file:
        json.dump({"file": arguments.file, "score": score(outcomes)[2],
                   "complete": complete, "outcomes": outcomes}, file, indent=2)


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", help="the Swift source to mutate, relative to the repository root")
    parser.add_argument("--filter", required=True, help="the `swift test --filter` that selects the module's tests")
    parser.add_argument("--ref", default="HEAD", help="the revision the clean source must match")
    parser.add_argument("--build-runner",
                        help="executable build/test wrapper; every build and test uses this runner")
    parser.add_argument("--limit", type=int, default=0, help="stop after this many mutants; 0 runs them all")
    parser.add_argument("--timeout", type=int, default=900, help="seconds before a build or test run counts as hung")
    parser.add_argument("--report", help="write every outcome to this JSON file")
    parser.add_argument("--list", action="store_true", help="print the mutants without building anything")
    parser.add_argument("--update-baseline", action="store_true", help="record this score as the floor")
    arguments = parser.parse_args()
    if arguments.limit and arguments.update_baseline:
        parser.error("a partial --limit run cannot update the score floor")
    if not arguments.list and not arguments.build_runner:
        parser.error("--build-runner must name an executable build/test wrapper")
    return arguments


def main():
    arguments = parse_arguments()
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
        write_report(arguments, outcomes, complete=not arguments.limit)
    if arguments.limit:
        print("partial run: score floor not checked")
        return 0
    return check_floor(arguments, ratio)


def check_floor(arguments, ratio):
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

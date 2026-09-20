#!/usr/bin/env python3
"""Fails when product code breaks the energy or memory budget in `Docs/performance.md` in a way the source shows."""

import argparse
import ast
import os
import re
import sys

# Developer tools and measurement harnesses, which never run inside the shipped app.
NOT_PRODUCT = ("uttrflow-dev", "uttrflow-bakeoff", "uttrflow-eval", "UttrflowEval", "UttrflowTestSupport")

# The fewest seconds between an idle app's own wakeups: at most 2 a second.
WAKEUP_FLOOR = 0.5

# Where suggestion and model work lives, which must run at utility priority or below.
MODEL_WORK = ("Sources/UttrflowLocalModel/", "Sources/UttrflowPredict/", "Sources/Uttrflow/Suggestion/")

# The suggestion model's types, which the app may hand out only through a utility wrapper.
SUGGESTION_MODELS = ("MLXCandidateScorer", "IdleReleasingModel")

# The wrappers that run a suggestion model's work at utility priority.
UTILITY_WRAPPER = re.compile(r"\bDiscretionary\w*\s*\(")

# The largest MLX buffer cache a process may keep, in bytes.
CACHE_CAP = 256 * 1_048_576

# Wakeups below the floor that are allowed, keyed by file and interval expression, each with its reason printed on every run.
WAKEUPS_ALLOWED = {
    ("Sources/Uttrflow/Dock/DockPanelController.swift", "Self.meteringInterval"): (
        "the level meter, which runs only while a recording is in progress and stops with it"
    ),
    ("Sources/UttrflowInput/CarbonHotkeyMonitor.swift", ".milliseconds(Self.reconciliationMilliseconds)"): (
        "the release check, which runs only while the shortcut is held; see Docs/stuck-recording.md"
    ),
    ("Sources/UttrflowInput/PasteConfirmation.swift", "interval"): (
        "watches the caret after a paste the user made, bounded by the confirmation budget"
    ),
    ("Sources/UttrflowCore/Support/SingleInstanceLock.swift", "seconds(interval)"): (
        "waits for a quitting copy's lock at launch, bounded by the caller's timeout"
    ),
    ("Sources/UttrflowAudio/InputDeviceSession.swift", "delay"): (
        "retries a microphone that went away mid-recording, a fixed schedule of a few delays"
    ),
    ("Sources/UttrflowAudio/TapDrain.swift", "slice"): (
        "waits for the tap's last block as a recording ends, bounded by the drain window"
    ),
    ("Sources/UttrflowAccount/HTTPAuthenticationService.swift", "wait"): (
        "polls for a sign-in the user started, at the interval the server sets, until the code expires"
    ),
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", ".milliseconds(max(delay, 1))"): (
        "books one turn after a pause in typing, calling the other `wake` overload once; each keystroke replaces it"
    ),
}

# Loops whose interval is a stored value, checked against the constant that supplies it.
WAKEUPS_BOUND_BY = {
    ("Sources/UttrflowClipboard/PasteboardWatcher.swift", "interval"): "PasteboardWatcher.pollInterval",
    ("Sources/UttrflowPredict/IdleRelease.swift", "interval"): "IdleRelease.tight / 4",
}

# Known breaches of the budget, each open under the issue that fixes it; a listed breach that is gone fails as stale.
BREACHES_OPEN = {}

# ---------------------------------------------------------------------------------------------------------------
# Reading Swift
# ---------------------------------------------------------------------------------------------------------------


def blanked(text):
    """The source with comments and string contents replaced by spaces, so offsets and lines still match."""
    out = list(text)
    index, length = 0, len(text)

    def blank(start, end):
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "

    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            blank(index, end)
            index = end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end < 0 else end + 2
            blank(index, end)
            index = end
        elif text.startswith('"""', index) or text[index] == '"':
            closing = '"""' if text.startswith('"""', index) else '"'
            cursor = index + len(closing)
            while cursor < length and not text.startswith(closing, cursor):
                cursor += 2 if text[cursor] == "\\" else 1
            blank(index + len(closing), cursor)
            index = cursor + len(closing)
        else:
            index += 1
    return "".join(out)


def matching(text, opening):
    """The offset of the bracket that closes the one at `opening`, or the end of the text."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    brackets = re.compile(re.escape(text[opening]) + "|" + re.escape(pairs[text[opening]]))
    depth = 0
    for match in brackets.finditer(text, opening):
        depth += 1 if match.group(0) == text[opening] else -1
        if depth == 0:
            return match.start()
    return len(text)


def arguments(text, opening):
    """The top-level arguments of the call whose parenthesis is at `opening`, as label and expression pairs."""
    end = matching(text, opening)
    inner = text[opening + 1 : end]
    parts, depth, start = [], 0, 0
    for index, character in enumerate(inner):
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            parts.append(inner[start:index])
            start = index + 1
    parts.append(inner[start:])
    labelled = []
    for part in parts:
        match = re.match(r"\s*(\w+)\s*:(?!:)\s*(.*)", part, re.S)
        labelled.append((match.group(1), match.group(2).strip()) if match else (None, part.strip()))
    return labelled


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def product_files(root):
    for directory, _, names in os.walk(os.path.join(root, "Sources")):
        relative = os.path.relpath(directory, root)
        parts = relative.split(os.sep)
        if len(parts) > 1 and parts[1] in NOT_PRODUCT:
            continue
        for name in sorted(names):
            if name.endswith(".swift"):
                yield os.path.join(relative, name).replace(os.sep, "/")


class Tree:
    """Every product source file, read once, with comments and strings blanked; `overrides` replaces a file's text."""

    def __init__(self, root, overrides=None):
        overrides = overrides or {}
        self.root = root

        def read(path):
            if path in overrides:
                return overrides[path]
            with open(os.path.join(root, path), encoding="utf-8") as handle:
                return handle.read()

        self.read = read
        self.files = {path: blanked(read(path)) for path in product_files(root)}
        self.constants = {}
        declaration = re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::\s*[\w.<>]+)?\s*=\s*([^\n;{]+)")
        for path, text in self.files.items():
            types = type_ranges(text)
            for match in declaration.finditer(text):
                owner = next((name for start, end, name in types if start < match.start() < end), None)
                self.constants.setdefault(match.group(1), []).append((path, owner, match.group(2).strip()))
        # A parameter's default is what a stored value holds unless a caller passes another, so it resolves too.
        self.defaults = {}
        parameter = re.compile(r"[(,]\s*(?:\w+\s+)?(\w+)\s*:\s*(?:Duration|TimeInterval|Double)\s*=\s*([^,)\n]+(?:\([^)\n]*\))?)")
        for path, text in self.files.items():
            for match in parameter.finditer(text):
                self.defaults.setdefault(match.group(1), []).append((path, None, match.group(2).strip()))


def type_ranges(text):
    """Every type declared in a file as (start, end, name), innermost first."""
    ranges = []
    for match in re.finditer(r"\b(?:struct|class|enum|actor|extension)\s+([\w.]+)[^{;]*\{", text):
        opening = match.end() - 1
        ranges.append((match.start(), matching(text, opening), match.group(1).split(".")[-1]))
    return sorted(ranges, key=lambda entry: entry[0], reverse=True)


# ---------------------------------------------------------------------------------------------------------------
# Resolving an interval to seconds
# ---------------------------------------------------------------------------------------------------------------

UNITS = {"seconds": 1.0, "milliseconds": 1e-3, "microseconds": 1e-6, "nanoseconds": 1e-9}


def seconds(tree, expression, path, depth=0):
    """The expression's value in seconds when the source settles it, otherwise None."""
    if depth > 8:
        return None
    expression = re.sub(r"(?<=\d)_(?=\d)", "", expression.strip())
    for unit, scale in UNITS.items():
        pattern = re.compile(r"(?:Duration|DispatchTimeInterval)?\s*\.\s*" + unit + r"\s*\(")
        while True:
            match = pattern.search(expression)
            if not match:
                break
            opening = match.end() - 1
            end = matching(expression, opening)
            inner = expression[opening + 1 : end]
            expression = expression[: match.start()] + f"(({inner})*{scale})" + expression[end + 1 :]
    expression = re.sub(r"\b(?:TimeInterval|Double|Int|Float|CGFloat)\s*\(", "(", expression)

    def substitute(match):
        dotted = match.group(0)
        parts = dotted.split(".")
        name = parts[-1]
        owner = parts[-2] if len(parts) > 1 and parts[-2] != "Self" else None
        candidates = tree.constants.get(name, [])
        if owner:
            candidates = [entry for entry in candidates if entry[1] == owner] or candidates
        local = [entry for entry in candidates if entry[0] == path]
        chosen = local or candidates
        if not chosen and not owner:
            chosen = [entry for entry in tree.defaults.get(name, []) if entry[0] == path]
        if len(chosen) != 1:
            raise LookupError(dotted)
        value = seconds(tree, chosen[0][2], chosen[0][0], depth + 1)
        if value is None:
            raise LookupError(dotted)
        return repr(value)

    try:
        expression = re.sub(r"(?<![\w.])(?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*(?![\w(])", substitute, expression)
        node = ast.parse(expression, mode="eval")
    except (LookupError, SyntaxError):
        return None
    return arithmetic(node)


def arithmetic(node):
    """The value of a parsed expression made only of numbers and + - * /, otherwise None."""
    allowed = (ast.Expression, ast.BinOp, ast.UnaryOp, ast.Constant, ast.Add, ast.Sub, ast.Mult, ast.Div, ast.USub)
    if not all(isinstance(child, allowed) for child in ast.walk(node)):
        return None
    if any(isinstance(child, ast.Constant) and not isinstance(child.value, (int, float)) for child in ast.walk(node)):
        return None
    try:
        return float(eval(compile(node, "<arithmetic>", "eval")))
    except (ZeroDivisionError, TypeError, OverflowError):
        return None


# ---------------------------------------------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------------------------------------------


class Findings:
    def __init__(self):
        self.failures = []
        self.notes = []
        self.used = set()

    def fail(self, check, path, line, message, key=None):
        if key is not None and key in BREACHES_OPEN:
            self.used.add(key)
            self.notes.append(f"{check}: {path}:{line} known breach, {BREACHES_OPEN[key]}")
            return
        self.failures.append(f"{check}: {path}:{line} {message}")


def repeating_sites(text):
    """Yields (offset, kind, interval expression) for every repeating timer, display link and sleeping loop."""
    for match in re.finditer(r"\bTimer\s*(?:\.\s*scheduledTimer\s*)?\(", text):
        labelled = dict((label, value) for label, value in arguments(text, match.end() - 1) if label)
        # A `repeats` passed through from a caller may be true, so only a literal `false` is a one-shot.
        if "repeats" in labelled and labelled["repeats"] != "false":
            interval = labelled.get("withTimeInterval") or labelled.get("timeInterval")
            if interval:
                yield match.start(), "repeating timer", interval
    for match in re.finditer(r"\bTimer\s*\.\s*publish\s*\(", text):
        labelled = dict((label, value) for label, value in arguments(text, match.end() - 1) if label)
        yield match.start(), "timer publisher", labelled.get("every", "")
    for match in re.finditer(r"\.\s*schedule\s*\(", text):
        labelled = dict((label, value) for label, value in arguments(text, match.end() - 1) if label)
        if "repeating" in labelled and labelled["repeating"] not in (".never", "DispatchTimeInterval.never"):
            yield match.start(), "repeating dispatch timer", labelled["repeating"]
    for match in re.finditer(r"\b(?:CADisplayLink|CVDisplayLink\w*|displayLink)\s*\(", text):
        yield match.start(), "display link", "display refresh"
    loops = []
    for match in re.finditer(r"(?<![.\w])(while|repeat|for)\b(?!\s*:)", text):
        opening = text.find("{", match.end())
        if opening < 0:
            continue
        header = text[match.end() : opening]
        if match.group(1) == "repeat" and header.strip():
            continue
        # A `for` that is an argument label, as in `for query: Query`, has no `in` before its body.
        if match.group(1) == "for" and (re.match(r"\s*\w+\s*:", header) or not re.search(r"\bin\b", header)):
            continue
        loops.append((opening, matching(text, opening)))
    sleep = re.compile(r"\b(?:sleep|pause)\s*\(")
    for match in sleep.finditer(text):
        if not any(start < match.start() < end for start, end in loops):
            continue
        labelled = arguments(text, match.end() - 1)
        if not labelled or labelled == [(None, "")]:
            continue
        label, value = labelled[0]
        if label == "nanoseconds":
            value = f".nanoseconds({value})"
        yield match.start(), "sleeping loop", value
    for offset, interval in rescheduling_sites(text, loops):
        yield offset, "self-rescheduling callback", interval


def calls_itself(text, name, start, end):
    """Whether the function `name` is called, or named as a selector, between start and end."""
    pattern = r"(?:(?<![\w.])|\bself\??\.)" + re.escape(name) + r"\s*\(|#selector\(\s*(?:\w+\.)?" + re.escape(name) + r"\b"
    return re.search(pattern, text[start:end]) is not None


def rescheduling_sites(text, loops):
    """Yields (offset, interval) for every delay in a function that is followed by a call back into that function."""
    delays = re.compile(r"\basyncAfter\s*\(|\bperform\s*\(|\b(?:sleep|pause)\s*\(|\bTimer\s*(?:\.\s*scheduledTimer\s*)?\(")
    for name, _, opening, end, _ in functions(text):
        for match in delays.finditer(text, opening, end):
            if any(start < match.start() < stop for start, stop in loops):
                continue
            labelled = arguments(text, match.end() - 1)
            labels = dict((label, value) for label, value in labelled if label)
            call = match.group(0)
            if call.startswith("asyncAfter"):
                deadline = labels.get("deadline") or labels.get("wallDeadline") or ""
                interval = re.sub(r"^\s*(?:DispatchTime|DispatchWallTime)?\s*\.\s*now\s*\(\s*\)\s*\+\s*", "", deadline)
            elif call.startswith("perform"):
                if "afterDelay" not in labels:
                    continue
                interval = labels["afterDelay"]
            elif call.startswith("Timer"):
                if labels.get("repeats") != "false":
                    continue
                interval = labels.get("withTimeInterval") or labels.get("timeInterval") or ""
            else:
                if not labelled or labelled == [(None, "")]:
                    continue
                label, interval = labelled[0]
                if label == "nanoseconds":
                    interval = f".nanoseconds({interval})"
            if calls_itself(text, name, match.start(), end):
                yield match.start(), interval


def check_wakeups(tree, findings, report):
    seen = set()
    for path, text in tree.files.items():
        for offset, kind, expression in repeating_sites(text):
            line = line_of(text, offset)
            key = (path, re.sub(r"\s+", "", expression) if kind != "display link" else kind)
            display = expression if kind != "display link" else kind
            allowed_key = next(
                (candidate for candidate in WAKEUPS_ALLOWED if (candidate[0], re.sub(r"\s+", "", candidate[1])) == key),
                None,
            )
            bound_key = next(
                (candidate for candidate in WAKEUPS_BOUND_BY if (candidate[0], re.sub(r"\s+", "", candidate[1])) == key),
                None,
            )
            if bound_key:
                seen.add(bound_key)
                value = seconds(tree, WAKEUPS_BOUND_BY[bound_key], path)
                if value is None:
                    findings.fail("wakeups", path, line, f"{kind} bound by {WAKEUPS_BOUND_BY[bound_key]}, which no longer resolves")
                elif value < WAKEUP_FLOOR:
                    findings.fail("wakeups", path, line, f"{kind} every {value:g} s via {WAKEUPS_BOUND_BY[bound_key]}, under {WAKEUP_FLOOR:g} s", key)
                else:
                    report.append(f"  ✓ {path}:{line} {kind} every {value:g} s ({WAKEUPS_BOUND_BY[bound_key]})")
                continue
            value = None if kind == "display link" else seconds(tree, expression, path)
            if value is not None and value >= WAKEUP_FLOOR:
                report.append(f"  ✓ {path}:{line} {kind} every {value:g} s")
                continue
            if allowed_key:
                seen.add(allowed_key)
                report.append(f"  ✓ {path}:{line} {kind} {display}, allowed: {WAKEUPS_ALLOWED[allowed_key]}")
                continue
            what = f"every {value:g} s, under {WAKEUP_FLOOR:g} s" if value is not None else f"at `{display}`, which the audit cannot resolve"
            findings.fail("wakeups", path, line, f"{kind} {what}", key)
    for stale in (set(WAKEUPS_ALLOWED) | set(WAKEUPS_BOUND_BY)) - seen:
        findings.failures.append(f"wakeups: {stale[0]} no longer has a site at `{stale[1]}`; remove it from the list")


PRIORITY_ABOVE_UTILITY = re.compile(
    r"(?:priority\s*:\s*(?:TaskPriority)?\.(?:userInitiated|high|userInteractive|medium)"
    r"|qos\s*:\s*(?:DispatchQoS)?\.(?:userInitiated|userInteractive|default)"
    r"|qualityOfService\s*=\s*\.(?:userInitiated|userInteractive|default)"
    r"|DispatchQueue\s*\.\s*global\s*\(\s*\))"
)


def check_priority(tree, findings, report):
    scanned = 0
    for path, text in tree.files.items():
        if path.startswith(MODEL_WORK):
            scanned += 1
            for match in PRIORITY_ABOVE_UTILITY.finditer(text):
                line = line_of(text, match.start())
                findings.fail("priority", path, line, f"`{match.group(0)}` runs model work above utility", (path, "priority", match.group(0)))
            for match in re.finditer(r"\bTask\s*\.\s*detached\s*(\(|\{)", text):
                if match.group(1) == "{" or not re.match(r"\s*priority\s*:\s*\.(?:utility|background|low)\b", text[match.end() :]):
                    line = line_of(text, match.start())
                    findings.fail("priority", path, line, "a detached task without utility or lower priority", (path, "priority", "Task.detached"))
        if path.startswith(("Sources/UttrflowLocalModel/", "Sources/UttrflowPredict/")):
            continue
        for model in SUGGESTION_MODELS:
            for binding in re.finditer(r"\b(?:let|var)\s+(\w+)\s*=\s*" + model + r"\s*\(", text):
                name = binding.group(1)
                wrapped = []
                for call in UTILITY_WRAPPER.finditer(text):
                    wrapped.append((call.end() - 1, matching(text, call.end() - 1)))
                constructor = matching(text, binding.end() - 1)
                for use in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\b(?!\s*:(?!:))", text[constructor:]):
                    offset = constructor + use.start()
                    if any(start < offset < end for start, end in wrapped):
                        continue
                    line = line_of(text, offset)
                    snippet = text[offset : text.find("\n", offset)].strip()
                    findings.fail(
                        "priority", path, line,
                        f"the suggestion model `{name}` is used outside a utility wrapper: `{snippet}`",
                        (path, "model", snippet),
                    )
    report.append(f"  ✓ {scanned} model-work files read for priority")


GATES = ("MotionBudget", "WindowAttention")


def gate_names(text):
    """The names in a file bound from the motion budget or window attention, which count as a gate where used."""
    names = set()
    for match in re.finditer(r"\b(?:let|var)\s+(\w+)\s*=\s*[^\n]*\b(?:MotionBudget\w*|WindowAttention\w*)", text):
        names.add(match.group(1))
    for match in re.finditer(r"\.onWindowAttentionChange\s*\{\s*(\w+)\s*=", text):
        names.add(match.group(1))
    return names


def mentions_gate(fragment, names):
    if any(gate in fragment for gate in GATES):
        return True
    return any(re.search(r"(?<![\w.])" + re.escape(name) + r"\b", fragment) for name in names)


def check_motion(tree, findings, report):
    counted = 0
    for path, text in tree.files.items():
        names = gate_names(text)
        for match in re.finditer(r"\bTimelineView\s*\(", text):
            counted += 1
            opening = match.end() - 1
            fragment = text[opening : matching(text, opening) + 1]
            line = line_of(text, match.start())
            if not mentions_gate(fragment, names):
                findings.fail("motion", path, line, "a TimelineView whose schedule reads neither MotionBudget nor WindowAttention", (path, "motion", "TimelineView"))
            elif re.search(r"\b(?:paused|isStill)\s*:\s*(?:true|false)\b", fragment):
                findings.fail("motion", path, line, "a TimelineView paused by a literal rather than by its gate", (path, "motion", "TimelineView"))
            else:
                report.append(f"  ✓ {path}:{line} TimelineView gated")
        repeating = re.compile(
            r"\.repeatForever\s*\(|\brepeatCount\s*=\s*(?:\.infinity|Float\.greatestFiniteMagnitude)"
            r"|\bPhaseAnimator\s*\(|\.phaseAnimator\s*\(|\.keyframeAnimator\s*\([^)]*repeating\s*:\s*true"
            r"|\.symbolEffect\s*\([^)]*\.(?:pulse|breathe|rotate|variableColor|wiggle|bounce)\b[^)]*options\s*:\s*\.repeat"
        )
        for match in repeating.finditer(text):
            counted += 1
            line = line_of(text, match.start())
            lines = text.split("\n")
            window = "\n".join(lines[max(0, line - 4) : line + 3])
            if mentions_gate(window, names):
                report.append(f"  ✓ {path}:{line} repeating animation gated")
            else:
                findings.fail("motion", path, line, f"`{match.group(0).strip()}` repeats without a MotionBudget or WindowAttention gate nearby", (path, "motion", match.group(0).strip()))
    report.append(f"  ✓ {counted} continuous animations read")


PASS_CALL = re.compile(r"\.\s*perform\s*[({]|\bMLXLMCommon\s*\.\s*generate\s*\(|\bTokenIterator\s*\(|\bChatSession\s*\(|\bgenerate\s*\(\s*input\s*:")


def functions(text):
    """Yields (name, start, body opening, body end, is private) for every function with a body."""
    for match in re.finditer(r"((?:(?:private|fileprivate|static|nonisolated|public|internal|override|mutating)\s+)*)func\s+(\w+)", text):
        parameters = text.find("(", match.end())
        if parameters < 0:
            continue
        opening = text.find("{", matching(text, parameters))
        if opening < 0:
            continue
        # A protocol requirement has no body before the next declaration.
        between = text[match.end() : opening]
        if re.search(r"\bfunc\b|\bvar\b|\blet\b", between):
            continue
        yield match.group(2), match.start(), opening, matching(text, opening), "private" in match.group(1)


def check_cache(tree, findings, report):
    mlx_files = [path for path, text in tree.files.items() if re.search(r"^\s*(?:public\s+|private\s+)?import\s+MLX", text, re.M)]
    passes = 0
    for path in mlx_files:
        text = tree.files[path]
        bodies = list(functions(text))
        guarded = {}
        for name, start, opening, end, private in bodies:
            body = text[opening:end]
            guarded[(name, start)] = bool(re.search(r"\.hold\s*\(\s*\)", body) and re.search(r"\bdefer\s*\{[^}]*\.clear\s*\(\s*\)", body))
        changed = True
        while changed:
            changed = False
            for name, start, opening, end, private in bodies:
                if guarded[(name, start)] or not private:
                    continue
                callers = [
                    other for other in bodies
                    if other[1] != start and re.search(r"(?<![\w])(?:self\.|Self\.)?" + name + r"\s*\(", text[other[2] : other[3]])
                ]
                if callers and all(guarded[(other[0], other[1])] for other in callers):
                    guarded[(name, start)] = True
                    changed = True
        for match in PASS_CALL.finditer(text):
            owner = [entry for entry in bodies if entry[2] < match.start() < entry[3]]
            if not owner:
                continue
            passes += 1
            innermost = max(owner, key=lambda entry: entry[2])
            outermost_guarded = any(guarded[(entry[0], entry[1])] for entry in owner)
            line = line_of(text, match.start())
            if outermost_guarded:
                report.append(f"  ✓ {path}:{line} pass inside {innermost[0]}(), which caps and clears the cache")
            else:
                findings.fail(
                    "cache", path, line,
                    f"a model pass in {innermost[0]}() that neither caps MLX's cache nor clears it on the way out",
                    (path, "cache", innermost[0]),
                )
        for name, start, opening, end, private in bodies:
            if name == "release" and not re.search(r"\.clear\s*\(\s*\)", text[opening:end]):
                findings.fail("cache", path, line_of(text, start), "release() drops the model without clearing MLX's cache", (path, "cache", "release"))
        for match in re.finditer(r"\bMemory\s*\.\s*cacheLimit\s*=\s*([^\n}]+)", text):
            if match.group(1).strip() != "GPUBufferCache.limit":
                findings.fail("cache", path, line_of(text, match.start()), f"MLX's cache capped at `{match.group(1).strip()}` rather than GPUBufferCache.limit")
        for match in re.finditer(r"\bGPU\s*\.\s*set\s*\(\s*cacheLimit", text):
            findings.fail("cache", path, line_of(text, match.start()), "MLX's cache capped outside GPUBufferCache")
    limit_file = "Sources/UttrflowLocalModel/GPUBufferCache.swift"
    limit = re.search(r"static\s+let\s+limit\s*=\s*([^\n]+)", tree.files.get(limit_file, ""))
    if not limit:
        findings.failures.append(f"cache: {limit_file} no longer declares GPUBufferCache.limit")
    else:
        try:
            value = arithmetic(ast.parse(re.sub(r"(?<=\d)_(?=\d)", "", limit.group(1).strip()), mode="eval"))
        except SyntaxError:
            value = None
        if value is None or value > CACHE_CAP:
            findings.failures.append(f"cache: GPUBufferCache.limit is `{limit.group(1).strip()}`, over {CACHE_CAP // 1_048_576} MB")
        else:
            report.append(f"  ✓ GPUBufferCache.limit is {int(value) // 1_048_576} MB")
    report.append(f"  ✓ {passes} model passes read in {len(mlx_files)} MLX files")


BUDGET_ROWS = {
    "idle, suggestions off": "idleSuggestionsOff",
    "peak during a dictation, suggestions off": "dictationPeak",
    "suggestions on, between passes": "suggestionsBetweenPasses",
    "suggestions on, peak of a pass": "suggestionsPassPeak",
}


def megabytes(cell):
    match = re.search(r"≤\s*([\d.]+)\s*(MB|GB)", cell)
    if not match:
        return None
    number = float(match.group(1))
    return int(round(number * 1024)) if match.group(2) == "GB" else int(round(number))


def check_counters(tree, findings, report):
    """The limits the harness judges readings by must be the budget table's, so the two cannot drift apart."""
    try:
        doc = tree.read("Docs/performance.md")
        swift = tree.read("Sources/UttrflowEval/ResourceBudget.swift")
    except FileNotFoundError as missing:
        findings.failures.append(f"counters: {missing.filename} is gone; the harness has nothing to judge readings by")
        return
    for row, member in BUDGET_ROWS.items():
        cells = re.search(r"^\|\s*" + re.escape(row) + r"\s*\|([^|]*)\|", doc, re.M)
        declared = re.search(r"\bcase\s+" + member + r"\b[^\n]*", swift)
        limit = re.search(r"case\s*\.\s*" + member + r"\s*:\s*return\s+([\d_]+)", swift)
        if not cells:
            findings.failures.append(f"counters: Docs/performance.md has no budget row `{row}`")
            continue
        if not declared or not limit:
            findings.failures.append(f"counters: ResourceBudget has no limit for `{member}`")
            continue
        expected = megabytes(cells.group(1))
        actual = int(limit.group(1).replace("_", ""))
        if expected != actual:
            findings.failures.append(f"counters: `{row}` is {expected} MB in Docs/performance.md and {actual} MB in ResourceBudget")
        else:
            report.append(f"  ✓ {row}: {actual} MB in both the document and ResourceBudget")


# ---------------------------------------------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------------------------------------------


def audit(root, quiet=False, overrides=None):
    tree = Tree(root, overrides)
    findings = Findings()
    sections = []
    for title, check in (
        ("Wakeups: nothing repeats faster than twice a second unless listed", lambda r: check_wakeups(tree, findings, r)),
        ("Priority: suggestion and model work runs at utility or below", lambda r: check_priority(tree, findings, r)),
        ("Motion: every continuous animation reads its gate", lambda r: check_motion(tree, findings, r)),
        ("Cache: every model pass caps MLX's cache and clears it", lambda r: check_cache(tree, findings, r)),
        ("Counters: the harness judges readings by the budget table", lambda r: check_counters(tree, findings, r)),
    ):
        report = []
        check(report)
        sections.append((title, report))
    for stale in set(BREACHES_OPEN) - findings.used:
        findings.failures.append(f"stale: {stale[0]} no longer breaches at `{stale[2]}`; remove it from BREACHES_OPEN")
    if not quiet:
        for title, report in sections:
            print(f"\n{title}")
            for line in report:
                print(line)
        for note in findings.notes:
            print(f"  ! {note}")
    return findings


# Each injection is (file, text to find, text to put in its place, the check that must fail), run on a copy of the tree.
INJECTIONS = (
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "Duration.milliseconds(500)", "Duration.milliseconds(200)", "wakeups",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionTicking.swift",
        "static let interval: TimeInterval = 1", "static let interval: TimeInterval = 0.25", "wakeups",
    ),
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "    // MARK: - The loop",
        "    func spin() async { while true { try? await Task.sleep(for: .milliseconds(100)) } }\n    // MARK: - The loop",
        "wakeups",
    ),
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "    // MARK: - The loop",
        "    func tick() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.tick() } }\n    // MARK: - The loop",
        "wakeups",
    ),
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "    // MARK: - The loop",
        "    func tick() async { try? await Task.sleep(for: .milliseconds(100)); await tick() }\n    // MARK: - The loop",
        "wakeups",
    ),
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "    // MARK: - The loop",
        "    @objc func tick() { perform(#selector(tick), with: nil, afterDelay: 0.1) }\n    // MARK: - The loop",
        "wakeups",
    ),
    (
        "Sources/UttrflowClipboard/PasteboardWatcher.swift",
        "    // MARK: - The loop",
        "    func every(_ seconds: TimeInterval, repeats: Bool) { _ = Timer.scheduledTimer(withTimeInterval: seconds, repeats: repeats) { _ in } }\n    // MARK: - The loop",
        "wakeups",
    ),
    (
        "Sources/UttrflowPredict/DiscretionaryGenerator.swift",
        "Task.detached(priority: .utility)", "Task.detached(priority: .userInitiated)", "priority",
    ),
    (
        "Sources/Uttrflow/Main/ClipboardDemonstration.swift",
        "ClipboardDemonstrationSchedule(typedLength: typedLength, isStill: !animates)",
        ".animation", "motion",
    ),
    (
        "Sources/Uttrflow/Main/ClipboardDemonstration.swift",
        ".cardSurface()", ".cardSurface()\n        .animation(.easeInOut.repeatForever(), value: offeredWidth)", "motion",
    ),
    (
        "Sources/UttrflowLocalModel/MLXCandidateScorer.swift",
        "        bufferCache.hold()\n        defer { bufferCache.clear() }\n        guard let container, !Task.isCancelled else { return [] }",
        "        guard let container, !Task.isCancelled else { return [] }", "cache",
    ),
    (
        "Sources/Uttrflow/Dock/DockView.swift",
        "paused: !motion.workingDotsMove", "paused: false", "motion",
    ),
    (
        "Sources/UttrflowLocalModel/MLXCandidateScorer.swift",
        "        await weights.unload()\n        bufferCache.clear()", "        await weights.unload()", "cache",
    ),
    (
        "Sources/UttrflowLocalModel/GPUBufferCache.swift",
        "256 * 1_048_576", "1_024 * 1_048_576", "cache",
    ),
    (
        "Sources/UttrflowEval/ResourceBudget.swift",
        "case .idleSuggestionsOff: return 300", "case .idleSuggestionsOff: return 900", "counters",
    ),
)


def self_test(root):
    """Injects each violation into the tree as read and confirms the audit fails on exactly that check."""
    print("\nSelf-test: each injected violation must fail its check")
    baseline = {failure.split(":")[0] for failure in audit(root, quiet=True).failures}
    failed = 0
    for path, find, replace, check in INJECTIONS:
        with open(os.path.join(root, path), encoding="utf-8") as handle:
            original = handle.read()
        if find not in original:
            print(f"  ✗ {path}: the injection site `{find[:60]}` is gone; update INJECTIONS")
            failed += 1
            continue
        injected = {path: original.replace(find, replace, 1)}
        caught = [failure for failure in audit(root, quiet=True, overrides=injected).failures if failure.startswith(check + ":")]
        if caught and check not in baseline:
            print(f"  ✓ {check} catches {path}: {caught[0].split(' ', 2)[-1]}")
        else:
            print(f"  ✗ {check} did not catch an injection into {path}")
            failed += 1
    return failed


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="The wakeup check reads one file at a time and follows no calls: a sleep in a function a loop calls, "
        "two functions that schedule each other, or an interval set by another file's caller gets past it. "
        "See Docs/performance.md.",
    )
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--self-test", action="store_true", help="also prove each check fails on an injected violation")
    options = parser.parse_args()
    findings = audit(options.root)
    if findings.failures:
        print(f"\n  ✗ {len(findings.failures)} breach(es) of the budget in Docs/performance.md:", file=sys.stderr)
        for failure in findings.failures:
            print(f"    {failure}", file=sys.stderr)
        print("    Fix the code, or list a wakeup with the reason it is not an idle cost.\n", file=sys.stderr)
        return 1
    if options.self_test and self_test(options.root):
        print("\n  ✗ the self-test found a check that no longer fails on its injected violation\n", file=sys.stderr)
        return 1
    print("\nperf budget audit: the source keeps to the budget.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

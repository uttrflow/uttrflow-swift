#!/usr/bin/env python3
"""Fails when product code breaks the energy or memory budget in `Docs/performance.md` in a way the source shows."""

import argparse
import ast
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dictation_bench as bench  # noqa: E402

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
    ("Sources/Uttrflow/Settings/SettingsPauseCountdown.swift", ".seconds(min(60, remaining) + 0.5)"): (
        "the suggestion pause countdown, at most once a minute and only while a pause runs with Settings open"
    ),
    ("Sources/UttrflowPipeline/DictationPipeline.swift", "PendingInsertionConfirmation.interval"): (
        "watches for a dictated insertion to land, bounded by PendingInsertionConfirmation.budget"
    ),
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", "0.2"): (
        "checks the caret only while a drawn offer can be accepted, and stops when the offer is withdrawn"
    ),
    ("Sources/UttrflowPipeline/DictationController.swift", "start.advanced(by:elapsed)"): (
        "the recording cap's countdown, every ten seconds in a recording's last minute and never at rest"
    ),
    ("Sources/Uttrflow/Dock/DockPanelController.swift", "Self.meteringInterval"): (
        "the level meter, which runs only while a recording is in progress and stops with it"
    ),
    ("Sources/UttrflowInput/CarbonHotkeyMonitor.swift", ".milliseconds(Self.reconciliationMilliseconds)"): (
        "the release check, which runs only while the shortcut is held; see Docs/stuck-recording.md"
    ),
    ("Sources/UttrflowInput/ActivationMonitor.swift", ".milliseconds(Self.reconciliationMilliseconds)"): (
        "the release check, which runs only while the dictation key is held; see Docs/stuck-recording.md"
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
    ("Sources/UttrflowPredict/IdleRelease.swift", "wait"): (
        "sleeps until the idle window can run out, never under a tenth of it (18 s), and ends once the model is let go"
    ),
    ("Sources/UttrflowSpeech/BackedSpeechEngine.swift", "wait"): (
        "sleeps until the speech model's ten-minute idle window can run out, and ends once the model is let go"
    ),
}

# Loops whose interval is a stored value, checked against every constant that supplies it.
WAKEUPS_BOUND_BY = {
    ("Sources/UttrflowClipboard/PasteboardWatcher.swift", "interval"): ("PasteboardWatcher.pollInterval",),
    ("Sources/Uttrflow/UsageTelemetry.swift", "interval"): ("UsageTelemetry.flushInterval",),
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", "interval"): (
        "SuggestionTicking.interval", "SuggestionTicking.ghostInterval",
    ),
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
                for bound in WAKEUPS_BOUND_BY[bound_key]:
                    value = seconds(tree, bound, path)
                    if value is None:
                        findings.fail("wakeups", path, line, f"{kind} bound by {bound}, which no longer resolves")
                    elif value < WAKEUP_FLOOR:
                        findings.fail("wakeups", path, line, f"{kind} every {value:g} s via {bound}, under {WAKEUP_FLOOR:g} s", key)
                    else:
                        report.append(f"  ✓ {path}:{line} {kind} every {value:g} s ({bound})")
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

# Panels that never become key, so WindowAttention never lets them move; each has its own reason it is not hidden while it runs.
WINDOW_EXEMPT = {
    "Sources/Uttrflow/Dock/": "the dock is a floating panel above every window, and its controller empties it whenever it is ordered out",
    "Sources/Uttrflow/MenuBar/": "the popover's controller hosts content only while the panel is on screen and empties it on close",
}


def gate_names(text):
    """The names in a file bound from the motion budget or window attention, which count as a gate where used."""
    names = set()
    for match in re.finditer(r"\b(?:let|var)\s+(\w+)\s*=\s*[^\n]*\b(?:MotionBudget\w*|WindowAttention\w*)", text):
        names.add(match.group(1))
    return names | attention_names(text)


def attention_names(text):
    """The names in a file bound from window attention, which say whether anybody can see the view."""
    names = set()
    for match in re.finditer(r"\b(?:let|var)\s+(\w+)\s*=\s*[^\n]*\bWindowAttention\w*", text):
        names.add(match.group(1))
    for match in re.finditer(r"\.onWindowAttentionChange\s*(?:\([^)]*\))?\s*\{\s*(\w+)\s*=", text):
        names.add(match.group(1))
    return names


def mentions_attention(fragment, names):
    if "WindowAttention" in fragment:
        return True
    return any(re.search(r"(?<![\w.])" + re.escape(name) + r"\b", fragment) for name in names)


def mentions_gate(fragment, names):
    if any(gate in fragment for gate in GATES):
        return True
    return any(re.search(r"(?<![\w.])" + re.escape(name) + r"\b", fragment) for name in names)


def check_motion(tree, findings, report):
    counted = 0
    for path, text in tree.files.items():
        names = gate_names(text)
        watched = attention_names(text)
        exempt = any(path.startswith(prefix) for prefix in WINDOW_EXEMPT)
        for match in re.finditer(r"\bTimelineView\s*\(", text):
            counted += 1
            opening = match.end() - 1
            fragment = text[opening : matching(text, opening) + 1]
            line = line_of(text, match.start())
            if not mentions_gate(fragment, names):
                findings.fail("motion", path, line, "a TimelineView whose schedule reads neither MotionBudget nor WindowAttention", (path, "motion", "TimelineView"))
            elif re.search(r"\b(?:paused|isStill)\s*:\s*(?:true|false)\b", fragment):
                findings.fail("motion", path, line, "a TimelineView paused by a literal rather than by its gate", (path, "motion", "TimelineView"))
            elif not exempt and not mentions_attention(fragment, watched):
                findings.fail("motion", path, line, "a TimelineView that never reads WindowAttention, so it runs in a hidden window", (path, "motion", "TimelineView"))
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
            if mentions_gate(window, names) and not exempt and not mentions_attention(window, watched):
                findings.fail("motion", path, line, f"`{match.group(0).strip()}` repeats without a WindowAttention gate nearby, so it runs in a hidden window", (path, "motion", match.group(0).strip()))
            elif mentions_gate(window, names):
                report.append(f"  ✓ {path}:{line} repeating animation gated")
            else:
                findings.fail("motion", path, line, f"`{match.group(0).strip()}` repeats without a MotionBudget or WindowAttention gate nearby", (path, "motion", match.group(0).strip()))
    report.append(f"  ✓ {counted} continuous animations read")


# Taking MLX's cache cap, directly or through the pass count that shares it across concurrent passes.
CACHE_HOLD = r"(?:\.hold|\bbeginPass|\b(?:bufferCachePasses|BufferCachePasses\s*\.\s*processWide)\s*\.\s*begin)\s*\(\s*\)"

# Clearing MLX's cache, directly or by ending the pass that the last one out clears for.
CACHE_CLEAR = r"(?:\.clear|\bendPass|\b(?:bufferCachePasses|BufferCachePasses\s*\.\s*processWide)\s*\.\s*end)\s*\(\s*\)"

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

        # The offsets of a function's own `.hold()` and `defer { … .clear() }`, not just
        # whether they appear — a defer registers when its statement runs, so one written
        # after the pass it is meant to guard never covers it, and neither does a `.hold()`
        # taken out only afterward.
        guard_pos = {}
        for name, start, opening, end, private in bodies:
            body = text[opening:end]
            hold_match = re.search(CACHE_HOLD, body)
            defer_match = re.search(r"\bdefer\s*\{[^}]*" + CACHE_CLEAR, body)
            guard_pos[(name, start)] = (
                opening + hold_match.start() if hold_match else None,
                opening + defer_match.start() if defer_match else None,
            )

        def covers(entry, position):
            """Whether entry's own hold()/defer(clear) both precede `position` in its body."""
            hold_pos, defer_pos = guard_pos[(entry[0], entry[1])]
            return hold_pos is not None and hold_pos < position and defer_pos is not None and defer_pos < position

        # A private helper with neither `.hold()` nor `defer { … .clear() }` of its own
        # relies entirely on whichever caller reaches it having already taken the cap
        # before that call — so propagation credits it only when every caller's own guard
        # precedes the specific line that calls it, not merely when the caller is guarded
        # somewhere in its body.
        guarded = {(name, start): guard_pos[(name, start)] != (None, None) for name, start, opening, end, private in bodies}

        def credit(entry, position):
            key = (entry[0], entry[1])
            if guard_pos[key] != (None, None):
                return covers(entry, position)
            return guarded[key]

        changed = True
        while changed:
            changed = False
            for name, start, opening, end, private in bodies:
                if guarded[(name, start)] or not private:
                    continue
                call_sites = [
                    (other, other[2] + call.start())
                    for other in bodies
                    if other[1] != start
                    for call in [re.search(r"(?<![\w])(?:self\.|Self\.)?" + name + r"\s*\(", text[other[2] : other[3]])]
                    if call
                ]
                if call_sites and all(credit(other, call_pos) for other, call_pos in call_sites):
                    guarded[(name, start)] = True
                    changed = True
        for match in PASS_CALL.finditer(text):
            owner = [entry for entry in bodies if entry[2] < match.start() < entry[3]]
            if not owner:
                continue
            passes += 1
            innermost = max(owner, key=lambda entry: entry[2])
            outermost_guarded = any(credit(entry, match.start()) for entry in owner)
            line = line_of(text, match.start())
            if outermost_guarded:
                report.append(f"  ✓ {path}:{line} pass inside {innermost[0]}(), which caps and clears the cache")
            else:
                findings.fail(
                    "cache", path, line,
                    f"a model pass in {innermost[0]}() that neither caps MLX's cache nor clears it before or after it",
                    (path, "cache", innermost[0]),
                )
        for name, start, opening, end, private in bodies:
            if name == "release" and not re.search(CACHE_CLEAR, text[opening:end]):
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
    "speech model, on disk": "speechModel",
    "recordings waiting for a retry": "recordings",
    "dictation history": "history",
    "clipboard, with its pictures": "clipboard",
    "diagnostics": "diagnostics",
    "other stores": "otherStores",
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


SUGGESTION_LIMITS = {
    "keystrokeReadsPerTurn": (1, r"primary Accessibility read per turn"),
    "keystrokeCallbackAXCalls": (0, r"Accessibility calls on the key callback"),
    "keystrokeCallbackAllocations": (0, r"allocations on the key callback"),
    "sameSuggestionDrawsPerKey": (0, r"duplicate panel draws for an unchanged suggestion"),
}


def check_suggestion_path(tree, findings, report):
    """Keep the documented keystroke limits tied to the source paths that enforce them."""
    doc = tree.read("Docs/performance.md")
    coordinator_path = "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift"
    panel_path = "Sources/Uttrflow/Suggestion/SuggestionPanelController.swift"
    coordinator = tree.files.get(coordinator_path, "")
    panel = tree.files.get(panel_path, "")
    turn_match = re.search(r"private func turn\([^)]*\) async\s*\{", coordinator)
    if turn_match:
        turn_opening = coordinator.find("{", turn_match.start())
        turn_body = coordinator[turn_opening : matching(coordinator, turn_opening) + 1]
    else:
        turn_body = ""
    primary_read = re.search(r"let read = shouldRead \? await FocusedFieldReader\.read\(\) : nil", turn_body)
    reader_calls = int(primary_read is not None)
    key_handler = re.search(r"private func keyPressed\([^)]*\)\s*\{", coordinator)
    if key_handler:
        opening = coordinator.find("{", key_handler.start())
        body = coordinator[opening : matching(coordinator, opening) + 1]
    else:
        body = ""
    monitor = re.search(r"addGlobalMonitorForEvents\(matching:\s*\[\.keyDown\]\)\s*\{", coordinator)
    if monitor:
        opening = coordinator.find("{", monitor.start())
        monitor_body = coordinator[opening : matching(coordinator, opening) + 1]
    else:
        monitor_body = ""
    limits = {}
    for name, (expected, label) in SUGGESTION_LIMITS.items():
        match = re.search(
            r"^\s*-\s*`" + re.escape(name) + r"`:\s*(\d+)\s+" + label + r"\s*$", doc, re.M | re.I
        )
        if not match:
            findings.failures.append(f"suggestions: Docs/performance.md has no numeric `{name}` limit")
            continue
        limits[name] = int(match.group(1))
        if limits[name] != expected:
            findings.failures.append(f"suggestions: `{name}` is {limits[name]}, expected {expected}")
        else:
            report.append(f"  ✓ {name}: {expected}")
    if reader_calls == 1:
        report.append("  ✓ one primary full field read in a coordinator turn")
    else:
        findings.failures.append(f"suggestions: expected one primary full field read in {coordinator_path}")
    primary_reads = re.findall(r"(?:let read = shouldRead \? await FocusedFieldReader\.read\(\)|let secondPrimaryRead = await FocusedFieldReader\.read\(\))", turn_body)
    if len(primary_reads) > 1:
        findings.fail(
            "suggestions", coordinator_path, 1, "two primary field reads can run in one turn",
            (coordinator_path, "reader-count"))
    if re.search(
        r"readStarted = Date\(\).*?FocusedFieldReader\.read\(\).*?readElapsed = Int\(Date\(\)\.timeIntervalSince\(readStarted\)",
        turn_body, re.S):
        report.append("  ✓ field-read duration starts before the cross-process read")
    else:
        findings.failures.append(f"suggestions: {coordinator_path} does not time the full field read")
    callback_source = re.sub(r"FocusedFieldReader\.focusMayHaveMoved\(\)", "", monitor_body)
    callback_allocations = re.sub(r"\.append\(text\)|\.append\(nil\)", "", callback_source)
    callback_allocations = re.sub(r"\[text\]", "", callback_allocations)
    if re.search(r"\b(?:FocusedFieldReader|AXUIElementCopy|AXUIElementSet|AXTextMarker)", callback_source + body):
        findings.fail("suggestions", coordinator_path, line_of(coordinator, monitor.start()) if monitor else 1, "the key callback performs an Accessibility call", (coordinator_path, "callback-ax"))
    elif key_handler and monitor:
        report.append("  ✓ key callback contains no Accessibility calls")
    else:
        findings.failures.append(f"suggestions: {coordinator_path} has no keyPressed callback")
    if re.search(r"\b(?:\[\]|\.append\(|\.map\s*\{|\.filter\s*\{|\.compactMap\s*\{|\.reduce\s*\{|\.sorted\s*\{|\bString\s*\()", callback_allocations):
        findings.fail("suggestions", coordinator_path, line_of(coordinator, monitor.start()) if monitor else 1, "the key callback contains an allocation-heavy operation", (coordinator_path, "callback-allocation"))
    elif key_handler and monitor:
        report.append("  ✓ key callback has no allocation-heavy collection or string work")
    same_draw_guards = re.findall(r"if isActuallyShowing, next\.draws\(sameAs: request\) \{ return true \}", panel)
    if len(same_draw_guards) < 2:
        findings.fail("suggestions", panel_path, 1, "identical visible suggestions are rendered again", (panel_path, "duplicate-draw"))
    else:
        report.append("  ✓ identical visible suggestions skip panel rendering")


# ---------------------------------------------------------------------------------------------------------------
# Latency: each stage's p95 against its budget, judged from a `uttrflow-dev bench` run
# ---------------------------------------------------------------------------------------------------------------

LATENCY_ROW = re.compile(r"^\|\s*`([\w:.-]+)`\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|", re.M)

# A stage's budget is its measured p95 times this; the one place the headroom is set.
LATENCY_HEADROOM = 1.2

# The current latency table names the commit it was measured at, so no older figure can pass for it.
LATENCY_COMMIT = re.compile(r"^\|\s*commit `[0-9a-f]{7,40}`\s*\|", re.M)

# The fewest samples a stage is judged on; fewer is a failure rather than a pass.
LATENCY_MIN_SAMPLES = 3

# The categories whose wait after key release has a budget, one per dictation length.
LATENCY_WAIT_CATEGORIES = ("dur5", "dur30", "dur120")

# Recognition's sub-stages as `uttrflow-dev bench` writes them on each `asr` event.
LATENCY_ASR_FIELDS = (
    "melSeconds", "encodeSeconds", "decoderSetupSeconds", "decodeSeconds", "wordTimingSeconds", "recognitionSeconds",
)


def latency_budget(p95):
    """The budget for a measured p95, rounded up to the table's 0.001 s."""
    return math.ceil(p95 * LATENCY_HEADROOM * 1000 - 1e-6) / 1000


def latency_section(doc):
    start = doc.find("## Latency budget per stage")
    if start < 0:
        return ""
    end = doc.find("\n## ", start + 1)
    return doc[start : end if end > 0 else len(doc)]


def latency_targets(doc):
    """The `stage -> (measured p95, budget)` rows of the stage budget table in Docs/performance.md."""
    return {m[1]: (float(m[2]), float(m[3])) for m in LATENCY_ROW.finditer(latency_section(doc))}


def check_latency_table(tree, findings, report):
    """Every budget is its measured p95 plus the headroom; whether a build meets them needs `--latency`."""
    doc = tree.read("Docs/performance.md")
    targets = latency_targets(doc)
    if not targets:
        findings.failures.append("latency: Docs/performance.md has no rows under `## Latency budget per stage`")
        return
    if not LATENCY_COMMIT.search(latency_section(doc)):
        findings.failures.append("latency: the current latency table names no `| commit `<hash>` |` it was measured at")
    findings.failures.extend(unearned_budgets(targets))
    report.extend(f"  ✓ {stage}: p95 {p95:.3f} s, budget {budget:.3f} s" for stage, (p95, budget) in sorted(targets.items()))


def unearned_budgets(targets):
    """One line per row whose budget is not its measured p95 times the headroom."""
    return [
        f"latency: `{stage}` budget {budget} is not its p95 {p95} x {LATENCY_HEADROOM} ({latency_budget(p95)})"
        for stage, (p95, budget) in sorted(targets.items())
        if p95 <= 0 or abs(budget - latency_budget(p95)) > 0.0005
    ]


def stage_samples(lines, corpus):
    """Seconds per stage, from clean audio, real-time mode and the shipping tidier only."""
    samples = {}
    for line in lines:
        if not line.startswith("BENCH "):
            continue
        event = json.loads(line[6:])
        clip = corpus.get(event.get("id"))
        if event.get("event") != "result" or clip is None or event.get("failed"):
            continue
        if clip["variant"] != "clean" or event.get("cleaner") != "shipping" or event.get("mode") != "rt":
            continue
        if clip["category"] in LATENCY_WAIT_CATEGORIES:
            samples.setdefault(f"wait:{clip['category']}", []).append(float(event["wait"]))
        for step in event.get("events", []):
            if step.get("kind") == "asr":
                for field in LATENCY_ASR_FIELDS:
                    samples.setdefault(f"asr:{field}", []).append(float(step[field]))
            elif step.get("kind") == "clean":
                samples.setdefault("clean", []).append(float(step["t1"]) - float(step["t0"]))
    return samples


def latency_breaches(targets, samples):
    """One line per stage over its budget, with too few samples, or left out of the run."""
    breaches, report = [], []
    for stage, (_, budget) in sorted(targets.items()):
        got = samples.get(stage, [])
        if len(got) < LATENCY_MIN_SAMPLES:
            breaches.append(f"latency: `{stage}` has {len(got)} sample(s), needs {LATENCY_MIN_SAMPLES}")
            continue
        p95 = bench.percentile(got, 95)
        line = f"{stage}: {len(got)} samples, p95 {p95:.3f}/{budget:.3f} s"
        if p95 > budget:
            breaches.append(f"latency: {line}")
        else:
            report.append(f"  ✓ {line}")
    return breaches, report


# The bench stage whose p95-plus-headroom row is each quality layer's latency budget, keyed by `QualityLayer` raw value.
LAYER_STAGES = {
    "recogniser-bias": "asr:recognitionSeconds",
    "evidence-capture": "asr:wordTimingSeconds",
    "candidate-generation": "correct",
    "scoring": "correct",
    "override-gate": "correct",
    "formatting": "clean",
}

# Layers whose stage has no measured row yet, each with its reason printed on every run; a measured one fails as stale.
LAYERS_UNMEASURED = {
    "candidate-generation": "runs in the dictionary's correction, which `uttrflow-dev bench` gives no dictionary to time",
    "scoring": "runs in the dictionary's correction, which `uttrflow-dev bench` gives no dictionary to time",
    "override-gate": "runs in the dictionary's correction, which `uttrflow-dev bench` gives no dictionary to time",
}

LAYER_CASE = re.compile(r"^\s*case\s+(\w+)(?:\s*=\s*\"([\w-]+)\")?\s*$", re.M)


def quality_layers(tree):
    """The raw value of every `QualityLayer` case, as the registry declares them."""
    text = tree.read("Sources/UttrflowCore/Support/QualityLayer.swift")
    start = text.find("enum QualityLayer")
    body = text[start : matching(text, text.find("{", start))] if start >= 0 else ""
    return [raw or name for name, raw in LAYER_CASE.findall(body)]


def check_layer_budgets(tree, findings, report):
    """Every quality layer's budget is the row of the stage it runs in, or it is listed as awaiting measurement."""
    targets = latency_targets(tree.read("Docs/performance.md"))
    layers = quality_layers(tree)
    if not layers:
        findings.failures.append("layers: no `QualityLayer` cases found in Sources/UttrflowCore/Support/QualityLayer.swift")
    for layer in layers:
        stage = LAYER_STAGES.get(layer)
        if stage is None:
            findings.failures.append(f"layers: `{layer}` names no bench stage in LAYER_STAGES, so it has no latency budget")
        elif stage in targets:
            if layer in LAYERS_UNMEASURED:
                findings.failures.append(f"stale: `{layer}` is measured as `{stage}`; remove it from LAYERS_UNMEASURED")
            else:
                report.append(f"  ✓ {layer}: `{stage}` budget {targets[stage][1]:.3f} s")
        elif layer in LAYERS_UNMEASURED:
            report.append(f"  - {layer}: `{stage}` unmeasured: {LAYERS_UNMEASURED[layer]}")
        else:
            findings.failures.append(f"layers: `{layer}` runs in `{stage}`, which has no row under `## Latency budget per stage`")
    for gone in sorted((set(LAYER_STAGES) | set(LAYERS_UNMEASURED)) - set(layers)):
        findings.failures.append(f"stale: `{gone}` is no longer a `QualityLayer`; remove it from LAYER_STAGES")


# The bench row each `StageTimeout` limit must equal, keyed by the limit's name.
STAGE_TIMEOUT_ROWS = {}

# Limits with no bench row yet, each with its reason printed on every run; one given a row fails as stale.
STAGE_TIMEOUTS_UNMEASURED = {
    "transcription": "`asr:recognitionSeconds` times one piece, not seconds per second of audio, so no length-scaled limit follows",
    "transformation": "the backstop around the route; `clean` sizes the route, not this stage",
    "route": "`clean` was measured on a loaded Mac and is to be re-measured on an idle one before a route limit follows it",
    "engine": "`clean` times the whole route, not one engine's turn",
    "rules": "`uttrflow-dev bench` never times the deterministic floor alone",
    "captureStop": "`uttrflow-dev bench` reads audio from a file, so it never stops a capture",
    "screenRead": "`uttrflow-dev bench` has no screen to read",
    "correction": "`uttrflow-dev bench` gives no dictionary to time",
    "expansion": "`uttrflow-dev bench` gives no snippets to time",
    "insertion": "`uttrflow-dev bench` inserts into no app",
    "speechModelLoad": "sized from the cold loads in Docs/startup.md, which bench runs after",
}

STAGE_TIMEOUT_LIMIT = re.compile(r"static let (\w+) = Duration\.(seconds|milliseconds)\(([\d.]+)\)")


def check_stage_timeouts(tree, findings, report):
    """Every `StageTimeout` limit equals its stage's p95-plus-headroom row, or is listed as awaiting measurement."""
    targets = latency_targets(tree.read("Docs/performance.md"))
    text = tree.read("Sources/UttrflowCore/Support/StageTimeout.swift")
    start = text.find("enum StageTimeout")
    body = text[start : matching(text, text.find("{", start))] if start >= 0 else ""
    limits = {name: float(value) * UNITS[unit] for name, unit, value in STAGE_TIMEOUT_LIMIT.findall(body)}
    if not limits:
        findings.failures.append("timeouts: no limits found in `enum StageTimeout`")
    for name, limit in sorted(limits.items()):
        stage = STAGE_TIMEOUT_ROWS.get(name)
        if stage is not None and name in STAGE_TIMEOUTS_UNMEASURED:
            findings.failures.append(f"stale: `{name}` follows `{stage}`; remove it from STAGE_TIMEOUTS_UNMEASURED")
        elif stage is not None and stage not in targets:
            findings.failures.append(f"timeouts: `{name}` follows `{stage}`, which has no row under `## Latency budget per stage`")
        elif stage is not None and abs(limit - targets[stage][1]) > 0.0005:
            findings.failures.append(f"timeouts: `{name}` is {limit:g} s, not its `{stage}` budget {targets[stage][1]:.3f} s")
        elif stage is not None:
            report.append(f"  ✓ {name}: {limit:g} s, the `{stage}` budget")
        elif name in STAGE_TIMEOUTS_UNMEASURED:
            report.append(f"  - {name}: {limit:g} s, unmeasured: {STAGE_TIMEOUTS_UNMEASURED[name]}")
        else:
            findings.failures.append(f"timeouts: `{name}` names no bench row in STAGE_TIMEOUT_ROWS and no reason it has none")
    for gone in sorted((set(STAGE_TIMEOUT_ROWS) | set(STAGE_TIMEOUTS_UNMEASURED)) - set(limits)):
        findings.failures.append(f"stale: `{gone}` is no longer a `StageTimeout` limit; remove it from the audit")


def read_run(run_path, corpus_path):
    with open(corpus_path, encoding="utf-8") as handle:
        corpus = {clip["id"]: clip for clip in json.load(handle)}
    with open(run_path, encoding="utf-8") as handle:
        return stage_samples(handle, corpus)


def performance_doc(root):
    with open(os.path.join(root, "Docs/performance.md"), encoding="utf-8") as handle:
        return handle.read()


def check_latency_run(root, run_path, corpus_path):
    breaches, report = latency_breaches(latency_targets(performance_doc(root)), read_run(run_path, corpus_path))
    print("\n".join(report))
    return breaches


def measure_latency(run_path, corpus_path):
    """Prints the budget table's rows for a run: each stage's p95 and that times the headroom."""
    for stage, got in sorted(read_run(run_path, corpus_path).items()):
        p95 = bench.percentile(got, 95)
        print(f"| `{stage}` | {p95:.3f} | {latency_budget(p95):.3f} | {len(got)} |")


def latency_self_test(root):
    """A run read back from bench lines at every budget passes; the same run 50% slower fails every stage."""
    targets = latency_targets(performance_doc(root))

    def run(scale):
        corpus, lines = {}, []
        for index in range(LATENCY_MIN_SAMPLES):
            for category in LATENCY_WAIT_CATEGORIES:
                clip_id = f"{category}-{index}"
                corpus[clip_id] = {"category": category, "variant": "clean"}
                wait = targets.get(f"wait:{category}", (0, 0))[1] * scale
                asr = {f: str(targets.get(f"asr:{f}", (0, 0))[1] * scale) for f in LATENCY_ASR_FIELDS}
                clean = targets.get("clean", (0, 0))[1] * scale
                events = [dict(asr, kind="asr"), {"kind": "clean", "t0": "1.0", "t1": str(1.0 + clean)}]
                lines.append("BENCH " + json.dumps({
                    "event": "result", "id": clip_id, "mode": "rt", "cleaner": "shipping", "wait": wait, "events": events}))
        return stage_samples(lines, corpus)

    met, _ = latency_breaches(targets, run(0.999))
    missed, _ = latency_breaches(targets, run(1.5))
    loosened = {stage: (p95, budget * 1.5) for stage, (p95, budget) in targets.items()}
    if unearned_budgets(targets) or len(unearned_budgets(loosened)) != len(targets):
        print("  ✗ latency: the table check does not catch a budget loosened past its p95 plus headroom")
        return 1
    if not targets or met or len(missed) != len(targets):
        print(f"  ✗ latency: on-budget run failed {len(met)}, 50% slower run failed {len(missed)} of {len(targets)}")
        return 1
    print(f"  ✓ latency catches a 50% slowdown on all {len(targets)} stages and passes a run within budget")
    return 0


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
        ("Suggestions: typing reads, callbacks and draws stay within their budget", lambda r: check_suggestion_path(tree, findings, r)),
        ("Latency: every stage budget is its measured p95 plus headroom", lambda r: check_latency_table(tree, findings, r)),
        ("Layers: every quality layer's budget is its stage's p95 plus headroom", lambda r: check_layer_budgets(tree, findings, r)),
        ("Timeouts: every stage limit is its stage's p95 plus headroom, or says why not", lambda r: check_stage_timeouts(tree, findings, r)),
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
        "            guard let vocabulary = self.vocabulary else { return [] }\n"
        "            // Only a call that reaches the model holds the process-wide cache; an unloaded scorer never does.\n"
        "            beginPass()\n            defer { endPass() }\n",
        "            guard let vocabulary = self.vocabulary else { return [] }\n", "cache",
    ),
    (
        "Sources/Uttrflow/Dock/DockView.swift",
        "paused: !motion.workingBarsMove", "paused: false", "motion",
    ),
    (
        "Sources/Uttrflow/Main/HomeHeroView.swift",
        "paused: !attended || !motion.workingBarsMove", "paused: !motion.workingBarsMove", "motion",
    ),
    (
        "Sources/UttrflowLocalModel/MLXCandidateScorer.swift",
        "        bufferCachePasses.begin()\n        await weights.unload()\n        bufferCachePasses.end()",
        "        await weights.unload()", "cache",
    ),
    (
        # The same guard, moved after the cached read it is meant to cap: a defer registers
        # when its statement runs, so it covers nothing written above it.
        "Sources/UttrflowLocalModel/MLXCandidateScorer.swift",
        "            // Only a call that reaches the model holds the process-wide cache; an unloaded scorer never does.\n"
        "            beginPass()\n            defer { endPass() }\n"
        "            let judged = await container.perform { loaded in\n",
        "            let judged = await container.perform { loaded in\n"
        "            beginPass()\n            defer { endPass() }\n",
        "cache",
    ),
    (
        "Sources/UttrflowLocalModel/GPUBufferCache.swift",
        "256 * 1_048_576", "1_024 * 1_048_576", "cache",
    ),
    (
        "Sources/UttrflowEval/ResourceBudget.swift",
        "case .idleSuggestionsOff: return 300", "case .idleSuggestionsOff: return 900", "counters",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift",
        "let read = shouldRead ? await FocusedFieldReader.read() : nil",
        "let read = shouldRead ? await FocusedFieldReader.read() : nil\n        let secondPrimaryRead = await FocusedFieldReader.read()",
        "suggestions", "two primary field reads",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift",
        "let readStarted = Date()\n        let read = shouldRead ? await FocusedFieldReader.read() : nil",
        "let read = shouldRead ? await FocusedFieldReader.read() : nil\n        let readStarted = Date()", "suggestions", "does not time the full field read",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift",
        "let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)",
        "let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)\n            _ = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), \"AXFocusedUIElement\" as CFString, nil)", "suggestions", "key callback performs an Accessibility call",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift",
        "let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)",
        "let text = Self.typedText(characters: event.characters, modifiers: event.modifierFlags)\n"
        "            let copy = text.map { [$0] }", "suggestions", "key callback contains an allocation-heavy operation",
    ),
    (
        "Docs/performance.md", "| commit `cfb11bf73` |", "| `cfb11bf73` |",
        "latency", "names no `| commit",
    ),
    (
        "Sources/UttrflowCore/Support/QualityLayer.swift",
        "    case formatting\n", "    case formatting\n    case persona\n",
        "layers", "`persona` names no bench stage",
    ),
    (
        "Docs/performance.md", "| `clean` | 5.557 | 6.669 | 75 |\n", "",
        "layers", "`formatting` runs in `clean`",
    ),
    (
        "Sources/UttrflowCore/Support/StageTimeout.swift",
        "    public static let insertion = Duration.seconds(15)\n",
        "    public static let insertion = Duration.seconds(15)\n    public static let probe = Duration.seconds(1)\n",
        "timeouts", "`probe` names no bench row",
    ),
    (
        "Sources/Uttrflow/Suggestion/SuggestionPanelController.swift",
        "if isActuallyShowing, next.draws(sameAs: request) { return true }",
        "if isActuallyShowing, next.draws(sameAs: request) { return false }",
        "suggestions", "identical visible suggestions are rendered again",
    ),
)


def self_test(root):
    """Injects each violation into the tree as read and confirms the audit fails on exactly that check."""
    print("\nSelf-test: each injected violation must fail its check")
    baseline_failures = audit(root, quiet=True).failures
    failed = 0
    for injection in INJECTIONS:
        path, find, replace, check = injection[:4]
        expected = injection[4] if len(injection) > 4 else None
        with open(os.path.join(root, path), encoding="utf-8") as handle:
            original = handle.read()
        if find not in original:
            print(f"  ✗ {path}: the injection site `{find[:60]}` is gone; update INJECTIONS")
            failed += 1
            continue
        injected = {path: original.replace(find, replace, 1)}
        caught = [
            failure for failure in audit(root, quiet=True, overrides=injected).failures
            if failure.startswith(check + ":")
        ]
        matched = [failure for failure in caught if expected is None or expected in failure]
        new_failure = check == "suggestions" and bool(matched) or any(
            failure not in baseline_failures for failure in matched
        )
        if new_failure:
            print(f"  ✓ {check} catches {path}: {matched[0].split(' ', 2)[-1]}")
        else:
            print(f"  ✗ {check} did not catch an injection into {path}")
            failed += 1
    return failed + latency_self_test(root)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="The wakeup check reads one file at a time and follows no calls: a sleep in a function a loop calls, "
        "two functions that schedule each other, or an interval set by another file's caller gets past it. "
        "See Docs/performance.md.",
    )
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--self-test", action="store_true", help="also prove each check fails on an injected violation")
    parser.add_argument("--latency", metavar="RUN", help="judge a `uttrflow-dev bench` run against the stage budgets instead")
    parser.add_argument("--measure", metavar="RUN", help="print the stage budget rows a `uttrflow-dev bench` run gives")
    parser.add_argument("--corpus", default=os.path.join(bench.DEFAULT_OUT, "corpus.json"), help="the run's corpus.json")
    options = parser.parse_args()
    if options.measure:
        measure_latency(options.measure, options.corpus)
        return 0
    if options.latency:
        breaches = check_latency_run(options.root, options.latency, options.corpus)
        for breach in breaches:
            print(f"  ✗ {breach}", file=sys.stderr)
        return 1 if breaches else 0
    findings = audit(options.root)
    if options.self_test and self_test(options.root):
        print("\n  ✗ the self-test found a check that no longer fails on its injected violation\n", file=sys.stderr)
        return 1
    if findings.failures:
        print(f"\n  ✗ {len(findings.failures)} breach(es) of the budget in Docs/performance.md:", file=sys.stderr)
        for failure in findings.failures:
            print(f"    {failure}", file=sys.stderr)
        print("    Fix the code, or list a wakeup with the reason it is not an idle cost.\n", file=sys.stderr)
        return 1
    print("\nperf budget audit: the source keeps to the budget.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Fails when a unified-log message interpolates a value named like user text, or publishes an error's description."""

import argparse
import os
import re
import sys

ROOTS = ("Sources",)

# A call on a logger: `Self.log.debug(`, `log.notice(`, `logger.error(`.
LOGGER_CALL = re.compile(r"\b(?:log|logger|[A-Za-z]+Log|[A-Za-z]+Logger)\.(?:debug|info|notice|error|fault|warning|trace|critical|log)\(")

# A file of log-message builders, every string literal in which is a log message; see `Docs/logging.md`.
BUILDER_FILE = re.compile(r"Log\.swift$")

# The names that mean user text, matched against every camelCase part of every identifier, plural or not.
USER_TEXT = (
    "typed", "text", "line", "value", "candidate", "completion", "prompt", "transcript", "spoken",
    "heard", "clip", "clipboard", "pasteboard", "word", "trigger", "expansion", "dropped",
    "surroundings", "preceding", "title", "document", "answer",
)

# What reduces a value to a size or a presence, which is what a log line may carry.
SHAPES = (
    re.compile(r"[\w$.?!]+?(?:\.(?:utf8|utf16|unicodeScalars))?\??\.(?:count|isEmpty)\b"),
    re.compile(r"[\w$.?!]+\s*[!=]==?\s*nil\b"),
)

# Interpolations that match a name above and carry no user text, each with the reason printed on every run.
ALLOWED = {
    ("Sources/Uttrflow/AppDelegate.swift", "clip.id"): "an identifier the store assigns, not the clip's contents",
    ("Sources/UttrflowLocalModel/MLXCandidateScorer.swift", "Int(info.promptTime * 1_000)"): (
        "how long the prompt took to prefill, in milliseconds"
    ),
}


# What describes a value in full, payload and all: an error's description can hold a path or the text it failed on.
DESCRIPTIONS = (
    re.compile(r"\bString\(\s*(?:describing|reflecting):"),
    re.compile(r"\.(?:localizedDescription|debugDescription|description)\b"),
    re.compile(r"^(?:self\.)?[a-z]*(?:error|failure|Error|Failure)s?$"),
)

# Public descriptions of values whose every case is fixed wording, each with the reason printed on every run.
DESCRIBED = {
    ("Sources/Uttrflow/AppDelegate.swift", "String(describing: method)"): "an InsertionArrival, a case with no payload",
    ("Sources/Uttrflow/AppDelegate.swift", "String(describing: became)"): "a LaunchAtLoginStatus, a case with no payload",
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", "String(describing: read?.placement)"): (
        "a SuggestionPlacement, a case with no payload"
    ),
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", "String(describing: failure)"): (
        "a KeyInterceptorFailure, a case with no payload"
    ),
    ("Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift", "String(describing: stroke.key)"): (
        "a KeyStroke.Key, a case with no payload"
    ),
    ("Sources/Uttrflow/Suggestion/SuggestionLog.swift", "String(describing: error)"): (
        "a TextInsertionError, whose one payload is fixed wording, or in `failure` a case with no payload"
    ),
}


def interpolations(text, start, end):
    """Yields (offset, expression) for every `\\(...)` inside a string literal between start and end."""
    index = start
    while index < end:
        if text.startswith('"""', index):
            closing = '"""'
            index += 3
        elif text[index] == '"':
            closing = '"'
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = end if newline < 0 else newline
            continue
        else:
            index += 1
            continue
        while index < end and not text.startswith(closing, index):
            if text.startswith("\\(", index):
                depth, cursor = 1, index + 2
                while cursor < end and depth:
                    depth += {"(": 1, ")": -1}.get(text[cursor], 0)
                    cursor += 1
                yield index, text[index + 2 : cursor - 1]
                index = cursor
            elif text[index] == "\\":
                index += 2
            else:
                index += 1
        index += len(closing)


def call_end(text, start):
    """The offset just past the parenthesis that closes the call opening at start."""
    depth, index, in_string = 0, start, False
    while index < len(text):
        character = text[index]
        if in_string:
            if character == "\\":
                index += 2
                continue
            if character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return len(text)


def value_of(expression):
    """The interpolated value without its `privacy:`, `format:` or `align:` arguments."""
    depth = 0
    for index, character in enumerate(expression):
        depth += {"(": 1, ")": -1, "[": 1, "]": -1}.get(character, 0)
        if character == "," and depth == 0 and re.match(r"\s*(?:privacy|format|align|attributes):", expression[index + 1 :]):
            return expression[:index].strip()
    return expression.strip()


def parts(identifier):
    """The lowercased camelCase parts of an identifier, each with a plural `s` taken off."""
    pieces = re.findall(r"[a-z]+|[A-Z][a-z]*", identifier)
    return [piece.lower()[:-1] if piece.lower().endswith("s") and len(piece) > 3 else piece.lower() for piece in pieces]


def sized_calls_removed(value):
    """The value with every call whose result is only measured, `a.b(c)?.count`, replaced by a number."""
    while True:
        match = re.search(r"\)\??\.(?:count|isEmpty)\b", value)
        if not match:
            return value
        depth, index = 0, match.start()
        while index >= 0:
            depth += {")": 1, "(": -1}.get(value[index], 0)
            if depth == 0:
                break
            index -= 1
        head = re.search(r"[\w$.?!]*$", value[: max(index, 0)])
        value = value[: head.start()] + "0" + value[match.end() :]


def user_text_names(value, builders=()):
    """The user-text names a value still carries once every size and presence test is taken out."""
    reduced = sized_calls_removed(re.sub(r'"(?:[^"\\]|\\.)*"', '""', value))
    for shape in SHAPES:
        reduced = shape.sub("0", reduced)
    if any(reduced.lstrip().startswith(builder + ".") for builder in builders):
        return []
    found = []
    for identifier in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", reduced):
        if identifier.endswith(("Count", "Length")) or identifier in ("rawValue", "hashValue"):
            continue
        if any(part in USER_TEXT for part in parts(identifier)):
            found.append(identifier)
    return found


def is_public(expression):
    """Whether an interpolation asks for its value to be published unredacted."""
    return re.search(r",\s*privacy:\s*\.public\b", expression) is not None


def described(value):
    """Whether a value is an error or a description of a value in full, which may carry its payload."""
    return any(pattern.search(value) for pattern in DESCRIPTIONS)


def findings_in(path, builders=(), text=None):
    """Yields (line, value, names) for each interpolation in a log message that carries user text or a public description; a builder's own calls are trusted, since its file is scanned whole."""
    if text is None:
        text = open(path, errors="ignore").read()
    builder = BUILDER_FILE.search(path) is not None
    spans = [(0, len(text), True)] if builder else []
    spans += [(match.end() - 1, call_end(text, match.end() - 1), False) for match in LOGGER_CALL.finditer(text)]
    for start, end, whole in spans:
        for offset, expression in interpolations(text, start, end):
            value = value_of(expression)
            names = user_text_names(value, builders)
            if names and (path, value) not in ALLOWED:
                yield text.count("\n", 0, offset) + 1, value, names
            elif (whole or is_public(expression)) and described(value) and (path, value) not in DESCRIBED:
                yield text.count("\n", 0, offset) + 1, value, ["public description"]


def swift_files():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            if ".build" in directory or ".claude" in directory:
                continue
            for name in sorted(names):
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


# Invented log calls, each with whether the audit must report it.
SELF_TEST = (
    ("Sources/A.swift", 'log.error("x: \\(String(describing: error), privacy: .public)")', True),
    ("Sources/A.swift", 'log.error("x: \\(String(reflecting: failure), privacy: .public)")', True),
    ("Sources/A.swift", 'log.error("x: \\(error.localizedDescription, privacy: .public)")', True),
    ("Sources/A.swift", 'log.error("x: \\(error, privacy: .public)")', True),
    ("Sources/A.swift", 'Self.log.error(\n "x: \\(self.loadError, privacy: .public)")', True),
    ("Sources/A.swift", 'log.error("x: \\(typed, privacy: .public)")', True),
    ("Sources/ALog.swift", 'static func f(_ error: any Error) -> String { "x \\(String(describing: error))" }', True),
    ("Sources/A.swift", 'log.error("x: \\(String(describing: error), privacy: .private)")', False),
    ("Sources/A.swift", 'log.error("x: \\(SuggestionLog.failure(error), privacy: .public)")', False),
    ("Sources/A.swift", 'log.error("x: \\(error.userMessage, privacy: .public)")', False),
    ("Sources/A.swift", 'log.error("x: \\(typed.count, privacy: .public)")', False),
)


def self_test():
    """Whether every invented call is reported exactly when it should be; prints each one that is not."""
    wrong = [
        (path, text) for path, text, expected in SELF_TEST if bool(list(findings_in(path, ["SuggestionLog"], text))) != expected
    ]
    for path, text in wrong:
        print(f"  ✗ self-test: {path}  {text}", file=sys.stderr)
    return not wrong


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="also prove the audit reports each invented violation")
    options = parser.parse_args()

    if options.self_test and not self_test():
        print("\nlog privacy audit: the self-test found a violation the audit no longer reports.\n", file=sys.stderr)
        return 1

    files = list(swift_files())
    if not files:
        print("log privacy audit: no Swift sources found; refusing to report a clean scan of nothing.")
        return 1

    print("\nWhat a log message may carry")
    print("  Allowed despite the name, with the reason:")
    for (path, value), reason in sorted(ALLOWED.items()):
        print(f"    {path}  \\({value})  {reason}")
    builders = [path for path in files if BUILDER_FILE.search(path)]
    print("  Described publicly, with the reason:")
    for (path, value), reason in sorted(DESCRIBED.items()):
        print(f"    {path}  \\({value})  {reason}")
    print("  Scanned whole, as log-message builders:")
    for path in builders or ["(none)"]:
        print(f"    {path}")

    trusted = [os.path.basename(path)[: -len(".swift")] for path in builders]
    sys.stdout.flush()
    failures = [(path, line, value, names) for path in files for line, value, names in findings_in(path, trusted)]
    stale = [key for key in (*ALLOWED, *DESCRIBED) if not os.path.isfile(key[0])]
    for path, value in stale:
        print(f"\n  ✗ the allow-list names {path}, which no longer exists", file=sys.stderr)

    if failures:
        print(f"\n  ✗ {len(failures)} log interpolation(s) carry text a person typed, read or said, or a public description:", file=sys.stderr)
        for path, line, value, names in failures:
            print(f"    {path}:{line}  \\({value})  [{', '.join(names)}]", file=sys.stderr)
        print("    The unified log keeps what it is given, and `.private` is readable on a Mac set to", file=sys.stderr)
        print("    reveal it. Log a length or a count instead (`.count`, `!= nil`), and an error by its type and", file=sys.stderr)
        print("    case (`SuggestionLog.failure`); see `Docs/logging.md`.", file=sys.stderr)
        return 1
    if stale:
        return 1

    print(f"\nlog privacy audit: {len(files)} files, no log message carries user text.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

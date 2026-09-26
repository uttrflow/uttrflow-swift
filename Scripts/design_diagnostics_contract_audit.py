#!/usr/bin/env python3
"""Fails when the Diagnostics artboards drift from `DiagnosticsPresentation`'s own contract.

#1137 found `Design/_gen_main.py`'s Diagnostics section describing a different product from
the shipped page: a plain `2.62s` total from only three stages, "target under 5s", two
invented reliability figures ("Heard you" / "Typed directly"), invented memory figures, and
timings said to be "measured ... over the last 7 days". Production instead measures eight
pipeline stages, marks an incomplete total "at least" and lists every unmeasured stage as
"Never run", reports reliability per measured stage, and keeps timings in memory only "since
Uttrflow started" — with no memory figures and no duration target anywhere.

This reads `PipelineStage`'s case order from `Metrics.swift`, and `title(for:)`, the
`footnote` and `noTimingsYet`'s title/message from `DiagnosticsPresentation.swift`, then
fails unless `Design/_gen_main.py`'s Diagnostics section spells all eight stage titles, the
footnote and the empty-state copy verbatim, still says "at least" and "Never run" for an
incomplete total, and fails outright if any of the retired claims — a five-second target, a
memory figure, a seven-day window, or the old two-way "Heard you" / "Typed directly"
reliability pair — reappears.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
METRICS_SOURCE = os.path.join(REPO_ROOT, "Sources", "UttrflowCore", "Support", "Metrics.swift")
PRESENTER_SOURCE = os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "DiagnosticsPresentation.swift")
GENERATOR_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_main.py")

STAGE_ENUM = re.compile(r"enum PipelineStage\b.*?\{(?P<body>.*?)\n\}", re.S)
STAGE_CASE = re.compile(r"case (\w+)$", re.M)

TITLE_FUNC = re.compile(
    r"static func title\(for stage: PipelineStage\) -> String \{(?P<body>.*?)\n    \}", re.S
)
TITLE_CASE = re.compile(r'case \.(\w+): "([^"]+)"')

FOOTNOTE_DECL = re.compile(r'static let footnote =\s*\n?\s*"([^"]+)"')
NO_TIMINGS_TITLE = re.compile(r'noTimingsYet = MainEmptyState\(.*?title: "([^"]+)"', re.S)
NO_TIMINGS_MESSAGE = re.compile(r'noTimingsYet = MainEmptyState\(.*?message: "([^"]+)"\)', re.S)

# Claims production makes nowhere and the generator must not reintroduce.
RETIRED_PATTERNS = [
    (re.compile(r"target under \d"), "a duration target (\"target under Ns\")"),
    (re.compile(r"[Ii]dle memory"), '"Idle memory"'),
    (re.compile(r"[Pp]eak memory"), '"Peak memory"'),
    (re.compile(r"last 7 days"), 'a seven-day measurement window ("last 7 days")'),
    (re.compile(r"[Hh]eard you"), '"Heard you"'),
    (re.compile(r"[Tt]yped directly"), '"Typed directly"'),
]


def stage_order_from_text(text, source="<text>"):
    """`PipelineStage`'s cases, in the declared (running) order."""
    match = STAGE_ENUM.search(text)
    if not match:
        raise SystemExit(f"diagnostics contract audit: no PipelineStage enum found in {source}")
    return STAGE_CASE.findall(match.group("body"))


def titles_from_text(text, source="<text>"):
    """`DiagnosticsPresenter.title(for:)`'s stage -> title mapping, in switch order."""
    match = TITLE_FUNC.search(text)
    if not match:
        raise SystemExit(f"diagnostics contract audit: no title(for:) function found in {source}")
    pairs = TITLE_CASE.findall(match.group("body"))
    if not pairs:
        raise SystemExit(f"diagnostics contract audit: title(for:) parsed with no cases in {source}")
    return pairs


def presenter_strings_from_text(text, source="<text>"):
    """Returns (footnote, noTimingsYet title, noTimingsYet message), exactly as declared."""
    footnote = FOOTNOTE_DECL.search(text)
    title = NO_TIMINGS_TITLE.search(text)
    message = NO_TIMINGS_MESSAGE.search(text)
    if not footnote:
        raise SystemExit(f"diagnostics contract audit: no footnote declaration found in {source}")
    if not title or not message:
        raise SystemExit(f"diagnostics contract audit: no noTimingsYet declaration found in {source}")
    return footnote.group(1), title.group(1), message.group(1)


def diagnostics_section(path):
    """The generator's Diagnostics section: from its own marker to the `written` loop."""
    text = open(path).read()
    start = text.find("# ---- Diagnostics")
    end = text.find("written = []", start)
    if start == -1 or end == -1:
        raise SystemExit(
            f"diagnostics contract audit: could not isolate the Diagnostics section of {path}"
        )
    return text[start:end]


def audit_failures(section, stage_order, titles, footnote, no_timings_title, no_timings_message):
    failures = []

    declared_stages = [stage for stage, _ in titles]
    if declared_stages != stage_order:
        failures.append(
            "title(for:) and the PipelineStage enum have drifted apart "
            f"({declared_stages!r} vs {stage_order!r}); fix the Swift source before the artboard"
        )

    for _, title in titles:
        if title not in section:
            failures.append(f"the generator's Diagnostics section never spells {title!r} verbatim")

    if footnote not in section:
        failures.append(f"the generator's Diagnostics section never spells the footnote verbatim ({footnote!r})")

    if no_timings_title not in section:
        failures.append(f"the generator never spells noTimingsYet's title verbatim ({no_timings_title!r})")

    if no_timings_message not in section:
        failures.append(f"the generator never spells noTimingsYet's message verbatim ({no_timings_message!r})")

    if "at least" not in section:
        failures.append('the generator never qualifies an incomplete total with "at least"')

    if "Never run" not in section:
        failures.append('the generator never draws an unmeasured stage as "Never run"')

    for pattern, description in RETIRED_PATTERNS:
        if pattern.search(section):
            failures.append(f"the generator's Diagnostics section still claims {description}")

    return failures


def audit_pairs():
    for path in (METRICS_SOURCE, PRESENTER_SOURCE, GENERATOR_SOURCE):
        if not os.path.isfile(path):
            raise SystemExit(f"diagnostics contract audit: {path} not found")

    stage_order = stage_order_from_text(open(METRICS_SOURCE).read(), METRICS_SOURCE)
    presenter_text = open(PRESENTER_SOURCE).read()
    titles = titles_from_text(presenter_text, PRESENTER_SOURCE)
    footnote, no_timings_title, no_timings_message = presenter_strings_from_text(
        presenter_text, PRESENTER_SOURCE)
    section = diagnostics_section(GENERATOR_SOURCE)
    return audit_failures(section, stage_order, titles, footnote, no_timings_title, no_timings_message)


def self_test():
    """Proves the extractors resolve known-good fixtures and the regressions they catch."""
    ok = True

    metrics_fixture = (
        "public enum PipelineStage: String, Sendable, Equatable, CaseIterable, Codable {\n"
        "    case microphoneOpen\n"
        "    case capture\n"
        "}\n"
        "public struct StageMeasurement {}\n"
    )
    stage_order = stage_order_from_text(metrics_fixture)
    if stage_order != ["microphoneOpen", "capture"]:
        print("  ✗ self-test: PipelineStage extraction failed", file=sys.stderr)
        ok = False

    presenter_fixture = (
        '    static let footnote =\n'
        '        "Measured on this Mac since Uttrflow started, and never sent anywhere."\n'
        '    static let noTimingsYet = MainEmptyState(\n'
        '        symbolName: "gauge.with.dots.needle.bottom.50percent",\n'
        '        title: "No timings yet",\n'
        '        message: "Dictate something and the times appear here. They stay on this Mac.")\n'
        '    static func title(for stage: PipelineStage) -> String {\n'
        '        switch stage {\n'
        '        case .microphoneOpen: "Opening the microphone"\n'
        '        case .capture: "Recording"\n'
        '        }\n'
        '    }\n'
    )
    titles = titles_from_text(presenter_fixture)
    footnote, no_timings_title, no_timings_message = presenter_strings_from_text(presenter_fixture)
    if titles != [("microphoneOpen", "Opening the microphone"), ("capture", "Recording")]:
        print("  ✗ self-test: title(for:) extraction failed", file=sys.stderr)
        ok = False
    if footnote != "Measured on this Mac since Uttrflow started, and never sent anywhere.":
        print("  ✗ self-test: footnote extraction failed", file=sys.stderr)
        ok = False
    if no_timings_title != "No timings yet" or "Dictate something" not in no_timings_message:
        print("  ✗ self-test: noTimingsYet extraction failed", file=sys.stderr)
        ok = False

    good_section = (
        "# ---- Diagnostics\n"
        "Opening the microphone Recording at least 2.15s Never run "
        "Measured on this Mac since Uttrflow started, and never sent anywhere. "
        "No timings yet Dictate something and the times appear here. They stay on this Mac.\n"
        "written = []"
    )
    if audit_failures(good_section, stage_order, titles, footnote, no_timings_title, no_timings_message):
        print("  ✗ self-test: a known-good fixture was flagged", file=sys.stderr)
        ok = False

    missing_stage = good_section.replace("Recording", "")
    if not audit_failures(missing_stage, stage_order, titles, footnote, no_timings_title, no_timings_message):
        print('  ✗ self-test: a missing stage title was not flagged', file=sys.stderr)
        ok = False

    no_qualifier = good_section.replace("at least 2.15s", "2.15s")
    if not audit_failures(no_qualifier, stage_order, titles, footnote, no_timings_title, no_timings_message):
        print('  ✗ self-test: a dropped "at least" was not flagged', file=sys.stderr)
        ok = False

    for retired in ("target under 5s", "Idle memory", "Peak memory", "last 7 days", "Heard you", "Typed directly"):
        regressed = good_section + f" {retired}"
        if not audit_failures(regressed, stage_order, titles, footnote, no_timings_title, no_timings_message):
            print(f"  ✗ self-test: a restored {retired!r} claim was not flagged", file=sys.stderr)
            ok = False

    return ok


def audit():
    failures = audit_pairs()
    if failures:
        print(f"\n  ✗ {len(failures)} Diagnostics artboard contract violation(s):", file=sys.stderr)
        for message in failures:
            print(f"    {message}", file=sys.stderr)
        print(
            "    Update Design/_gen_main.py's Diagnostics section to match\n"
            "    Sources/UttrflowUX/DiagnosticsPresentation.swift and\n"
            "    Sources/UttrflowCore/Support/Metrics.swift, then regenerate both\n"
            "    Main-Diagnostics and Main-Diagnostics-Empty artboards.",
            file=sys.stderr,
        )
        return 1

    print(
        "diagnostics contract audit: the Diagnostics section matches DiagnosticsPresentation, "
        "with no retired memory, target or window claims.\n"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the extractors resolve known-good fixtures and catch known regressions",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print("\ndiagnostics contract audit: self-test failed; the parser is broken.\n", file=sys.stderr)
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())

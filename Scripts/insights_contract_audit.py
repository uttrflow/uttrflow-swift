#!/usr/bin/env python3
"""Fails when the Insights artboard generator disagrees with InsightsPresentation.

The Insights artboards once drew a contract production never had: a popup scope, a restored
Baseline meter and a "Languages you spoke" card with no measured source. Later production
was redesigned as a calendar with a range switch and the generator was not. Both drifts had
the same cause: nothing tied `Design/_gen_app.py`'s Insights section to
`Sources/UttrflowUX/InsightsPresentation.swift`.

This reads both sides and fails unless the generator draws what the presenter builds:

1. The range switch offers exactly `InsightsRange`'s titles, and the empty screen draws none.
2. The calendar's legend steps through `InsightsCalendar.legend`, its tiles snap at
   `inkCeiling` and `deepInkFloor`, and the day fixture covers the range it claims.
3. The four dictation figures and five suggestion figures carry the presenter's captions, in order.
4. The empty state spells the presenter's title and message.
5. No retired claim returns: a popup scope, an Accuracy or Baseline meter, an average line,
   a per-app breakdown or a language card.

Needs no build: it is a source-level check, like `design_contrast_audit.py`.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
GEN_APP_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_app.py")
INSIGHTS_PRESENTER_SOURCE = os.path.join(
    REPO_ROOT, "Sources", "UttrflowUX", "InsightsPresentation.swift"
)
INSIGHTS_RANGE_SOURCE = os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "InsightsRange.swift")
INSIGHTS_DAY_SOURCE = os.path.join(REPO_ROOT, "Sources", "UttrflowUX", "InsightsCalendarDay.swift")

SECTION_START = "# Insights — only what the app already measures."

# What production no longer draws, each with the wording that would bring it back.
RETIRED = (
    (re.compile(r"pop\(\s*[\"']"), "a popup scope"),
    (re.compile(r"Baseline"), "a Baseline meter"),
    (re.compile(r"Left as dictated|Accuracy"), "an Accuracy tile"),
    (re.compile(r"avgline"), "an average line over bars"),
    (re.compile(r"Where you dictate|PLACES\s*="), "a per-app breakdown"),
    (re.compile(r"Languages you spoke|Hinglish|LANGS\s*="), "a language card"),
)


def insights_section(text):
    """The generator's Insights block, so a string from another page is not caught here."""
    start = text.find(SECTION_START)
    if start == -1:
        raise SystemExit(f"insights contract audit: no {SECTION_START!r} marker in {GEN_APP_SOURCE}")
    # The title line is framed by a rule above and below; skip the closing rule first.
    body_start = text.find("\n", start + len(SECTION_START))
    body_start = text.find("\n", body_start + 1)
    end = text.find("\n# =====", body_start)
    if end == -1:
        raise SystemExit("insights contract audit: could not find the end of the Insights section")
    return text[start:end]


def presenter_contract(swift, range_swift, day_swift):
    """The ranges, legend, ink thresholds, figure captions and empty wording the presenter builds."""
    ranges = [int(days) for days in re.findall(r"case \w+ = \"(\d+)\"", range_swift)]
    title = re.search(r'public var title: String \{ "\\\(days\) days" \}', range_swift)
    legend = re.search(r"static let legend: \[Double\] = \[([^\]]*)\]", swift)
    ceiling = re.search(r"static let inkCeiling = ([0-9.]+)", day_swift)
    floor = re.search(r"static let deepInkFloor = ([0-9.]+)", day_swift)
    figures = swift[swift.find("static func figures(") : swift.find("static func dailyAverage(")]
    captions = re.findall(r'caption: "([^"]+)"\)', figures)
    suggestion_start = swift.find("private static func suggestionFigures(")
    suggestion_end = swift.find("// MARK: - The range", suggestion_start)
    suggestion_figures = swift[suggestion_start:suggestion_end]
    suggestion_captions = re.findall(r'caption: "([^"]+)"\)', suggestion_figures)
    empty_title = re.search(r'title: "(Not enough[^"]*)"', swift)
    empty_message = re.search(r"Dictate on \\\(daysBeforeCharting\) ([^\\]*)\\", swift)
    before = re.search(r"static let daysBeforeCharting = (\d+)", swift)
    missing = [
        name for name, found in (
            ("InsightsRange.title", title), ("InsightsCalendar.legend", legend),
            ("inkCeiling", ceiling), ("deepInkFloor", floor), ("the empty title", empty_title),
            ("the empty message", empty_message), ("daysBeforeCharting", before),
        ) if not found
    ]
    if missing or not ranges or len(captions) != 4 or len(suggestion_captions) != 5:
        raise SystemExit(
            "insights contract audit: InsightsPresentation.swift no longer has the shape this "
            f"audit reads ({', '.join(missing) or 'ranges or figure captions'}); "
            "update this audit to the new contract, not just the artboard")
    return {
        "ranges": [f"{days} days" for days in ranges],
        "legend": [float(value) for value in legend.group(1).split(",")],
        "ink_ceiling": float(ceiling.group(1)),
        "deep_ink_floor": float(floor.group(1)),
        "captions": captions,
        "suggestion_captions": suggestion_captions,
        "empty_title": empty_title.group(1),
        "empty_message": f"Dictate on {before.group(1)} {empty_message.group(1).strip()}",
        "days_before_charting": int(before.group(1)),
    }


def python_list(section, name):
    match = re.search(rf"^{name} = \[([^\]]*)\]", section, re.M)
    return None if match is None else [item.strip() for item in match.group(1).split(",") if item.strip()]


def audit_failures(section, screens, contract):
    failures = []

    # ---- 1. The range switch. -------------------------------------------------------------
    ranges = python_list(section, "RANGES")
    if ranges is None or [f"{days} days" for days in ranges] != contract["ranges"]:
        failures.append(
            f"RANGES is {ranges!r}; InsightsRange offers {contract['ranges']!r}")
    if 'RANGE_TITLES = [f"{days} days" for days in RANGES]' not in section:
        failures.append('RANGE_TITLES is not built as "N days" from RANGES, as InsightsRange.title is')
    if "seg(RANGE_TITLES, SELECTED_TITLE)" not in screens.get("Main-Insights", ""):
        failures.append("Main-Insights does not draw the range switch from RANGE_TITLES")
    if screens.get("Main-Insights-Empty", "").split(",")[0].strip() != '""':
        failures.append("Main-Insights-Empty draws a scope; the presenter offers no range before the calendar")

    # ---- 2. The calendar. -----------------------------------------------------------------
    legend = python_list(section, "LEGEND")
    if legend is None or [float(value) for value in legend] != contract["legend"]:
        failures.append(f"LEGEND is {legend!r}; InsightsCalendar.legend is {contract['legend']!r}")
    for name, key, swift_name in (
        ("INK_CEILING", "ink_ceiling", "inkCeiling"), ("DEEP_INK_FLOOR", "deep_ink_floor", "deepInkFloor"),
    ):
        match = re.search(rf"^{name} = ([0-9.]+)", section, re.M)
        if match is None or float(match.group(1)) != contract[key]:
            failures.append(f"{name} does not match InsightsCalendarDay.{swift_name}")
    if "assert len(DAYS) == SELECTED_RANGE" not in section:
        failures.append("the DAYS fixture is not asserted against SELECTED_RANGE, so the calendar can claim one range and draw another")
    if "less {legend_swatches} more" not in section:
        failures.append('the legend does not run from "less" to "more"')

    # ---- 3. The four figures. -------------------------------------------------------------
    captions = python_list(section, "FIGURE_CAPTIONS")
    if captions is None or [caption.strip("\"'") for caption in captions] != contract["captions"]:
        failures.append(
            f"FIGURE_CAPTIONS is {captions!r}; InsightsPresenter.figures captions "
            f"{contract['captions']!r}")
    suggestion_captions = python_list(section, "SUGGESTION_CAPTIONS")
    if suggestion_captions is None or [caption.strip("\"'") for caption in suggestion_captions] != contract[
        "suggestion_captions"
    ]:
        failures.append(
            f"SUGGESTION_CAPTIONS is {suggestion_captions!r}; presenter captions "
            f"{contract['suggestion_captions']!r}")
    if "{suggestion_insights}" not in section:
        failures.append("the filled Insights artboard does not include the suggestion counts group")
    for wording in ("Suggestions</div>", "Stored corpus totals on this Mac."):
        if wording not in section:
            failures.append(f"the suggestion group does not include {wording!r}")
    empty_generator = section[section.find("insights_empty =") :]
    if "{suggestion_insights}" not in empty_generator:
        failures.append("the empty Insights artboard does not include the suggestion counts group")

    # ---- 4. The empty state. --------------------------------------------------------------
    if f'EMPTY_TITLE = "{contract["empty_title"]}"' not in section:
        failures.append(f"the empty state does not say {contract['empty_title']!r}")
    message = re.sub(r"\s+", " ", contract["empty_message"])
    drawn = re.sub(r"\s+", " ", section).replace(
        "{DAYS_BEFORE_CHARTING}", str(contract["days_before_charting"]))
    if message not in drawn:
        failures.append(f"the empty state's message does not say {message!r}")

    # ---- 5. Nothing retired comes back. ---------------------------------------------------
    for pattern, description in RETIRED:
        if pattern.search(section):
            failures.append(f"the Insights section still draws {description}")

    return failures


def screens_rows(text):
    """Each Insights SCREENS row's text after its caption, keyed by artboard name."""
    rows = {}
    for match in re.finditer(r'\("(Main-Insights(?:-Empty)?)", "Insights", INSIGHTS_CAPTION,\s*([^\n]*)', text):
        rows[match.group(1)] = match.group(2)
    return rows


def audit():
    text = open(GEN_APP_SOURCE).read()
    contract = presenter_contract(
        open(INSIGHTS_PRESENTER_SOURCE).read(), open(INSIGHTS_RANGE_SOURCE).read(),
        open(INSIGHTS_DAY_SOURCE).read())
    failures = audit_failures(insights_section(text), screens_rows(text), contract)
    print("Insights artboard vs InsightsPresentation contract")
    if failures:
        print(f"\n  ✗ {len(failures)} mismatch(es):", file=sys.stderr)
        for failure in failures:
            print(f"    - {failure}", file=sys.stderr)
        return 1
    print("  ✓ range switch, calendar, figures and empty state match; nothing retired returns\n")
    print("insights contract audit: Design/_gen_app.py's Insights section matches InsightsPresentation.\n")
    return 0


def self_test():
    """The real generator passes, and each injected drift is caught."""
    text = open(GEN_APP_SOURCE).read()
    contract = presenter_contract(
        open(INSIGHTS_PRESENTER_SOURCE).read(), open(INSIGHTS_RANGE_SOURCE).read(),
        open(INSIGHTS_DAY_SOURCE).read())
    section, screens = insights_section(text), screens_rows(text)
    if audit_failures(section, screens, contract):
        print("  ✗ self-test: the generator as it stands does not pass; run the audit itself", file=sys.stderr)
        return False
    injections = (
        ("RANGES = [7, 30, 90]", "RANGES = [7, 14, 30]", None),
        ("LEGEND = [0.15, 0.4, 0.72, 0.9]", "LEGEND = [0.2, 0.4, 0.6, 0.8]", None),
        ('"words / min"', '"words per minute"', None),
        ('"Self-sourced"]', '"Self-sourced entries"]', None),
        ("assert len(DAYS) == SELECTED_RANGE", "", None),
        (f'EMPTY_TITLE = "{contract["empty_title"]}"', 'EMPTY_TITLE = "Nothing yet"', None),
        ("insights = f\"\"\"", "PLACES = []\ninsights = f\"\"\"", None),
        (None, None, ("Main-Insights", 'pop("Last 30 days"), "", "", insights, RECENT, TAILS),')),
        (None, None, ("Main-Insights-Empty", 'seg(RANGE_TITLES, SELECTED_TITLE), "", "", insights_empty,')),
    )
    ok = True
    for find, replace, screen in injections:
        if screen:
            broken_screens = dict(screens)
            broken_screens[screen[0]] = screen[1]
            broken_section = section
        else:
            if find not in section:
                print(f"  ✗ self-test: the injection site {find!r} is gone; update the self-test", file=sys.stderr)
                ok = False
                continue
            broken_section, broken_screens = section.replace(find, replace, 1), screens
        if not audit_failures(broken_section, broken_screens, contract):
            print(f"  ✗ self-test: an injected drift was not caught ({find or screen[0]!r})", file=sys.stderr)
            ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test", action="store_true", help="prove the audit passes the generator and catches each drift")
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print("\ninsights contract audit: self-test failed.\n", file=sys.stderr)
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())
